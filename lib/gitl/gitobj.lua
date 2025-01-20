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
  local file = io.open(objectPath, "wb")
  if not file then
    error("Failed to open object file for writing")
  end
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

    local hashHex = ""
    for j = 1, #hashBinary do
      hashHex = hashHex .. string.format("%02x", hashBinary:byte(j))
    end

    table.insert(entries, {
      mode = mode,
      name = name,
      hashHex = hashHex
    })
    i = nullIndex + 21
  end

  local formatted = ""
  for _, entry in ipairs(entries) do
    formatted = formatted .. entry.mode .. " " .. entry.name .. " " .. entry.hashHex .. "\n"
  end

  return {
    type = "tree",
    entries = entries,
    formatted = formatted:sub(1, -2)
  }
end

local function decodeObjectData(data, type)
  if type == "blob" then
    return decodeBlobData(data)
  elseif type == "tree" then
    return decodeTreeData(data)
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
  decodeObjectData = decodeObjectData
}