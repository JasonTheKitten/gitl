local driver = localRequire "driver"
local configTool = localRequire "lib/configtool"
local filesystem = driver.filesystem

local function tryCreateFile(gitDir, name, content)
  local filePath = filesystem.combine(gitDir, name)
  local file = io.open(filePath, "w")
  if not file then
    error("Failed to create " .. name .. " file")
  end
  file:write(content)
  file:close()
end

local function createHeadFile(gitDir, defaultBranchName)
  tryCreateFile(gitDir, "HEAD", "ref: refs/heads/" .. defaultBranchName .. "\n")
end

local function createInitConfig(gitDir)
  local config = configTool.createConfig()
  config.section("core")
    .set("repositoryformatversion", 0)
    .set("filemode", false)
    .set("bare", false)
    .set("logallrefupdates", true)
  config.write(filesystem.combine(gitDir, "config"))
end

local function createDescriptionFile(gitDir)
  tryCreateFile(gitDir, "description", "Unnamed repository; edit this file 'description' to name the repository.\n")
end

local function run()
  local projectDir = filesystem.workingDir()
  local defaultBranchName = "main"
  local gitDir = filesystem.combine(projectDir, ".git")
  print("Initializing git repository in " .. projectDir)
  filesystem.makeDir(gitDir)

  createHeadFile(gitDir, defaultBranchName)
  createInitConfig(gitDir)
  createDescriptionFile(gitDir)
  filesystem.makeDir(filesystem.combine(gitDir, "hooks"))
  filesystem.makeDir(filesystem.combine(gitDir, "info"))
  filesystem.makeDir(filesystem.combine(gitDir, "objects"))
  filesystem.makeDir(filesystem.combine(gitDir, "refs"))
  filesystem.makeDir(filesystem.combine(gitDir, "refs/heads"))
  tryCreateFile(gitDir, "info/exclude", "# exclude files\n")
end

return {
  subcommand = "init",
  description = "Initialize a new git project",
  run = run
}