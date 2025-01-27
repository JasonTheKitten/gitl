local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local gitstat = localRequire("lib/gitl/gitstat")
local gitdex = localRequire("lib/gitl/gitdex")
local gitobj = localRequire("lib/gitl/gitobj")
local gitref = localRequire("lib/gitl/gitref")
local filesystem = driver.filesystem

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

-- TODO: Actual correct formatting
local function createTreeDiffFormatterOptions(writeCallback, contextThreshold)
  return {
    addCallback = function(file, contentDiff)
      local diffContent = formatDiffContent(contentDiff, contextThreshold)
      local filesHeader =
        "diff --git a/" .. file .. " b/" .. file .. "\n"
        -- TODO: Next line
        .. "--- /dev/null\n"
        .. "+++ b/" .. file .. "\n"
      writeCallback(filesHeader .. diffContent .. "\n")
    end,
    removeCallback = function(file)
      local filesHeader =
        "diff --git a/" .. file .. " b/" .. file .. "\n"
        -- TODO: Next line
        .. "--- a/" .. file .. "\n"
        .. "+++ /dev/null\n"
      writeCallback(filesHeader .. "\n")
    end,
    diffCallback = function(file, contentDiff)
      local diffContent = formatDiffContent(contentDiff, contextThreshold)
      local filesHeader =
        "diff --git a/" .. file .. " b/" .. file .. "\n"
        -- TODO: Next line
        .. "--- a/" .. file .. "\n"
        .. "+++ b/" .. file .. "\n"
      writeCallback(filesHeader .. diffContent .. "\n")
    end
  }
end

local function diffDifferingTrees(treeDiff, options)
  if not (
    options.removeCallback and options.diffCallback
    and options.getTree1File and options.getTree2File
  ) then
    error("Missing callbacks for diffDifferingTrees")
  end

  if options.addCallback then
    for _, file in ipairs(treeDiff.insertions) do
      local file2 = options.getTree2File(file)
      local contentDiff = diff("", file2)
      options.addCallback(file, contentDiff)
    end
  end
  for _, file in ipairs(treeDiff.deletions) do
    options.removeCallback(file)
  end

  for _, file in ipairs(treeDiff.modifications) do
    local file1 = options.getTree1File(file)
    local file2 = options.getTree2File(file)

    -- Sometimes gitstat thinks the file has been changed, but it hasn't
    -- I should probably fix that
    if file1 ~= file2 then
      local contentDiff = diff(file1, file2)
      options.diffCallback(file, contentDiff)
    end
  end
end

local function getIndexFileContents(gitDir, index, file)
  local entry = gitdex.getEntry(index, file)
  local objectHash = entry.hash
  local objectType, objectData = gitobj.readObject(gitDir, objectHash)
  if objectType ~= "blob" then
    error("Expected blob object")
  end
  return objectData
end

-- TODO: A similar function is in gitstat.lua. Perhaps it needs abstracted?
local getTreeFileContents
getTreeFileContents = function(gitDir, treeHash, file)
  local contentType, contentData = gitobj.readObject(gitDir, treeHash)
  if contentType ~= "tree" then
    error("Expected tree object")
  end
  contentData = gitobj.decodeTreeData(contentData)

  local currentPart, nextPart
  local partAfterSlash = file:match("^.+/(.+)$")
  if partAfterSlash then
    currentPart = file:sub(1, #file - #partAfterSlash - 1)
    nextPart = partAfterSlash
  else
    currentPart = file
  end

  for _, entry in ipairs(contentData.entries) do
    if entry.name == currentPart then
      if (tonumber(entry.mode) == 40000) and nextPart then -- TODO: Is this check enough?
        return getTreeFileContents(gitDir, entry.hash, nextPart)
      elseif not nextPart or (#nextPart == 0) then
        local blobType, blobData = gitobj.readObject(gitDir, entry.hash)
        if blobType ~= "blob" then
          error("Expected blob object")
        end
        return blobData
      end
    end
  end

  return nil
end

local function getWorkingDirFileContents(projectDir, file)
  local path = filesystem.combine(projectDir, file)
  local contents = utils.readAll(path)
  return contents or ""
end

local function diffWorking(gitDir, projectDir, index, options)
  local treeDif = gitstat.compareWorkingWithIndex(gitDir, projectDir, index)
  local optionsClone = {}
  for k, v in pairs(options) do
    optionsClone[k] = v
  end
  optionsClone.getTree1File = function(file) return getIndexFileContents(gitDir, index, file) end
  optionsClone.getTree2File = function(file) return getWorkingDirFileContents(projectDir, file) end
  optionsClone.addCallback = nil -- New untracked files should not be included in the diff
  diffDifferingTrees(treeDif, optionsClone)
end

local function diffStaged(gitDir, index, options, commitOverride)
  local lastCommitHash = commitOverride or gitref.getLastCommitHash(gitDir)
  local _, commitObj = gitobj.readObject(gitDir, lastCommitHash)
  local treeHash = gitobj.decodeCommitData(commitObj).tree

  local stagedDif = gitstat.compareTreeWithIndex(gitDir, treeHash, index)

  local optionsClone = {}
  for k, v in pairs(options) do
    optionsClone[k] = v
  end
  optionsClone.getTree1File = function(file) return getTreeFileContents(gitDir, treeHash, file) end
  optionsClone.getTree2File = function(file) return getIndexFileContents(gitDir, index, file) end
  diffDifferingTrees(stagedDif, optionsClone)
end

local function diffTree(gitDir, tree1, tree2, options)
  local optionsClone = {}
  for k, v in pairs(options) do
    optionsClone[k] = v
  end
  optionsClone.getTree1File = function(file) return getTreeFileContents(gitDir, tree1, file) end
  optionsClone.getTree2File = function(file) return getTreeFileContents(gitDir, tree2, file) end

  local treeDiff = gitstat.compareTreeWithTree(gitDir, tree1, tree2)
  diffDifferingTrees(treeDiff, optionsClone)
end

return {
  diff = diff,
  hunkDiffContent = hunkDiffContent,
  formatDiffContent = formatDiffContent,
  createTreeDiffFormatterOptions = createTreeDiffFormatterOptions,
  diffWorking = diffWorking,
  diffStaged = diffStaged,
  diffTree = diffTree
}