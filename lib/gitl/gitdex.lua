local driver = localRequire("driver")
local gitobj = localRequire("lib/gitl/gitobj")
local filesystem = driver.filesystem

local function evalOp(code)
  return assert(load("return function(a, b) return a " .. code .. " b end"))()
end

local shl, shr, band
if bit32 then
  shl = bit32.lshift
  shr = bit32.rshift
  band = bit32.band
else
  shl = evalOp("<<")
  shr = evalOp(">>")
  band = evalOp("&")
end

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

local function insertEntry(index, entry)
  if (#index.entries == 0) or (index.entries[#index.entries].name < entry.name) then
    table.insert(index.entries, entry)
    return
  end
  if index.entries[1].name > entry.name then
    table.insert(index.entries, 1, entry)
    return
  end
  local startIndex, endIndex = 1, #index.entries
  while startIndex <= endIndex do
    local middleIndex = math.floor((startIndex + endIndex) / 2)
    local middleEntry = index.entries[middleIndex]
    if middleEntry.name == entry.name then
      table.insert(index.entries, middleIndex, entry)
      return
    elseif middleEntry.name < entry.name then
      startIndex = middleIndex + 1
    else
      endIndex = middleIndex - 1
    end
  end
  error("Failed to insert entry")
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

local function write32BitNumber(file, number)
  file:write(string.char(shr(number, 24)))
  file:write(string.char(band(shr(number, 16), 0xFF)))
  file:write(string.char(band(shr(number, 8), 0xFF)))
  file:write(string.char(band(number, 0xFF)))
end

local function write16BitNumber(file, number)
  file:write(string.char(shr(number, 8)))
  file:write(string.char(band(number, 0xFF)))
end

local function write20ByteHash(file, hash)
  for i = 1, 40, 2 do
    file:write(string.char(tonumber(hash:sub(i, i + 1), 16)))
  end
end

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

local function read32BitNumber(file)
  return shl(file:read(1):byte(), 24) +
    shl(file:read(1):byte(), 16) +
    shl(file:read(1):byte(), 8) +
    file:read(1):byte()
end

local function read16BitNumber(file)
  return shl(file:read(1):byte(), 8) + file:read(1):byte()
end

local function read20ByteHash(file)
  local hash = ""
  for i = 1, 20 do
    hash = hash .. string.format("%02x", file:read(1):byte())
  end
  return hash
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

local function convertToTree(index)
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
          mode = 16384, -- TODO: Figure out the correct mode
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
      mode = entry.mode,
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
    name = tree.name,
    mode = tree.mode,
    hash = hash
  }
end

local function writeTreeFromIndex(gitDir, index)
  local tree = convertToTree(index)
  local writtenTree = writeConvertedTree(gitDir, tree)
  return writtenTree.hash
end

return {
  createIndex = createIndex,
  removeEntry = removeEntry,
  updateEntry = updateEntry,
  getEntry = getEntry,
  writeIndex = writeIndex,
  readIndex = readIndex,
  writeTreeFromIndex = writeTreeFromIndex,
}