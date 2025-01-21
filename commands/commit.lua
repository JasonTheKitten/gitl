local driver = localRequire "driver"
local getopts = localRequire "lib/getopts"
local gitrepo = localRequire "lib/gitl/gitrepo"
local gitdex = localRequire "lib/gitl/gitdex"
local gitconfig = localRequire "lib/gitl/gitconfig"
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

local function run(arguments)
  local gitDir = gitrepo.locateGitRepo()
  if not gitDir then
    error("Not a git repository")
  end

  local authorName = gitconfig.get(gitDir, "user.name")
  local authorEmail = gitconfig.get(gitDir, "user.email")
  if not authorName or not authorEmail then
    -- TODO: Tell them how
    error("Author name or email not set - please edit your config")
  end
  local author = authorName .. " <" .. authorEmail .. ">"

  local commitTime = driver.utcTime()
  local commitTimeFormatted = os.date(nil, commitTime)

  local additionalEditMessage = "\n#\n# Date: " .. commitTimeFormatted .. "\n# Author: " .. author .. "\n#\n"

  local commitMsg =
    (arguments.options.message and arguments.options.message.arguments[1]) or
    editCommit(gitDir, DEFAULT_EDIT_MESSAGE .. additionalEditMessage)
  commitMsg = validateCommitMessage(commitMsg)
  -- TODO: Correct branch, correct hash
  local commitMsgShort = commitMsg:match("[^\r\n]+"):sub(1, 50)
  if #commitMsg > 50 then
    commitMsgShort = commitMsgShort .. "..."
  end

  local indexPath = filesystem.combine(gitDir, "index")
  local index = gitdex.readIndex(indexPath)
  local treeHash = gitdex.writeTreeFromIndex(gitDir, index)

  print("[main " .. treeHash:sub(1, 7) .. "] " .. commitMsgShort)
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
  },
  run = run
}