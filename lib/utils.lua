local function readAll(file)
  local f = assert(io.open(file, "r"))
  local content = f:read("*a")
  f:close()
  return content
end

local function writeAll(file, content)
  local f = assert(io.open(file, "w"))
  f:write(content)
  f:close()
end

local function evalOp(code)
  return assert(load("return function(a, b) return a " .. code .. " b end"))()
end

local shl, shr, band, bor, bnot
if bit32 then
  shl = bit32.lshift
  shr = bit32.rshift
  band = bit32.band
  bor = bit32.bor
  bnot = bit32.bnot
elseif bit then
  shl = bit.lshift
  shr = bit.rshift
  band = bit.band
  bor = bit.bor
  bnot = bit.bnot
else
  shl = evalOp("<<")
  shr = evalOp(">>")
  band = evalOp("&")
  bor = evalOp("|")
  bnot = assert(load("return function(a) return ~a end"))()
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

local function format20ByteHash(hash)
  local formatted = ""
  for i = 1, 20 do
    formatted = formatted .. string.char(tonumber(hash:sub(i * 2 - 1, i * 2), 16))
  end
  return formatted
end

return {
  readAll = readAll,
  writeAll = writeAll,
  shl = shl,
  shr = shr,
  band = band,
  bor = bor,
  bnot = bnot,
  write32BitNumber = write32BitNumber,
  write16BitNumber = write16BitNumber,
  write20ByteHash = write20ByteHash,
  read32BitNumber = read32BitNumber,
  read16BitNumber = read16BitNumber,
  read20ByteHash = read20ByteHash,
  format20ByteHash = format20ByteHash
}