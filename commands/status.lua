local gitstat = localRequire("lib/gitl/gitstat")
local gitrepo = localRequire("lib/gitl/gitrepo")

local DEFAULT_CHANGES_STAGED_MESSAGE = "Changes to be committed:\n"
  .. "  (use \"gitl restore --staged <file>...\" to unstage)"

local DEFAULT_CHANGES_NOT_STAGED_MESSAGE = "Changes not staged for commit:\n"
  .. "  (use \"gitl add/rm <file>...\" to update what will be committed)\n"
  .. "  (use \"gitl restore <file>...\" to discard changes in working directory)"

local UNTRACKED_FILES_MESSAGE = "Untracked files:\n"
  .. "  (use \"gitl add <file>...\" to include in what will be committed)"

local NO_CHANGES_ADDED_MESSAGE = "no changes added to commit (use \"gitl add\")"

local function printFullStatus(allChanges)
  local treeChanges = allChanges.treeChanges
  if #treeChanges.insertions > 0 or #treeChanges.deletions > 0 or #treeChanges.modifications > 0 then
    print(DEFAULT_CHANGES_STAGED_MESSAGE)
    for k, v in pairs(treeChanges.insertions) do
      print("        new file:   " .. v)
    end
    for k, v in pairs(treeChanges.deletions) do
      print("        deleted:    " .. v)
    end
    for k, v in pairs(treeChanges.modifications) do
      print("        modified:   " .. v)
    end
    print()
  end

  local workingDirChanges = allChanges.workingDirChanges
  -- TODO: Terminal coloring
  if #workingDirChanges.deletions > 0 or #workingDirChanges.modifications > 0 then
    print(DEFAULT_CHANGES_NOT_STAGED_MESSAGE)
    -- TODO: Perhaps deletions and modifications should be sorted
    for k, v in pairs(workingDirChanges.deletions) do
      print("        deleted:    " .. v)
    end
    for k, v in pairs(workingDirChanges.modifications) do
      print("        modified:   " .. v)
    end
    print()
  end

  if #workingDirChanges.insertions > 0 then
    print(UNTRACKED_FILES_MESSAGE)
    for k, v in pairs(workingDirChanges.insertions) do
      print("        " .. v)
    end
    print()
  end

  if #treeChanges.insertions == 0 and #treeChanges.deletions == 0 and #treeChanges.modifications == 0 then
    print(NO_CHANGES_ADDED_MESSAGE)
  end
end

local function printShortStatus(allChanges)
  local treeChanges = allChanges.treeChanges
  for k, v in pairs(treeChanges.insertions) do
    print("A  " .. v)
  end
  for k, v in pairs(treeChanges.deletions) do
    print("D  " .. v)
  end
  for k, v in pairs(treeChanges.modifications) do
    print("M  " .. v)
  end

  local workingDirChanges = allChanges.workingDirChanges
  for k, v in pairs(workingDirChanges.deletions) do
    print(" D " .. v)
  end
  for k, v in pairs(workingDirChanges.modifications) do
    print(" M " .. v)
  end

  for k, v in pairs(workingDirChanges.insertions) do
    print("?? " .. v)
  end
end

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())
  local projectDir = assert(gitrepo.locateProjectRepo())

  local allChanges = gitstat.stat(gitDir, projectDir)
  if arguments.options.short then
    printShortStatus(allChanges)
  else
    printFullStatus(allChanges)
  end
end

return {
  subcommand = "status",
  description = "Show the working tree status",
  options = {
    short = { flag = "short", short = "s", description = "Show status in short format" }
  },
  run = run
}