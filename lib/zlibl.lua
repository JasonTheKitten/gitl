-- Deflate
-- https://datatracker.ietf.org/doc/html/rfc1951
local utils = localRequire("lib/utils")
local timings = localRequire("lib/timings")
local shl, shr, band, bor = utils.shl, utils.shr, utils.band, utils.bor

local extraLenCodeList = {
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
}
local extraDistCodeList = {
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
}
local codeLengthCodeList = {
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
}

local lenCodeGroups, distCodeGroups = {}, {}
local lenCodeGroupStarts, distCodeGroupStarts = {}, {}

do
  local i, k2 = 257, 3
  for j = 1, #extraLenCodeList do
    local numInGroup = 2 ^ extraLenCodeList[j]
    lenCodeGroupStarts[j - 1] = k2
    for k = 1, numInGroup do
      lenCodeGroups[i + k - 1] = j - 1
    end
    i = i + numInGroup
    k2 = k2 + numInGroup
  end
end
-- Ahahaha, let's make the previous range one shorter than
-- all the rest just to throw off developers
lenCodeGroups[285 + 254] = 28
lenCodeGroupStarts[28] = 258

local function resolveDistCodeGroup(code)
  if distCodeGroups[code] then
      return distCodeGroups[code], distCodeGroupStarts[distCodeGroups[code]]
  end

  local i = 0
  for j = 0, #extraDistCodeList - 1 do
      local numInGroup = 2 ^ extraDistCodeList[j + 1]
      if code <= i + numInGroup then
          distCodeGroups[code] = j
          distCodeGroupStarts[j] = i + 1
          return j, i + 1
      end
      i = i + numInGroup
  end
end


local function resolveDistCodeGroupStart(codeGroup)
  if distCodeGroupStarts[codeGroup] then
    return distCodeGroupStarts[codeGroup]
  end
  local startTotal = 1
  for i = 1, codeGroup do
    startTotal = startTotal + 2 ^ extraDistCodeList[i]
  end
  distCodeGroupStarts[codeGroup] = startTotal
  return startTotal
end

local function binaryInsert(array, value, compare)
  local low, high = 1, #array
  while low <= high do
    local mid = math.floor((low + high) / 2)
    if compare(array[mid], value) then
      low = mid + 1
    else
      high = mid - 1
    end
  end
  table.insert(array, low, value)
end

--

local reversedBits = {}
local function reverseBits(bits, numBits)
  local reversed = 0
  for i = 0, numBits - 1 do
    reversed = shl(reversed, 1) + band(shr(bits, i), 1)
  end
  return reversed
end
for i = 0, 8 do
  reversedBits[i] = {}
  for j = 0, 2 ^ i - 1 do
    reversedBits[i][j] = reverseBits(j, i)
  end
end
local reversedBytes = reversedBits[8]

local function createBitWriter(writer)
  local currentByte, bitIndex = 0, 0
  local function flushCurrentByte()
    if bitIndex > 0 then
      writer.write(reversedBytes[currentByte])
      currentByte, bitIndex = 0, 0
    end
  end

  local function write(value, length)
    -- Need to write bits in reverse order
    while length > 0 do
      if bitIndex == 8 then
        writer.write(reversedBytes[currentByte])
        currentByte, bitIndex = 0, 0
      end
      local bitsToWrite = math.min(8 - bitIndex, length)
      local valuePart = band(value, 2 ^ bitsToWrite - 1)
      local valueToWrite = reversedBits[bitsToWrite][valuePart]
      local shifted = shl(valueToWrite, 7 - bitIndex - bitsToWrite + 1)
      currentByte = bor(currentByte, shifted)
      bitIndex = bitIndex + bitsToWrite
      length = length - bitsToWrite
      value = shr(value, bitsToWrite)
    end
  end
  local function writeBitString(bitString)
    local length = #bitString
    local value = tonumber(bitString, 2)
    while length > 0 do
      if bitIndex == 8 then
        writer.write(reversedBytes[currentByte])
        currentByte, bitIndex = 0, 0
      end
      local bitsToWrite = math.min(8 - bitIndex, length)
      local valueToWrite = band(shr(value, length - bitsToWrite), 2 ^ bitsToWrite - 1)
      local shifted = shl(valueToWrite, 7 - bitIndex - bitsToWrite + 1)
      currentByte = bor(currentByte, shifted)
      bitIndex = bitIndex + bitsToWrite
      length = length - bitsToWrite
    end
  end

  return {
    write = write,
    writeBitString = writeBitString,
    finalize = flushCurrentByte
  }
end

local function createBitReader(reader)
  local currentByte, bitIndex = 0, 8
  local function align()
    if bitIndex ~= 0 then
      currentByte = reader.read()
      bitIndex = 0
    end
  end
  local function readBit()
    if bitIndex == 8 then
      align()
    end
    local result = band(shr(currentByte, bitIndex), 1)
    bitIndex = bitIndex + 1
    return result
  end
  local function read(numBits)
    local value = 0
    for i = 1, numBits do
      value = value + readBit() * 2 ^ (i - 1)
    end
    return value
  end

  return {
    readBit = readBit,
    read = read,
    align = align
  }
end

--

local function toBitStr(value, bitLength)
  local str = ""
  for i = bitLength - 1, 0, -1 do
      str = str .. tostring(band(shr(value, i), 1))
  end
  return str
end

local function decodeHuffmanTable(codeLengths, maxCodeIndex)
  local blCount = {}
  local nextCode = {}
  local maxBits = 0
  for i = 0, maxCodeIndex do
    local codeLen = codeLengths[i] or 0
    blCount[codeLen] = (blCount[codeLen] or 0) + 1
    maxBits = math.max(maxBits, codeLen)
  end
  local code = 0
  blCount[0] = 0
  for i = 1, maxBits do
    code = shl(code + (blCount[i - 1] or 0), 1)
    nextCode[i] = code
  end
  local codes = {}
  for i = 0, maxCodeIndex do
    local len = codeLengths[i] or 0
    if len ~= 0 then
      codes[i] = toBitStr(nextCode[len], len)
      nextCode[len] = nextCode[len] + 1
    end
  end

  return codes
end

local function generateInitHuffmanTree(frequencies)
  local sortFunc = function(a, b)
      if a.height ~= b.height then
          return a.height < b.height
      end
      return
        (a.frequency < b.frequency)
        or ((a.frequency == b.frequency) and (a.index < b.index))
  end

  local nodes = {}
  for i = 0, #frequencies do
    if frequencies[i] ~= 0 then
      table.insert(nodes, { frequency = frequencies[i], index = i, height = 0 })
    end
  end
  table.sort(nodes, sortFunc)

  while #nodes > 1 do
    local left = table.remove(nodes, 1)
    local right = table.remove(nodes, 1)
    local newNode = {
      frequency = left.frequency + right.frequency,
      height = math.max(left.height, right.height) + 1,
      index = math.min(left.index, right.index),
      left = left,
      right = right
    }

    binaryInsert(nodes, newNode, sortFunc)
  end

  return nodes[1]
end

local function generateHuffmanCodesFromFreq(frequencies)
  local initTree = generateInitHuffmanTree(frequencies)
  -- Our codes are wrong for some reason, but they are the right lengths
  -- so we'll just regenerate them with the official algorithm
  local codeLens, maxCodeIndex = {}, 0
  local findCodeLens
  findCodeLens = function(node, nodeLen)
    if not node then return end
    if node.left then
      findCodeLens(node.left, nodeLen + 1)
    end
    if node.right then
      findCodeLens(node.right, nodeLen + 1)
    end
    if not node.left and not node.right then
      codeLens[node.index] = math.max(nodeLen, 1)
      maxCodeIndex = math.max(maxCodeIndex, node.index)
    end
  end
  findCodeLens(initTree, 0)
  return decodeHuffmanTable(codeLens, maxCodeIndex)
end

--

local function trihash(a, b, c)
  return a * 256 * 256 + b * 256 + c
end

local function createRollingWindow(length)
  local rollingWindow, rollingWindowIndex, rollingWindowSize, rollingWindowCycle = {}, 0, 0, 0
  local function write(byte)
    --timings.startTiming("deflate-writeWindow")
    rollingWindowIndex = rollingWindowIndex + 1
    if rollingWindowIndex == length then
      rollingWindowIndex = 0
      rollingWindowCycle = rollingWindowCycle + 1
    end
    rollingWindow[rollingWindowIndex] = byte
    rollingWindowSize = math.min(rollingWindowSize + 1, length)
    --timings.stopTiming("deflate-writeWindow")
  end
  local function size()
    return rollingWindowSize
  end
  local function bytesAgo(ago)
    return rollingWindow[(rollingWindowIndex - ago + 1) % length]
  end
  local function removeFirst()
    local originalValue = bytesAgo(rollingWindowSize)
    rollingWindowSize = rollingWindowSize - 1
    return originalValue
  end
  local function reset()
    rollingWindowIndex, rollingWindowSize = 0, 0
  end
  local function currentCycleIndex()
    return rollingWindowCycle, rollingWindowIndex
  end
  local function agoCycleIndex(ago)
    local cycle, index = currentCycleIndex()
    while (index - ago) < 0 do
      cycle = cycle - 1
      index = index + length
    end
    return cycle, index - ago
  end
  local function isWithinWindow(cycle, index)
    return
      (rollingWindowCycle == cycle and rollingWindowIndex >= index) or
      (rollingWindowCycle == cycle - 1 and rollingWindowIndex < index)
  end
  local function distanceFrom(cycle, index)
    return (rollingWindowCycle - cycle) * length + rollingWindowIndex - index
  end

  return {
    write = write,
    size = size,
    bytesAgo = bytesAgo,
    removeFirst = removeFirst,
    reset = reset,
    currentCycleIndex = currentCycleIndex,
    agoCycleIndex = agoCycleIndex,
    isWithinWindow = isWithinWindow,
    distanceFrom = distanceFrom
  }
end

local function deflateBlock(reader, bitWriter, window, size, blockCompressor)
  timings.startTiming("deflate-deflateBlock")
  local buffer = createRollingWindow(258)

  -- We have a lookup to quickly find potential matches
  local triLookup = {}
  local function getTriEntries(a, b, c, index)
    --timings.startTiming("deflate-getTriEntries")
    local hash = trihash(a, b, c)
    local linkedEntry = triLookup[hash]
    if not linkedEntry then return {} end
    local entries = {}
    local parent = nil
    while linkedEntry do
      if window.distanceFrom(linkedEntry.cycle, linkedEntry.index) <= window.size() then
        table.insert(entries, {
          cycle = linkedEntry.cycle,
          index = linkedEntry.index,
          length = 3
        })
      else
        if parent then
          parent.next = nil
        else
          triLookup[hash] = nil
        end
      end
      parent = linkedEntry
      linkedEntry = linkedEntry.next
      --timings.stopTiming("deflate-getTriEntries")
    end

    return entries
  end

  -- Now, set up block frequencies and storage
  local charLenFreq = {}
  local distFreq = {}
  local intermediateBlock = {}
  local function writeAndHash(char)
    --timings.startTiming("deflate-writeAndHash")
    local a, b, c = window.bytesAgo(2), window.bytesAgo(1), char
    local cycle, index = window.agoCycleIndex(2)
    window.write(char)
    if not a then return end
    local hash = trihash(a, b, c)
    local linkedEntry = triLookup[hash]
    local newEntry = {
      cycle = cycle,
      index = index
    }
    if linkedEntry then
      while linkedEntry.next do
        linkedEntry = linkedEntry.next
      end
      linkedEntry.next = newEntry
    else
      triLookup[hash] = newEntry
    end
    --timings.stopTiming("deflate-writeAndHash")
  end
  local function insertChar(char)
    charLenFreq[char] = (charLenFreq[char] or 0) + 1
    table.insert(intermediateBlock, char)
  end
  local function insertLen(len)
    local offsetLen = 254 + len
    charLenFreq[offsetLen] = (charLenFreq[offsetLen] or 0) + 1
    table.insert(intermediateBlock, offsetLen)
  end
  local function insertDist(dist)
    distFreq[dist] = (distFreq[dist] or 0) + 1
    table.insert(intermediateBlock, dist)
  end
  
  -- Maintain a set of leads that might give good compression
  local leads = {}
  local function flushBuffer()
    leads = {}
    for i = 1, buffer.size() do
      insertChar(buffer.removeFirst())
    end
    buffer.reset()
  end
  local function flushFirstLead()
    local lead = leads[1]
    leads = {}
    local dist = window.distanceFrom(lead.cycle, lead.index + lead.length)
    insertLen(lead.length)
    insertDist(dist)
    buffer.reset()
  end
  local function scanInitialLeads(i)
    local a, b, c = buffer.bytesAgo(3), buffer.bytesAgo(2), buffer.bytesAgo(1)
    leads = getTriEntries(a, b, c, i - 3)
  end
  local function extendLeads(ch)
    --timings.startTiming("deflate-extendLeads")
    local reducedLeads = {}
    for j = 1, #leads do
      local lead = leads[j]
      local distance = window.distanceFrom(lead.cycle, lead.index)
      if ch == window.bytesAgo(distance - lead.length) then
        lead.length = lead.length + 1
        table.insert(reducedLeads, lead)
      end
    end
    --timings.stopTiming("deflate-extendLeads")
    return reducedLeads
  end

  -- Next, do basic compression
  for i = 1, size do
    local byte = reader.read()
    if not byte then break end
    if buffer.size() < 2 then
      buffer.write(byte)
    elseif buffer.size() == 2 then
      buffer.write(byte)
      scanInitialLeads(i)
    elseif (buffer.size() == 3) and (#leads == 0) then
      insertChar(buffer.removeFirst())
      buffer.write(byte)
      scanInitialLeads(i)
    elseif buffer.size() == 258 then
      flushFirstLead()
      buffer.write(byte)
    else
      assert(#leads > 0)
      local newLeads = extendLeads(byte)
      if #newLeads == 0 then
        flushFirstLead()
        buffer.write(byte)
      else
        leads = newLeads
        buffer.write(byte)
      end
    end
    writeAndHash(byte)
  end

  -- Finally, flush the buffer
  if #leads > 0 then
    flushFirstLead()
  else
    flushBuffer()
  end

  table.insert(intermediateBlock, 256)
  charLenFreq[256] = 1

  timings.stopTiming("deflate-deflateBlock")

  --[[local intermediateBlock, charLenFreq, distFreq = {}, {}, {}
  for i = 1, size do
    local byte = reader.read()
    if not byte then break end
    intermediateBlock[i] = byte
    charLenFreq[byte] = (charLenFreq[byte] or 0) + 1
  end]]

  return blockCompressor(bitWriter, intermediateBlock, charLenFreq, distFreq, reader.done())
end

local function compressHuffmanDeflateBlockContent(bitWriter, intermediateBlock, charLenCodes, distCodes)
  local i = 1
  timings.startTiming("i1")
  while i <= #intermediateBlock do
    local byte = intermediateBlock[i]
    if byte <= 256 then
      bitWriter.writeBitString(charLenCodes[byte])
      i = i + 1
    else
      local len = byte - 254
      local lenPrefix = lenCodeGroups[byte]
      local lenSuffix = len - lenCodeGroupStarts[lenPrefix]
      bitWriter.writeBitString(charLenCodes[lenPrefix + 257])
      bitWriter.write(lenSuffix, extraLenCodeList[lenPrefix + 1])

      local dist = intermediateBlock[i + 1]
      local distPrefix, distCodeGroupStart = resolveDistCodeGroup(dist)
      local distSuffix = dist - distCodeGroupStart
      bitWriter.writeBitString(distCodes[distPrefix])
      bitWriter.write(distSuffix, extraDistCodeList[distPrefix + 1])
      i = i + 2
    end
  end
  timings.stopTiming("i1")
end

--

local function adjustCharLenFreq(charLenFreq)
  local adjustedCharLenFreq = {}
  for i = 0, 256 do
    adjustedCharLenFreq[i] = charLenFreq[i] or 0
  end
  for i = 257, 285 do
    adjustedCharLenFreq[i] = adjustedCharLenFreq[i] or 0
  end
  for i = 257, 257 + 258 - 2 do
    local lenCodeGroup = 257 + lenCodeGroups[i]
    adjustedCharLenFreq[lenCodeGroup] = adjustedCharLenFreq[lenCodeGroup] + (charLenFreq[i] or 0)
  end

  return adjustedCharLenFreq
end

local function adjustDistFreq(distFreq)
  local adjustedDistFreq = {}
  for i = 0, 29 do
    adjustedDistFreq[i] = 0
  end
  for k, v in pairs(distFreq) do
    local distCodeGroup = resolveDistCodeGroup(k)
    adjustedDistFreq[distCodeGroup] = adjustedDistFreq[distCodeGroup] + v
  end

  return adjustedDistFreq
end

local function codesToCodeOccurrenceTable(codeLenCodeFreq, codes, numCodes)
  local codeOccurrenceTable = {}
  local lastCodeLen
  local i = 0
  while i <= numCodes do
    local code = codes[i]
    if code == nil then
      lastCodeLen = nil
      local numZeroes = 1
      while (i + numZeroes <= numCodes) and (codes[i + numZeroes] == nil) and (numZeroes < 138) do
        numZeroes = numZeroes + 1
      end
      if numZeroes < 3 then
        codeLenCodeFreq[0] = codeLenCodeFreq[0] + 1
        table.insert(codeOccurrenceTable, 0)
        i = i + 1
      elseif numZeroes < 11 then
        codeLenCodeFreq[17] = codeLenCodeFreq[17] + 1
        table.insert(codeOccurrenceTable, 17)
        table.insert(codeOccurrenceTable, numZeroes - 3)
        i = i + numZeroes
      else
        codeLenCodeFreq[18] = codeLenCodeFreq[18] + 1
        table.insert(codeOccurrenceTable, 18)
        table.insert(codeOccurrenceTable, numZeroes - 11)
        i = i + numZeroes
      end
    elseif #code ~= lastCodeLen then
      codeLenCodeFreq[#code] = codeLenCodeFreq[#code] + 1
      table.insert(codeOccurrenceTable, #code)
      lastCodeLen = #code
      i = i + 1
    else
      local numRepeats = 1
      while (i + numRepeats <= numCodes) and (codes[i + numRepeats] == code) and (numRepeats < 6) do
        numRepeats = numRepeats + 1
      end
      if numRepeats < 3 then
        codeLenCodeFreq[#code] = codeLenCodeFreq[#code] + 1
        table.insert(codeOccurrenceTable, #code)
        i = i + 1
      else
        codeLenCodeFreq[16] = codeLenCodeFreq[16] + 1
        table.insert(codeOccurrenceTable, 16)
        table.insert(codeOccurrenceTable, numRepeats - 3)
        i = i + numRepeats
      end
    end
  end

  return codeOccurrenceTable
end

local function writeCodeOccurrenceTable(bitWriter, codeOccurrenceTable, codeLenCodes)
  local i = 1
  while i <= #codeOccurrenceTable do
    local code = codeOccurrenceTable[i]
    local compressedCode = codeLenCodes[code]
    local nextCode = codeOccurrenceTable[i + 1]
    bitWriter.writeBitString(compressedCode)
    if code < 16 then
      i = i + 1
    elseif code == 16 then
      bitWriter.write(nextCode, 2)
      i = i + 2
    elseif code == 17 then
      bitWriter.write(nextCode, 3)
      i = i + 2
    elseif code == 18 then
      bitWriter.write(nextCode, 7)
      i = i + 2
    end
  end
end

local function highestNonZero(tbl)
  local max = 0
  for k, v in pairs(tbl) do
    if v ~= 0 then max = math.max(max, k) end
  end
  return max
end

local function compressDynamicDeflateBlock(bitWriter, intermediateBlock, charLenFreq, distFreq, done)
  timings.startTiming("deflate-compressDynamicDeflateBlock")

  bitWriter.write(done and 1 or 0, 1) -- BFINAL
  bitWriter.write(2, 2) -- BTYPE

  local adjustedCharLenFreq = adjustCharLenFreq(charLenFreq)
  local adjustedDistFreq = adjustDistFreq(distFreq)
  local charLenCodes = generateHuffmanCodesFromFreq(adjustedCharLenFreq)
  local distCodes = generateHuffmanCodesFromFreq(adjustedDistFreq)

  local codeLenCodeFreq = {}
  for i = 0, 18 do
    codeLenCodeFreq[i] = 0
  end

  for i = 1, 257 do adjustedCharLenFreq[i] = adjustedCharLenFreq[i] or 0 end
  for i = 1, 4 do adjustedDistFreq[i] = adjustedDistFreq[i] or 0 end
  local highestHLIT = highestNonZero(adjustedCharLenFreq) + 1
  local highestHDIST = highestNonZero(adjustedDistFreq) + 1
  local boundedHLIT = math.max(highestHLIT - 257, 0) + 257
  local boundedHDIST = math.max(highestHDIST - 1, 0) + 1
  bitWriter.write(math.max(highestHLIT - 257, 0), 5) -- HLIT
  bitWriter.write(math.max(highestHDIST - 1, 0), 5) -- HDIST

  local charLenCodeOccurrences = codesToCodeOccurrenceTable(codeLenCodeFreq, charLenCodes, boundedHLIT - 1)
  local distCodeOccurences = codesToCodeOccurrenceTable(codeLenCodeFreq, distCodes, boundedHDIST - 1)
  local codeLenCodes = generateHuffmanCodesFromFreq(codeLenCodeFreq)

  local highestHCLEN = 0
  for i = 1, #codeLengthCodeList do
    if codeLenCodeFreq[codeLengthCodeList[i]] ~= 0 then
      highestHCLEN = i
    end
  end

  bitWriter.write(highestHCLEN - 4, 4) -- HCLEN

  for i = 1, math.max(highestHCLEN, 4) do
    local code = codeLenCodes[codeLengthCodeList[i]]
    local codeLen = code and #code or 0
    bitWriter.write(codeLen, 3)
  end
  writeCodeOccurrenceTable(bitWriter, charLenCodeOccurrences, codeLenCodes)
  writeCodeOccurrenceTable(bitWriter, distCodeOccurences, codeLenCodes)
  timings.stopTiming("deflate-compressDynamicDeflateBlock")

  timings.startTiming("deflate-compressDynamicDeflateBlock1")
  compressHuffmanDeflateBlockContent(bitWriter, intermediateBlock, charLenCodes, distCodes)
  timings.stopTiming("deflate-compressDynamicDeflateBlock1")
end

--

local function deflate(reader, writer)
  local window = createRollingWindow(32 * 1024)
  local bitWriter = createBitWriter(writer)
  while not reader.done() do
    deflateBlock(reader, bitWriter, window, 32 * 1024, compressDynamicDeflateBlock)
  end
  bitWriter.finalize()
end

--

local function addCodeToLookupTable(lookupTable, code, value)
  for i = #lookupTable + 1, #code do
    lookupTable[i] = {}
  end
  lookupTable[#code][tonumber(code, 2)] = value
end

local function createCodeLookupTable(codes)
  local lookupTable = {}
  for k, v in pairs(codes) do
    addCodeToLookupTable(lookupTable, v, k)
  end

  return lookupTable
end

local function createCodeLookupFromLengths(lengths)
  local huffmanCodes = decodeHuffmanTable(lengths, #lengths)
  return createCodeLookupTable(huffmanCodes)
end

local function readCode(bitReader, lookupTable)
  local byte = 0
  for i = 1, #lookupTable do
    byte = shl(byte, 1) + bitReader.readBit()
    local value = lookupTable[i][byte]
    if value then return value end
  end
  error("Invalid code")
end

local function readCodeOccurrenceTable(bitReader, codeLenLookup, numEntries)
  local codes = {}
  local i = 0
  while i <= numEntries do
    local code = readCode(bitReader, codeLenLookup)
    if code < 16 then
      codes[i] = code
      i = i + 1
    elseif code == 16 then
      local numCpy = bitReader.read(2) + 3
      for j = 1, numCpy do
        codes[i] = codes[i-1]
        i = i + 1
      end
    elseif code == 17 then
      local numZeroes = bitReader.read(3) + 3
      for j = 1, numZeroes do
        codes[i] = 0
        i = i + 1
      end
    elseif code == 18 then
      local numZeroes = bitReader.read(7) + 11
      for j = 1, numZeroes do
        codes[i] = 0
        i = i + 1
      end
    end
  end

  return codes
end

local function decodeDynamicHuffmanTables(bitReader)
  local numLitLenCodes = bitReader.read(5) + 257
  local numDistCodes = bitReader.read(5) + 1
  local numCodeLenCodes = bitReader.read(4) + 4
  local codeLenLengths = {}
  for i = 1, numCodeLenCodes do
    local r = bitReader.read(3)
    codeLenLengths[codeLengthCodeList[i]] = r
  end
  for i = numCodeLenCodes + 1, 19 do
    codeLenLengths[codeLengthCodeList[i]] = 0
  end

  local codeLenLookup = createCodeLookupFromLengths(codeLenLengths)
  local numLitLengths = readCodeOccurrenceTable(bitReader, codeLenLookup, numLitLenCodes - 1)
  local numDistLengths = readCodeOccurrenceTable(bitReader, codeLenLookup, numDistCodes - 1)

  local litLenLookup = createCodeLookupFromLengths(numLitLengths)
  local distLookup = createCodeLookupFromLengths(numDistLengths)

  return litLenLookup, distLookup
end

local fixedLitLenLookup = {}
local fixedDistLookup = {}

do
  local fixedLitLenLengths = {}
  for i = 0, 143 do
    fixedLitLenLengths[i] = 8
  end
  for i = 144, 255 do
    fixedLitLenLengths[i] = 9
  end
  for i = 256, 279 do
    fixedLitLenLengths[i] = 7
  end
  for i = 280, 287 do
    fixedLitLenLengths[i] = 8
  end
  fixedLitLenLookup = createCodeLookupFromLengths(fixedLitLenLengths)

  local fixedDistLengths = {}
  for i = 0, 31 do
    fixedDistLengths[i] = 5
  end
  fixedDistLookup = createCodeLookupFromLengths(fixedDistLengths)
end

local function parseHuffmanBlock(bitReader, writer, window, litLenLookup, distLookup)
  while true do
    local code = readCode(bitReader, litLenLookup)
    if code == 256 then
      break
    elseif code < 256 then
      window.write(code)
      writer.write(code)
    else
      local lenPrefix = code - 257
      local lenSuffix = bitReader.read(extraLenCodeList[lenPrefix + 1])
      local len = lenCodeGroupStarts[lenPrefix] + lenSuffix
      local distPrefix = readCode(bitReader, distLookup)
      local distSuffix = bitReader.read(extraDistCodeList[distPrefix + 1])
      local dist = resolveDistCodeGroupStart(distPrefix) + distSuffix

      for i = 1, len do
        local byte = window.bytesAgo(dist)
        window.write(byte)
        writer.write(byte)
      end
    end
  end
end

local function inflate(reader, writer)
  local window = createRollingWindow(32 * 1024)
  local bitReader = createBitReader(reader)
  local lastBlockReached = false
  while not lastBlockReached do
    local bfinal = bitReader.read(1)
    local btype = bitReader.read(2)
    if btype == 0 then
      -- Uncompressed block (Not tested)
      bitReader.align()
      local len = bitReader.read(16)
      local nlen = bitReader.read(16)
      assert(len + nlen == 0xFFFF, "Invalid uncompressed block")
      for i = 1, len do
        local byte = bitReader.read(8)
        writer.write(byte)
      end
    elseif btype == 1 then
      -- Fixed Huffman block
      parseHuffmanBlock(bitReader, writer, window, fixedLitLenLookup, fixedDistLookup)
    elseif btype == 2 then
      -- Dynamic Huffman block
      local litLenLookup, distLookup = decodeDynamicHuffmanTables(bitReader)
      parseHuffmanBlock(bitReader, writer, window, litLenLookup, distLookup)
    else
      error("Invalid block type")
    end
    lastBlockReached = bfinal == 1
  end
end

-- ZLib
-- https://datatracker.ietf.org/doc/html/rfc1950

local function createAdler32Reader(reader)
  local a, b = 1, 0
  return {
    read = function()
      local byte = reader.read()
      if not byte then return nil end
      a = (a + byte) % 65521
      b = (b + a) % 65521
      return byte
    end,
    done = function()
      return reader.done()
    end,
    adler32 = function()
      return shl(b, 16) + a
    end
  }
end

local function write32BitNumber(writer, number)
  writer.write(band(shr(number, 24), 0xFF))
  writer.write(band(shr(number, 16), 0xFF))
  writer.write(band(shr(number, 8), 0xFF))
  writer.write(band(number, 0xFF))
end

local function encodeZlib(reader, writer)
  timings.startTiming("encodeZlib")
  writer.write(0x78)
  writer.write(0xDA)
  local adler32Reader = createAdler32Reader(reader)
  deflate(adler32Reader, writer)
  write32BitNumber(writer, adler32Reader.adler32())
  timings.stopTiming("encodeZlib")
end

local function createAdler32Writer(writer)
  local a, b = 1, 0
  return {
    write = function(byte)
      a = (a + byte) % 65521
      b = (b + a) % 65521
      writer.write(byte)
    end,
    adler32 = function()
      return shl(b, 16) + a
    end
  }
end

local function read32BitNumber(reader)
  return shl(reader.read(), 24) + shl(reader.read(), 16) + shl(reader.read(), 8) + reader.read()
end

local function decodeZlib(reader, writer)
  timings.startTiming("decodeZlib")
  
  local cmf = reader.read()
  local flg = reader.read()
  local cm = band(cmf, 0x0F)
  local cinfo = shr(cmf, 4)
  local fcheck = band(flg, 0x1F)
  local fdict = band(flg, 0x20)
  local flevel = shr(flg, 6)
  assert(cm == 8, "Only deflate compression method is supported")
  assert(cinfo <= 7, "Invalid window size")
  assert(fcheck == (cmf * 256 + flg) % 32, "Invalid fcheck")
  assert(fdict == 0, "Presets not supported")
  assert(flevel <= 3, "Invalid flevel")

  local adler32Writer = createAdler32Writer(writer)
  inflate(reader, adler32Writer)
  local computedAdler32 = adler32Writer.adler32()
  local expectedAdler32 = read32BitNumber(reader)
  assert(computedAdler32 == expectedAdler32, "Invalid Adler32 checksum")

  timings.stopTiming("decodeZlib")
end

--

local function createStringReader(str)
  local index = 1
  return {
    read = function()
      local byte = str:byte(index)
      index = index + 1
      return byte
    end,
    readString = function(len)
      local s = str:sub(index, index + len - 1)
      index = index + len
      return s
    end,
    done = function()
      return index > #str
    end
  }
end

local function createStringWriter()
  local strTbl = {}
  return {
    write = function(byte)
      table.insert(strTbl, string.char(byte))
    end,
    writeString = function(str)
      table.insert(strTbl, str)
    end,
    finalize = function()
      return table.concat(strTbl)
    end
  }
end

local function createIOReader(io)
  return {
    read = function()
      return io:read(1):byte()
    end,
    readString = function(len)
      return io:read(len)
    end,
    done = function()
      return io:read(0) == nil
    end
  }
end

local function createIOWriter(io)
  return {
    write = function(byte)
      io:write(string.char(byte))
    end,
    writeString = function(str)
      io:write(str)
    end
  }
end

--

return {
  deflate = deflate,
  inflate = inflate,
  encodeZlib = encodeZlib,
  decodeZlib = decodeZlib,
  createStringReader = createStringReader,
  createStringWriter = createStringWriter,
  createIOReader = createIOReader,
  createIOWriter = createIOWriter
}