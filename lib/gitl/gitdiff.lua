local function splitLines(contents)
  local lines = {}
  local line = ""
  for i = 1, #contents do
    local char = contents:sub(i, i)
    if char == "\n" then
      table.insert(lines, line)
      line = ""
    else
      line = line .. char
    end
  end

  if #line > 0 then
    table.insert(lines, line)
  end

  return lines
end

local function computeLCSTable(lines1, lines2)
  local lcsTable = {}
  for i = 0, #lines1 do
    lcsTable[i] = {}
    for j = 0, #lines2 do
      lcsTable[i][j] = 0
    end
  end

  for i = 1, #lines1 do
    for j = 1, #lines2 do
      if lines1[i] == lines2[j] then
        lcsTable[i][j] = lcsTable[i - 1][j - 1] + 1
      else
        lcsTable[i][j] = math.max(lcsTable[i - 1][j], lcsTable[i][j - 1])
      end
    end
  end

  return lcsTable
end

local function backtrackLCSTable(lscTable, lines1, lines2)
  local i = #lines1
  local j = #lines2
  local lcs = {}
  while i > 0 and j > 0 do
    if lines1[i] == lines2[j] then
      table.insert(lcs, 1, lines1[i])
      i = i - 1
      j = j - 1
    elseif lscTable[i - 1][j] > lscTable[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end

  return lcs
end

local function diff(contents1, contents2)
  local lines1 = splitLines(contents1)
  local lines2 = splitLines(contents2)

  local lcsTable = computeLCSTable(lines1, lines2)
  local lcs = backtrackLCSTable(lcsTable, lines1, lines2)

  local diffTable = {}
  local i, j = 1, 1
  for _, line in ipairs(lcs) do
    while lines1[i] ~= line do
      table.insert(diffTable, { type = "remove", value = lines1[i] })
      i = i + 1
    end
    while lines2[j] ~= line do
      table.insert(diffTable, { type = "add", value = lines2[j] })
      j = j + 1
    end
    table.insert(diffTable, { type = "normal", value = line })
    i = i + 1
    j = j + 1
  end

  while i <= #lines1 do
    table.insert(diffTable, { type = "remove", value = lines1[i] })
    i = i + 1
  end
  while j <= #lines2 do
    table.insert(diffTable, { type = "add", value = lines2[j] })
    j = j + 1
  end

  return diffTable
end

local function hunkDiffContent(diffs, contextThreshold)
  local hunks = {}
  local currentHunk
  local i, j = 1, 1
  local currentDistance = 0

  local function endCurrentHunk()
    if not currentHunk then return end

    table.insert(hunks, currentHunk)

    currentHunk = nil
    currentDistance = 0
  end

  local function ensureHunkStarted()
    if currentHunk then return end
    currentHunk = { start1 = i, start2 = j, size1 = 0, size2 = 0, diff = {} }

    -- Include context lines before the hunk
    local contextStart = math.max(1, i - contextThreshold)
    for k = contextStart, i - 1 do
      if diffs[k].type == "normal" then
        table.insert(currentHunk.diff, diffs[k])
        currentHunk.size1 = currentHunk.size1 + 1
        currentHunk.size2 = currentHunk.size2 + 1
        currentHunk.start1 = currentHunk.start1 - 1
        currentHunk.start2 = currentHunk.start2 - 1
      else
        break
      end
    end
  end

  for _, diffLine in ipairs(diffs) do
    if diffLine.type == "normal" then
      if currentDistance >= contextThreshold then
        endCurrentHunk()
      end
      currentDistance = currentDistance + 1
      if currentHunk then
        table.insert(currentHunk.diff, diffLine)
        currentHunk.size1 = currentHunk.size1 + 1
        currentHunk.size2 = currentHunk.size2 + 1
      end
      i = i + 1
      j = j + 1
    elseif diffLine.type == "add" then
      ensureHunkStarted()
      table.insert(currentHunk.diff, diffLine)
      currentHunk.size2 = currentHunk.size2 + 1
      j = j + 1
      currentDistance = 0
    elseif diffLine.type == "remove" then
      ensureHunkStarted()
      table.insert(currentHunk.diff, diffLine)
      currentHunk.size1 = currentHunk.size1 + 1
      i = i + 1
      currentDistance = 0
    end
  end
  endCurrentHunk()

  return hunks
end

local function formatDiffContent(diffs, contextThreshold)
  local hunks = hunkDiffContent(diffs, contextThreshold)
  local diffContent = ""
  for _, hunk in ipairs(hunks) do
    diffContent = diffContent .. "@@ -" .. hunk.start1 .. "," .. hunk.size1 .. " +" .. hunk.start2 .. "," .. hunk.size2 .. " @@\n"
    for _, diffLine in ipairs(hunk.diff) do
      if diffLine.type == "add" then
        diffContent = diffContent .. "+ " .. diffLine.value .. "\n"
      elseif diffLine.type == "remove" then
        diffContent = diffContent .. "- " .. diffLine.value .. "\n"
      else
        diffContent = diffContent .. "  " .. diffLine.value .. "\n"
      end
    end
  end

  return diffContent
end

return {
  diff = diff,
  hunkDiffContent = hunkDiffContent,
  formatDiffContent = formatDiffContent
}