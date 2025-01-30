local GITHUB_URL = "https://raw.githubusercontent.com/JasonTheKitten/gitl/main/"
local computer = pcall(require, "computer")

local originalEnv = {}
for k, v in pairs(_G) do
  originalEnv[k] = v
end

---@diagnostic disable: undefined-global
---@diagnostic disable-next-line: undefined-field
if os.pullEvent then
  originalEnv.WORKING_DIR = shell.dir()
  originalEnv.DRIVER_NAME = "driver_cc"
  originalEnv.RUN = shell.run

  originalEnv.downloadFile = function(name)
    local handle = assert(http.get(GITHUB_URL .. name .. ".lua"))
    local fileContent = handle.readAll()
    handle.close()
    return fileContent
  end
elseif computer then
  local internet = require("internet")
  originalEnv.DRIVER_NAME = "driver_oc"
  originalEnv.downloadFile = function(name)
    local handle = assert(internet.request(GITHUB_URL .. name .. ".lua"))
    local fileContent = ""
    for chunk in handle do
      fileContent = fileContent .. chunk
    end
    return fileContent
  end
else
  local request = require("http.request")
  originalEnv.DRIVER_NAME = "driver_puc"
  originalEnv.downloadFile = function(name)
    local req = request.new_from_uri(GITHUB_URL .. name .. ".lua")
    local headers, stream = assert(req:go())
    local body = assert(stream:get_body_as_string())
    return body
  end
end

local cache = {}
local localRequire
function localRequire(name)
  if cache[name] then
    return cache[name]
  end

  local env = {}
  for k, v in pairs(originalEnv) do
    env[k] = v
  end
  env.localRequire = localRequire

  local loadName = name
  if loadName == "driver" then
    if originalEnv.DRIVER_NAME then
      loadName = "drivers/" .. originalEnv.DRIVER_NAME
    else
      loadName = "drivers/driver_puc"
    end
  end
  
  local programText = originalEnv.downloadFile(loadName)
  local ok, err = load(programText, loadName, "t", env)
  if not ok then
    error(err)
  end

  local result = ok()
  cache[name] = result
  return result
end

--

print("Downloading additional files")

local getopts = localRequire("lib/getopts")

local cloneCommand = localRequire("commands/clone")
local optionsSpec = { clone = cloneCommand }

local options = getopts.options(optionsSpec)
local ok, results = getopts.parse(options, { "clone", "https://github.com/JasonTheKitten/gitl.git" }, {
  argumentPreprocessor = getopts.argumentPreprocessors.detect,
  delimiter = "-%",
  commandKey = "command",
  requireSubcommand = false
})

if not ok then
  error(results)
end

print("Starting installation...")
cloneCommand.run(results.clone)

print("Setting some things up...")
---@diagnostic disable-next-line: undefined-field
if os.pullEvent then
  local pathText = [[--Add gitl to the path
shell.setPath(shell.path() .. ":/gitl/bin")]]
  print("COPY gitl/misc/dumbrun.lua /bin/luajit")
  shell.run("copy gitl/misc/dumbrun.lua /bin/luajit")
  if fs.isDir("startup") then
    print("CREATE startup/50_gitl.lua")
    local file = assert(io.open("startup/50_gitl.lua", "w"))
    file:write(pathText)
    file:close()
  else
    print("APPEND startup.lua")
    local file = assert(io.open("startup.lua", "a"))
    file:write("\n" .. pathText)
    file:close()
  end
elseif computer then
  local pathText = [[--Add gitl to the path
os.setenv("PATH", os.getenv("PATH") .. ":/gitl/bin")]]
  print("COPY gitl/misc/dumbrun.lua /bin/luajit")
  os.execute("copy gitl/misc/dumbrun.lua /bin/luajit")
  print("APPEND /etc/profile.lua")
  local file = assert(io.open("/etc/profile.lua", "a"))
  file:write("\n" .. pathText)
  file:close()
else
  local pathText = [[#Add gitl to the path
export PATH=$PATH":/home/jason/Code/gitl/bin"]]
  print("SETMODE gitl/bin/gitl")
  os.execute("chmod u+x gitl/bin/gitl")
  print("APPEND ~/.bashrc")
  local bashrcPath = os.getenv("HOME") .. "/.bashrc"
  local file = assert(io.open(bashrcPath, "a"))
  file:write("\n" .. pathText)
  file:close()
end

print("Installation complete! Reboot to add gitl to your path.")
print("For future updates, cd into the installation directory and `run gitl pull origin main`.")