local driver = localRequire("driver")
local libdeflate = localRequire("third_party/libdeflate/libdeflate")
local sha1 = localRequire("third_party/sha1/init").sha1

local filesystem = driver.filesystem

local function decompressObject(data)
  local packedData = libdeflate:DecompressZlib(data)
  local typeEndIndex = packedData:find(" ")
  local type = packedData:sub(1, typeEndIndex - 1)
  local sizeEndIndex = packedData:find("\0")
  local size = tonumber(packedData:sub(typeEndIndex + 1, sizeEndIndex - 1))
  local content = packedData:sub(sizeEndIndex + 1)
  if #content ~= size then
    error("Invalid object size")
  end

  return type, content:sub(1) -- Remove extra byte
end

local function compressObject(data, type)
  local size = #data
  local packedData = type .. " " .. size .. "\0" .. data
  local sha1Hash = sha1(packedData)
  return libdeflate:CompressZlib(packedData), sha1Hash
end

local function readObject(gitDir, hash)
  local objectPath = filesystem.combine(gitDir, "objects", hash:sub(1, 2), hash:sub(3))
  local file = io.open(objectPath, "rb")
  if not file then
    error("Object not found")
  end
  local data = file:read("*a")
  file:close()
  return decompressObject(data)
end

local function writeObject(gitDir, data, type)
  local compressedData, hash = compressObject(data, type)
  local objectPath = filesystem.combine(gitDir, "objects", hash:sub(1, 2), hash:sub(3))
  if not filesystem.exists(filesystem.combine(gitDir, "objects", hash:sub(1, 2))) then
    filesystem.makeDir(filesystem.combine(gitDir, "objects", hash:sub(1, 2)))
  end
  if filesystem.exists(objectPath) then
    return hash -- Presumably, will be the same content
  end
  local file = assert(io.open(objectPath, "wb"))
  file:write(compressedData)
  file:close()
  return hash
end

local function decodeBlobData(data)
  return {
    type = "blob",
    data = data,
    formatted = data
  }
end

local function decodeTreeData(data)
  local entries = {}
  local i = 1
  while i < #data do
    local spaceIndex = data:find(" ", i)
    local nullIndex = data:find("\0", spaceIndex)
    local mode = data:sub(i, spaceIndex - 1)
    local name = data:sub(spaceIndex + 1, nullIndex - 1)
    local hashBinary = data:sub(nullIndex + 1, nullIndex + 20)

    local hash = ""
    for j = 1, #hashBinary do
      hash = hash .. string.format("%02x", hashBinary:byte(j))
    end

    table.insert(entries, {
      mode = mode,
      name = name,
      hash = hash
    })
    i = nullIndex + 21
  end

  local formatted = ""
  for _, entry in ipairs(entries) do
    formatted = formatted .. entry.mode .. " " .. entry.name .. " " .. entry.hash .. "\n"
  end

  return {
    type = "tree",
    entries = entries,
    formatted = formatted:sub(1, -2)
  }
end

local function decodeCommitData(data)
  local tree = data:match("tree ([^\n]+)")
  local parents = {}
  for parent in data:gmatch("parent ([^\n]+)") do
    table.insert(parents, parent)
  end
  local author = data:match("author ([^\n]+)")
  local authorTime = tonumber(author:match("([^\n]+)"))
  local authorTimezoneOffset = author:match("([^\n]+)$")
  local committer = data:match("committer ([^\n]+)")
  local committerTime = tonumber(committer:match("([^\n]+)"))
  local committerTimezoneOffset = committer:match("([^\n]+)$")
  local message = data:match("\n\n(.+)$")

  return {
    type = "commit",
    tree = tree,
    parents = parents,
    author = author,
    authorTime = authorTime,
    authorTimezoneOffset = authorTimezoneOffset,
    committer = committer,
    committerTime = committerTime,
    committerTimezoneOffset = committerTimezoneOffset,
    message = message
  }
end

local function decodeObjectData(data, type)
  if type == "blob" then
    return decodeBlobData(data)
  elseif type == "tree" then
    return decodeTreeData(data)
  elseif type == "commit" then
    return decodeCommitData(data)
  end
  error("Unsupported object type")
end

local function encodeBlobData(data)
  return data
end

local function encodeTreeData(data)
  local encoded = ""
  for _, entry in ipairs(data.entries) do
    local hashBinary = ""
    for i = 1, #entry.hash, 2 do
      hashBinary = hashBinary .. string.char(tonumber(entry.hash:sub(i, i + 1), 16))
    end
    encoded = encoded .. string.format("%06d", entry.mode) .. " " .. entry.name .. "\0" .. hashBinary
  end

  return encoded
end

local function encodeCommitData(data)
  local encoded = "tree " .. data.tree .. "\n"
  for _, parent in ipairs(data.parents) do
    encoded = encoded .. "parent " .. parent .. "\n"
  end
  
  local authorTime = string.format("%d", data.authorTime) .. " " .. (data.authorTimezoneOffset or "+0000")
  local committerTime = string.format("%d", data.committerTime) .. " " .. (data.committerTimezoneOffset or "+0000")
  encoded = encoded .. "author " .. data.author .. " " .. authorTime .. "\n"
  encoded = encoded .. "committer " .. data.committer .. " " .. committerTime .. "\n"
  encoded = encoded .. "\n" .. data.message
  return encoded
end

local function encodeObjectData(data, type)
  if type == "blob" then
    return encodeBlobData(data)
  elseif type == "tree" then
    return encodeTreeData(data)
  elseif type == "commit" then
    return encodeCommitData(data)
  end
  error("Unsupported object type")
end

return {
  decompressObject = decompressObject,
  compressObject = compressObject,
  readObject = readObject,
  writeObject = writeObject,
  decodeBlobData = decodeBlobData,
  decodeTreeData = decodeTreeData,
  decodeCommitData = decodeCommitData,
  decodeObjectData = decodeObjectData,
  encodeBlobData = encodeBlobData,
  encodeTreeData = encodeTreeData,
  encodeCommitData = encodeCommitData,
  encodeObjectData = encodeObjectData
}