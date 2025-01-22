local utils = localRequire("lib/utils")
local read32BitNumber, band, bor, shr, shl = utils.read32BitNumber, utils.band, utils.bor, utils.shr, utils.shl

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

local function decodePackFile(fileHandle, pakOptions)
  local header = fileHandle:read(4)
  assert(header == "PACK", "Invalid pack file header")
  local version = fileHandle:read(4)
  assert(version == "\0\0\0\2", "Invalid pack file version")
  local numObjects = read32BitNumber(fileHandle)
  for i = 1, numObjects do
    local type, length = decodeTypeAndLength(fileHandle)
    print("Type: " .. type .. ", Length: " .. length)
    fileHandle:read(length)
  end
end

return {
  decodePackFile = decodePackFile
}