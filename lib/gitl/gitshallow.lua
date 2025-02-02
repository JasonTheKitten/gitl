local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local filesystem = driver.filesystem

local function getShallowCommits(gitDir)
  local shallowPath = filesystem.combine(gitDir, "shallow")
  if not filesystem.exists(shallowPath) then
    return {}
  end
  
  local shallowFile = utils.readAll(shallowPath)
  local shallowCommits = {}
  for line in shallowFile:gmatch("[^\r\n]+") do
    shallowCommits[line] = true
  end

  return shallowCommits
end

local function storeShallowCommits(gitDir, shallowCommits)
  local shallowPath = filesystem.combine(gitDir, "shallow")
  local shallowFile = ""
  for commit in pairs(shallowCommits) do
    shallowFile = shallowFile .. commit .. "\n"
  end
  utils.writeAll(shallowPath, shallowFile)
end

return {
  getShallowCommits = getShallowCommits,
  storeShallowCommits = storeShallowCommits
}