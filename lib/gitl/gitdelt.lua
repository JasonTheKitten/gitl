local utils = localRequire("lib/utils")
local timings = localRequire("lib/timings")
local shl, band, bor = utils.shl, utils.band, utils.bor

local function readSize(reader)
  local size = 0
  local shift = 0
  while true do
    local byte = reader.read()
    size = bor(size, shl(band(byte, 0x7F), shift))
    if band(byte, 0x80) == 0 then
      break
    end
    shift = shift + 7
  end
  return size
end

local function applyDelta(deltaReader, baseData)
  timings.startTiming("applyDelta")

  local baseSize, objSize = readSize(deltaReader), readSize(deltaReader)
  assert(baseSize == #baseData, "Base size mismatch")
  
  local newData = {}
  while not deltaReader.done() do
    local opcode = deltaReader.read()
    if band(opcode, 0x80) == 0 then
      -- New Data
      newData[#newData + 1] = deltaReader.readString(opcode)
    elseif band(opcode, 0x80) == 0x80 then
      -- Copy from base
      local offset, size = 0, 0
      offset = offset + ((band(opcode, 0x01) ~= 0) and deltaReader.read() or 0)
      offset = offset + ((band(opcode, 0x02) ~= 0) and (deltaReader.read() * 256) or 0)
      offset = offset + ((band(opcode, 0x04) ~= 0) and (deltaReader.read() * 65536) or 0)
      offset = offset + ((band(opcode, 0x08) ~= 0) and (deltaReader.read() * 16777216) or 0)
      size = size + ((band(opcode, 0x10) ~= 0) and deltaReader.read() or 0)
      size = size + ((band(opcode, 0x20) ~= 0) and (deltaReader.read() * 256) or 0)
      size = size + ((band(opcode, 0x40) ~= 0) and (deltaReader.read() * 65536) or 0)
      size = size == 0 and 0x10000 or size
      newData[#newData + 1] = baseData:sub(offset + 1, offset + size)
    else
      error("Invalid opcode: " .. opcode)
    end
  end

  local newDataStr = table.concat(newData)
  assert(#newDataStr == objSize, "New size mismatch, expected " .. objSize .. ", got " .. #newDataStr)

  timings.stopTiming("applyDelta")

  return newDataStr
end

return {
  applyDelta = applyDelta
}