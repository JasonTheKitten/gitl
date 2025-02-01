local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitobj = localRequire("lib/gitl/gitobj")
local gitdex = localRequire("lib/gitl/gitdex")
local gitref = localRequire("lib/gitl/gitref")
local gitconfig = localRequire("lib/gitl/gitconfig")
local gitignore = localRequire("lib/gitl/gitignore")
local filesystem = driver.filesystem

local DEFAULT_EDIT_MESSAGE = "\n# Please enter the commit message for your changes. Lines starting\n"
  .. "# with '#' will be ignored, and an empty message aborts the commit."

local function editCommit(gitDir, editMessage)
  -- TODO: Get config editor
  local editMsgFile = filesystem.combine(gitDir, "COMMIT_EDITMSG")
  local editMsgHandle = assert(io.open(editMsgFile, "w"))
  editMsgHandle:write(editMessage)
  editMsgHandle:close()

  driver.edit(editMsgFile)

  editMsgHandle = assert(io.open(editMsgFile, "r"))
  local commitMsg = editMsgHandle:read("*a")
  editMsgHandle:close()

  return commitMsg
end

local function validateCommitMessage(commitMsg)
  local noCommentLines = {}
  for line in commitMsg:gmatch("[^\r\n]+") do
    if line:sub(1, 1) ~= "#" then
      table.insert(noCommentLines, line)
    end
  end
  commitMsg = table.concat(noCommentLines, "\n")

  if commitMsg:gsub("\n", "") == "" then
    error("Commit message is empty")
  end

  return commitMsg
end

local function addAllChanges(gitDir, projectDir)
  local filter = gitignore.createFileFilter(projectDir)
  local indexFile = filesystem.combine(gitDir, "index")
  local index = filesystem.exists(indexFile) and gitdex.readIndex(indexFile) or gitdex.createIndex()
  gitdex.addToIndex(gitDir, index, projectDir, "", filter)
  gitdex.clearOldIndexEntries(projectDir, index, projectDir, "", filter)
  gitdex.writeIndex(index, indexFile)
end

local function determineParentsAndInitialMessage(gitDir, arguments)
  local currentCommit = gitref.getLastCommitHash(gitDir)
  if arguments.options.amend then
    local commitData = gitobj.readAndDecodeObject(gitDir, currentCommit, "commit")
    return commitData.parents, commitData.message
  else
    return { gitref.getLastCommitHash(gitDir) }, ""
  end
end

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())

  local authorName = gitconfig.get(gitDir, "user.name")
  local authorEmail = gitconfig.get(gitDir, "user.email")
  if not authorName or not authorEmail then
    error("Author name or email not set - please edit your config\n"
      .. "To set your name, run `gitl config --global set user.name <name>`\n"
      .. "To set your email, run `gitl config --global set user.email <email>`", -1)
  end

  if arguments.options.all then
    addAllChanges(gitDir, assert(gitrepo.locateProjectRepo()))
  end

  local author = authorName .. " <" .. authorEmail .. ">"

  local commitTime, commitOffset = driver.timeAndOffset()
  local commitTimeFormatted = os.date("%a %b %d %H:%M:%S %Y", commitTime)

  local indexPath = filesystem.combine(gitDir, "index")
  local index = gitdex.readIndex(indexPath)
  local treeHash = gitdex.writeTreeFromIndex(gitDir, index)

  local commitParents, message = determineParentsAndInitialMessage(gitDir, arguments)

  local additionalEditMessage = "\n#\n# Date: " .. commitTimeFormatted .. "\n# Author: " .. author .. "\n#\n"

  local commitMsg =
    (arguments.options.message and arguments.options.message.arguments[1]) or
    editCommit(gitDir, message .. DEFAULT_EDIT_MESSAGE .. additionalEditMessage)
  commitMsg = validateCommitMessage(commitMsg)
  -- TODO: Correct branch, correct hash
  local commitMsgShort = commitMsg:match("[^\r\n]+"):sub(1, 50)
  if #commitMsg > 50 then
    commitMsgShort = commitMsgShort .. "..."
  end

  local commitData = {
    tree = treeHash,
    parents = commitParents,
    author = author,
    committer = author,
    authorTime = commitTime,
    authorTimezoneOffset = commitOffset,
    committerTime = commitTime,
    committerTimezoneOffset = commitOffset,
    message = commitMsg
  }

  local commitHash = gitobj.writeObject(gitDir, gitobj.encodeCommitData(commitData), "commit")
  gitref.setLastCommitHash(gitDir, commitHash)

  local formattedCommitHash = assert(gitref.formatCurrentCommitRef(gitDir))
  print(formattedCommitHash .. " " .. commitMsgShort)
  print(" Date: " .. commitTimeFormatted)
  print(" Author: " .. author)
end

return {
  subcommand = "commit",
  description = "Record changes to the repository",
  options = {
    message = {
      flag = "message", short = "m", params = "<msg>", description = "Use the commit message <msg>",
      multiple = getopts.stop.times(1)
    },
    all = { flag = "all", short = "a", description = "Commit all changes" },
    amend = { flag = "amend", description = "Amend the last commit" }
  },
  run = run
}