local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitconfig = localRequire("lib/gitl/gitconfig")
local gitrepo = localRequire("lib/gitl/gitrepo")
local filesystem = driver.filesystem

local listConfigPart
listConfigPart = function(gitDir, builtName, customConfigList)
  local configPart = gitconfig.list(gitDir, builtName, customConfigList)
  for _, value in pairs(configPart) do
    local builtKey = builtName .. (builtName == "" and "" or ".") .. value
    local configValue = gitconfig.get(gitDir, builtKey)
    if type(configValue) == "table" then
      listConfigPart(gitDir, builtKey)
    else
      print(builtKey .. "=" .. tostring(configValue))
    end
  end
end

local function list(gitDir, customConfigList)
  listConfigPart(gitDir, "", customConfigList)
end

local function get(gitDir, customConfigList, name)
  local value = gitconfig.get(gitDir, name, nil, customConfigList)
  if value then
    print(value)
  end
end

local function set(gitDir, customConfigList, name, value)
  gitconfig.set(gitDir, name, value, customConfigList)
end

local function unset(gitDir, customConfigList, name)
  local oldValue = gitconfig.get(gitDir, name, customConfigList)
  if not oldValue then
    error("error: key does not exist: " .. name, -1)
  end
  gitconfig.remove(gitDir, name, customConfigList)
end

local function renameSection(gitDir, customConfigList, oldName, newName)
  local oldValue = gitconfig.get(gitDir, oldName, customConfigList)
  if not oldValue or (type(oldValue) ~= "table") then
    error("error: section does not exist: " .. oldName, -1)
  end
  local newValue = gitconfig.get(gitDir, newName, customConfigList)
  if newValue then
    error("error: section already exists: " .. newName, -1)
  end
  gitconfig.set(gitDir, newName, oldValue, customConfigList)
end

local function removeSection(gitDir, customConfigList, name)
  local oldValue = gitconfig.get(gitDir, name, customConfigList)
  if not oldValue or (type(oldValue) ~= "table") then
    error("error: section does not exist: " .. name, -1)
  end
  gitconfig.remove(gitDir, name, customConfigList)
end

local function run(arguments)
  local commandList = {
    list = list,
    get = get,
    set = set,
    unset = unset,
    ["rename-section"] = renameSection,
    ["remove-section"] = removeSection,
  }

  local gitDir = gitrepo.locateGitRepo()

  local command = arguments.options.command
  if not command then
    error("error: missing subcommand", -1)
  end

  local commandFunction = commandList[command]
  if not commandFunction then
    error("error: unknown subcommand: " .. command, -1)
  end

  local customConfigList = {}
  if arguments.options.global then
    table.insert(customConfigList, gitconfig.getGlobalConfig())
  end
  if arguments.options.local_ then
    table.insert(customConfigList, gitconfig.getLocalConfig(gitDir))
  end
  if arguments.options.file then
    local file = filesystem.resolve(arguments.options.file.arguments[1])
    table.insert(customConfigList, gitconfig.getPathConfig(file))
  end
  
  if #customConfigList > 1 then
    error("error: cannot use multiple scope flags", -1)
  end

  local myArguments = arguments.options[command].options.arguments
  commandFunction(gitDir, customConfigList, myArguments[1], myArguments[2])
end

return {
  subcommand = "config",
  description = "Get and set repository or global options",
  options = {
    list = {
      subcommand = "list",
      description = "List all options",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(0)) },
      }
    },
    get = {
      subcommand = "get",
      description = "Get the value of an option",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<configname>" },
      }
    },
    set = {
      subcommand = "set",
      description = "Set the value of an option",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), params = "<configname> <value>" },
      }
    },
    unset = {
      subcommand = "unset",
      description = "Unset the value of an option",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<configname>" },
      }
    },
    ["rename-section"] = {
      subcommand = "rename-section",
      description = "Rename a section",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), params = "<oldname> <newname>" },
      }
    },
    ["remove-section"] = {
      subcommand = "remove-section",
      description = "Remove a section",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<name>" },
      }
    },
    global = { flag = "global", description = "Use the global configuration file" },
    local_ = { flag = "local", description = "Use the repository configuration file" },
    file = { flag = "file", description = "Use the specified configuration file", params = "<file>", multiple = getopts.stop.times(1) },
  },
  run = run,
}