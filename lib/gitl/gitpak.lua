local utils = localRequire("lib/utils")
local zlibl = localRequire("lib/zlibl")
local gitdelt = localRequire("lib/gitl/gitdelt")
local read32BitNumber, band, bor, shr, shl = utils.read32BitNumber, utils.band, utils.bor, utils.shr, utils.shl

local BASIC_OBJECT_TYPES = { "commit", "tree", "blob", "tag" }

local function decodeTypeAndLength(fileHandle)
  local byte = fileHandle:read(1):byte()
  local type = band(shr(byte, 4), 0x7)
  local length = band(byte, 0xF)
  local shift = 4
  while band(byte, 0x80) ~= 0 do
    byte = fileHandle:read(1):byte()
    length = bor(length, shl(band(byte, 0x7F), shift))
    shift = shift + 7
  end
  return type, length
end

local function decode20ByteHash(reader)
  local hash = ""
  for i = 1, 20 do
    hash = hash .. string.format("%02x", reader.read())
  end
  return hash
end

local function decodeStandardObject(reader, pakOptions, mtype)
  local writer = zlibl.createStringWriter()
  zlibl.decodeZlib(reader, writer)
  if not pakOptions.writeObject then return end
  pakOptions.writeObject(BASIC_OBJECT_TYPES[mtype], writer.finalize())
end

local function decodeDeltaObject(reader, pakOptions)
  local writer = zlibl.createStringWriter()
  local hash = decode20ByteHash(reader)
  zlibl.decodeZlib(reader, writer)
  if not (pakOptions.readObject and pakOptions.writeObject) then return end
  local type, baseData = pakOptions.readObject(hash)
  local deltaReader = zlibl.createStringReader(writer.finalize())
  local newData = gitdelt.applyDelta(deltaReader, baseData)
  pakOptions.writeObject(type, newData)
end

local function decodePackFile(fileHandle, pakOptions)
  local header = fileHandle:read(4)
  assert(header == "PACK", "Invalid pack file header")
  local version = fileHandle:read(4)
  assert(version == "\0\0\0\2", "Invalid pack file version")
  local numObjects = read32BitNumber(fileHandle)
  local reader = zlibl.createIOReader(fileHandle)
  for i = 1, numObjects do
    local mtype, length = decodeTypeAndLength(fileHandle)
    pakOptions.indicateProgress(i, numObjects)
    if mtype >= 1 and mtype <= 4 then
      decodeStandardObject(reader, pakOptions, mtype)
    elseif mtype == 7 then
      decodeDeltaObject(reader, pakOptions)
    else
      -- TODO: Support OBJ_OFS_DELTA
      error("Unsupported object type: " .. mtype)
    end
  end
end

return {
  decodePackFile = decodePackFile
}