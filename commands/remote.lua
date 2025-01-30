
local getopts = localRequire("lib/getopts")
local gitconfig = localRequire("lib/gitl/gitconfig")
local gitrepo = localRequire("lib/gitl/gitrepo")

local function setUrl(gitDir, name, newUrl)
  if not gitconfig.has(gitDir, { "remote", name, "url" }) then
    error("error: No such remote: \"" .. name .. "\"")
  end
  gitconfig.set(gitDir, { "remote", name, "url" }, newUrl)
end

local function getUrl(gitDir, name)
  print(gitconfig.get(gitDir, { "remote", name, "url" }))
end

local function add(gitDir, name, url)
  if gitconfig.has(gitDir, { "remote", name, "url" }) then
    error("error: remote \"" .. name .. "\" already exists")
  end
  gitconfig.set(gitDir, { "remote", name, "url" }, url)
end

local function remove(gitDir, name)
  if not gitconfig.has(gitDir, { "remote", name, "url" }) then
    error("error: No such remote: \"" .. name .. "\"")
  end
  gitconfig.remove(gitDir, { "remote", name, "url" })
end

local function rename(gitDir, oldName, newName)
  local url = gitconfig.get(gitDir, { "remote", oldName, "url" })
  if not url then
    error("error: No such remote: \"" .. oldName .. "\"")
  end
  if gitconfig.has(gitDir, { "remote", newName, "url" }) then
    error("error: remote \"" .. newName .. "\" already exists")
  end

  gitconfig.remove(gitDir, { "remote", oldName, "url" })
  gitconfig.set(gitDir, { "remote", newName, "url" }, url)
end

local function list(gitDir, verbose)
  local remotes = gitconfig.list(gitDir, { "remote" })
  for _, remote in ipairs(remotes) do
    if verbose then
      local url = gitconfig.get(gitDir, { "remote", remote, "url" })
      print(remote .. "\t" .. url)
    else
      print(remote)
    end
  end
end

local function run(arguments)
  local commandList = {
    ["set-url"] = setUrl,
    ["get-url"] = getUrl,
    add = add,
    remove = remove,
    rename = rename,
  }

  local gitDir = gitrepo.locateGitRepo()
  local commandName = arguments.options.command
  if not commandName then
    list(gitDir, arguments.options.verbose)
    return
  end

  local command = commandList[commandName]
  local commandArguments = arguments.options[commandName].options.arguments
  command(gitDir, commandArguments[1], commandArguments[2])
end

return {
  subcommand = "remote",
  description = "Manage set of tracked repositories",
  options = {
    ["set-url"] = {
      subcommand = "set-url",
      description = "Change the URL of a remote repository",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), params = "<name> <newurl>" }
      },
    },
    ["get-url"] = {
      subcommand = "get-url",
      description = "Retrieves the URL of a remote repository",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<name>" }
      },
    },
    add = {
      subcommand = "add",
      description = "Add a remote repository",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), params = "<name> <url>" }
      },
    },
    remove = {
      subcommand = "remove",
      description = "Remove a remote repository",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<name>" }
      },
    },
    rename = {
      subcommand = "rename",
      description = "Rename a remote repository",
      options = {
        arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), params = "<oldname> <newname>" }
      },
    },
    verbose = { flag = "verbose", short = "v", description = "Be verbose" },
  },
  run = run
}