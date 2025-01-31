local gitobj = localRequire("lib/gitl/gitobj")

--

local function decodeShortNameCommand(command)
  local commands, ptr = {}, 1

  local function decodeNumber()
    local number = 0
    while true do
      local char = command:sub(ptr, ptr)
      ptr = ptr + 1
      local value = tonumber(char, 10)
      if value == nil then
        return number == 0 and 1 or number
      end
      number = number * 10 + value
    end
  end

  -- The first command should be a commit hash
  local hash = ""
  while (ptr <= #command) and (ptr <= 40) do
    local char = command:sub(ptr, ptr)
    local byte = char:byte()
    -- Check if byte is number, uppercase, or lowercase
    if (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 123) then
      hash = hash .. char
      ptr = ptr + 1
    else break end
  end
  if #hash < 3 then
    return nil, "Hash is not long enough"
  end
  table.insert(commands, hash)

  while ptr <= #command do
    local char = command:sub(ptr, ptr)
    if (char == "~") or (char == "^") then
      ptr = ptr + 1
      local number = decodeNumber()
      table.insert(commands, char)
      table.insert(commands, number)
    else
      return nil, "Invalid character in short name"
    end
  end

  return commands
end


local function getNthParent(gitDir, hash, n)
  local commit = gitobj.readAndDecodeObject(gitDir, hash, "commit")
  if n > #commit.parents then
    return nil, "No such parent"
  end

  return commit.parents[n]
end

local function getNthAncestor(gitDir, hash, n)
  local commit = gitobj.readAndDecodeObject(gitDir, hash, "commit")
  local parent = commit.parents[1]
  for i = 1, n - 1 do
    if not parent then
      return nil, "No such ancestor"
    end
    parent = gitobj.readAndDecodeObject(gitDir, parent, "commit").parents[1]
  end

  return parent
end

local function determineHashFromShortName(gitDir, shortName, preserveBranch)
  local commands, err = decodeShortNameCommand(shortName)
  if not commands then
    return nil, err
  end

  local hash
  hash, err = gitobj.resolveObject(gitDir, commands[1])
  if #commands == 1 and err == "branch" and preserveBranch then
    return commands[1], true
  end

  for i = 2, #commands, 2 do
    local command = commands[i]
    if command:sub(1, 1) == "~" then
      local n = commands[i + 1]
      hash, err = getNthAncestor(gitDir, hash, n)
      if not hash then return nil, err end
    elseif command:sub(1, 1) == "^" then
      local n = commands[i + 1]
      hash, err = getNthParent(gitDir, hash, n)
      if not hash then return nil, err end
    end
  end

  return hash
end

--

-- There are ways to optimize this in the future if need be
local function compareNthValue(paths, n)
  local tail = paths[1][#(paths[1]) - n + 1]
  for i = #paths, 1, -1 do
    if paths[i][#paths[i] - n + 1] ~= tail then
      return paths[i][#paths[i] - n + 2]
    end
  end
  return paths[1][#paths[1] - n + 1]
end
local function getLowestTableSize(paths)
  local lowest = #paths[1]
  for i = 2, #paths do
    if #paths[i] < lowest then
      lowest = #paths[i]
    end
  end
  return lowest
end
local function determineClosestAncestor(paths)
  local lowest = getLowestTableSize(paths)
  local lastValue
  for i = 1, lowest do
    local nextValue = compareNthValue(paths, i)
    if not nextValue then break end
    lastValue = nextValue
  end

  return lastValue
end

local function getCommitAncestors(gitDir, commitHash)
  local ancestors = {}
  local current = commitHash
  while current do
    local currentCommit = gitobj.readAndDecodeObject(gitDir, current, "commit", true)
    if currentCommit then
      table.insert(ancestors, current)
    end
    current = currentCommit and currentCommit.parents[1] -- TODO: What if there are multiple parents
  end
  
  return ancestors
end

local function determineNearestAncestor(gitDir, commits)
  local paths = {}
  for _, commit in ipairs(commits) do
    table.insert(paths, getCommitAncestors(gitDir, commit))
  end
  return determineClosestAncestor(paths)
end

return {
  determineHashFromShortName = determineHashFromShortName,
  getCommitAncestors = getCommitAncestors,
  determineNearestAncestor = determineNearestAncestor
}