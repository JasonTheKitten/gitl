local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local gitobj = localRequire("lib/gitl/gitobj")
local filesystem = driver.filesystem
local read32BitNumber, write32BitNumber, read16BitNumber, write16BitNumber, read20ByteHash, write20ByteHash =
  utils.read32BitNumber, utils.write32BitNumber, utils.read16BitNumber,
  utils.write16BitNumber, utils.read20ByteHash, utils.write20ByteHash

local function createIndex()
  local index = {}
  index.entries = {}
  index.version = 2
  return index
end

local function findEntry(index, name)
  local startIndex, endIndex = 1, #index.entries
  while startIndex <= endIndex do
    local middleIndex = math.floor((startIndex + endIndex) / 2)
    local middleEntry = index.entries[middleIndex]
    if middleEntry.name == name then
      return middleIndex
    elseif middleEntry.name < name then
      startIndex = middleIndex + 1
    else
      endIndex = middleIndex - 1
    end
  end
end

local function formatEntryName(entry)
  if entry == nil then return nil end
  return entry.type == "tree" and (entry.name .. "/\0") or (entry.name .. "\0")
end

local function insertEntry(index, entry)
  local entryName = formatEntryName(entry)
  if (#index.entries == 0) or (formatEntryName(index.entries[#index.entries]) < entryName) then
    table.insert(index.entries, entry)
    return
  end
  if formatEntryName(index.entries[1]) > entryName then
    table.insert(index.entries, 1, entry)
    return
  end
  local startIndex, endIndex = 1, #index.entries
  while startIndex <= endIndex do
    local middleIndex = math.floor((startIndex + endIndex) / 2)
    local middleEntry = index.entries[middleIndex]
    local middleEntryName = formatEntryName(middleEntry)

    if middleEntryName == entryName then
      table.insert(index.entries, middleIndex, entry)
      return
    elseif middleEntryName < entryName then
      startIndex = middleIndex + 1
    else
      endIndex = middleIndex - 1
    end
  end
  table.insert(index.entries, startIndex, entry)
end


local function getOrCreateEntry(index, name, default)
  local entryIndex = findEntry(index, name)
  if entryIndex then
    return index.entries[entryIndex]
  end
  insertEntry(index, default)
  return default
end

local function removeEntry(index, name)
  local entryIndex = findEntry(index, name)
  if entryIndex then
    table.remove(index.entries, entryIndex)
  end
end

local function updateEntry(index, name, entry)
  local entryIndex = findEntry(index, name)
  if entryIndex then
    local newEntry = {}
    local oldEntry = index.entries[entryIndex]
    for key, value in pairs(oldEntry) do
      newEntry[key] = value
    end
    for key, value in pairs(entry) do
      newEntry[key] = value
    end
    index.entries[entryIndex] = newEntry
  else
    insertEntry(index, entry)
  end
end

local function getEntry(index, name)
  local entryIndex = findEntry(index, name)
  if entryIndex then
    return index.entries[entryIndex]
  end
end

local function reduceEntries(index, filter)
  local newEntries = {}
  for _, entry in ipairs(index.entries) do
    if filter(entry) then
      table.insert(newEntries, entry)
    end
  end
  index.entries = newEntries
end

--

local function compareEntries(entry1, entry2)
  if entry1 == nil then
    return false
  end
  for key, value in pairs(entry1) do
    local altVal = entry2[key]
    if (altVal ~= nil) and (value ~= altVal) and (key ~= "hash") and (key ~= "name") then
      return false
    end
  end
  return true
end

-- It seems that git doesn't retain the actual Unix perms,
-- and instead chooses one of a few options based on the file's mode
local function isX(str, index)
  return str:sub(index, index) == "x"
end
local function selectGitPerm(str)
  if str == nil then
    return 420
  end

  if isX(str, 3) or isX(str, 6) or isX(str, 9) then
    return 493
  end

  return 420
end

local addToIndex
addToIndex = function(gitDir, index, path, indexPath, filter, skipWrite)
  if indexPath:sub(1, 1) == "/" then
    indexPath = indexPath:sub(2)
  end
  path = filesystem.collapse(path)

  local existingEntry = getEntry(index, indexPath)
  if not filter(indexPath) then
    -- Ignore
  elseif filesystem.isDir(path) then
    for _, file in ipairs(filesystem.list(path)) do
      addToIndex(gitDir, index, filesystem.combine(path, file), filesystem.combine(indexPath, file), filter, skipWrite)
    end
  elseif filesystem.isFile(path) and not compareEntries(existingEntry, filesystem.attributes(path)) then
    local fileAttributes = filesystem.attributes(path)

    local fileHandle = assert(io.open(path, "rb"))
    local content = fileHandle:read("*a")
    fileHandle:close()

    local permNum = selectGitPerm(fileAttributes.fmode)
    fileAttributes.fmode = nil
    fileAttributes.mode = utils.shl(8, 12) + permNum

    if not skipWrite then
      fileAttributes.hash = gitobj.writeObject(gitDir, content, "blob")
    end
    fileAttributes.name = indexPath
    updateEntry(index, indexPath, fileAttributes)
  elseif not filesystem.exists(path) then
    removeEntry(index, indexPath)
  end
end

local removeFromIndex
removeFromIndex = function(index, indexPath, recursive)
  if not recursive then
    removeEntry(index, indexPath)
    return
  end

  reduceEntries(index, function(entry)
    local isFileMatch = entry.name == indexPath
    local isDirMatch = entry.name:sub(1, #indexPath + 1) == (indexPath .. "/")
    return not isFileMatch and not isDirMatch
  end)
end

local clearOldIndexEntries = function(projectDir, index, path, indexPath, filter)
  if indexPath:sub(1, 1) == "/" then
    indexPath = indexPath:sub(2)
  end
  path = filesystem.collapse(path)
  if indexPath:sub(-1) == "/" then
    indexPath = indexPath:sub(1, -2)
  end

  reduceEntries(index, function(entry)
    if not filter(entry.name) then
      return true
    end
    if (entry.name ~= indexPath) and (entry.name:sub(1, #indexPath + 1) ~= (indexPath .. "/")) and indexPath ~= "" then
      return true
    end
    return filesystem.exists(filesystem.combine(projectDir, entry.name))
  end)
end

--

local function writeIndex(index, filePath)
  local file = filesystem.openWriteProtected(filePath, "wb")
  if not file then
    error("Failed to open index file")
  end
  file:write("DIRC")
  write32BitNumber(file, index.version)
  write32BitNumber(file, #index.entries)

  for _, entry in ipairs(index.entries) do
    write32BitNumber(file, entry.ctime)
    write32BitNumber(file, entry.ctimeNanos or 0)
    write32BitNumber(file, entry.mtime)
    write32BitNumber(file, entry.mtimeNanos or 0)
    write32BitNumber(file, entry.dev or 0)
    write32BitNumber(file, entry.ino or 0)
    write32BitNumber(file, entry.mode or 33188)
    write32BitNumber(file, entry.uid or 0)
    write32BitNumber(file, entry.gid or 0)
    write32BitNumber(file, entry.size)
    write20ByteHash(file, entry.hash)

    if #entry.name > 0xFFF then
      write16BitNumber(file, 0xFFF)
    else
      write16BitNumber(file, #entry.name)
    end
    file:write(entry.name)
    file:write(string.char(0))

    local size = 62 + #entry.name + 1
    if size % 8 ~= 0 then
      file:write(string.rep("\0", 8 - (size % 8)))
    end
  end
  file:close()
end

local function readIndex(filePath)
  local file = assert(filesystem.openWriteProtected(filePath, "rb"))
  if file:read(4) ~= "DIRC" then
    error("Invalid index file")
  end

  local index = {}
  index.entries = {}
  index.version = read32BitNumber(file)

  local entryCount = read32BitNumber(file)
  for _ = 1, entryCount do
    local entry = {}
    entry.ctime = read32BitNumber(file)
    entry.ctimeNanos = read32BitNumber(file)
    entry.mtime = read32BitNumber(file)
    entry.mtimeNanos = read32BitNumber(file)
    entry.dev = read32BitNumber(file)
    entry.ino = read32BitNumber(file)
    entry.mode = read32BitNumber(file)
    entry.uid = read32BitNumber(file)
    entry.gid = read32BitNumber(file)
    entry.size = read32BitNumber(file)
    entry.hash = read20ByteHash(file)
    local nameLength = read16BitNumber(file)
    entry.name = file:read(nameLength)
    ---@diagnostic disable-next-line: discard-returns
    file:read(1)
    
    local padding = 8 - ((62 + nameLength + 1) % 8)
    if padding ~= 8 then
      ---@diagnostic disable-next-line: discard-returns
      file:read(padding)
    end

    table.insert(index.entries, entry)
  end
  file:close()
  return index
end

local function split(str, pattern)
  local parts = {}
  for part in str:gmatch("([^" .. pattern .. "]+)") do
    table.insert(parts, part)
  end
  return parts
end

local function convertToInMemTree(index)
  local rootTree = {
    type = "tree",
    entries = {},
    subtrees = {} -- Convenience, will be dropped upon serialization
    -- Don't bother with formatted?
  }

  for _, entry in ipairs(index.entries) do
    local path = entry.name
    local currentTree = rootTree
    local pathParts = split(path, "/")
    for i = 1, #pathParts - 1 do
      local part = pathParts[i]
      local subtree = currentTree.subtrees[part]
      if not subtree then
        subtree = {
          type = "tree",
          name = part,
          mode = 40000,
          entries = {},
          subtrees = {}
        }
        currentTree.subtrees[part] = subtree
      end
      currentTree = subtree
    end

    local part = pathParts[#pathParts]
    getOrCreateEntry(currentTree, part, {
      type = "blob",
      name = part,
      mode = 100644, -- TODO: Figure out the correct mode conversion
      hash = entry.hash
    })

    currentTree.hash = entry.hash
  end

  return rootTree
end

local writeConvertedTree
function writeConvertedTree(gitdir, tree)
  local entries = {}
  local tempTree = {
    type = "tree",
    entries = entries
  }
  for _, entry in pairs(tree.entries) do
    updateEntry(tempTree, entry.name, entry)
  end
  for name, subtree in pairs(tree.subtrees) do
    local finalizedSubtree = writeConvertedTree(gitdir, subtree)
    updateEntry(tempTree, name, finalizedSubtree)
  end

  local hash = gitobj.writeObject(gitdir, gitobj.encodeTreeData(tempTree), "tree")

  return {
    type = "tree",
    name = tree.name,
    mode = tree.mode,
    hash = hash
  }
end

local function writeTreeFromIndex(gitDir, index)
  local tree = convertToInMemTree(index)
  local writtenTree = writeConvertedTree(gitDir, tree)
  return writtenTree.hash
end

return {
  createIndex = createIndex,
  removeEntry = removeEntry,
  updateEntry = updateEntry,
  getEntry = getEntry,
  addToIndex = addToIndex,
  removeFromIndex = removeFromIndex,
  clearOldIndexEntries = clearOldIndexEntries,
  writeIndex = writeIndex,
  readIndex = readIndex,
  convertToInMemTree = convertToInMemTree,
  writeTreeFromIndex = writeTreeFromIndex,
}