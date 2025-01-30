local computer = pcall(require, "computer")

local args = { ... }
local program = table.remove(args, 1)

local env = {}
for k, v in pairs(_G) do
  env[k] = v
end

---@diagnostic disable: undefined-global
if os.pullEvent then
  env.WORKING_DIR = shell.dir()
  env.DRIVER_NAME = "driver_cc"
  env.PROGRAM_LOCATION = fs.combine(program, "../..") .. "/"
  env.RUN = shell.run
elseif computer then
  local filesystem = require("filesystem")
  env.DRIVER_NAME = "driver_oc"
  env.PROGRAM_LOCATION = filesystem.concat(program, "../..") .. "/"
end

if computer then
  local fileHandle = assert(io.open(program, "r"))
  local content = fileHandle:read("*a")
  fileHandle:close()

  content = content:gsub("#!/bin/luajit", "")
  content = content:gsub("#!/bin/lua", "")
  ---@diagnostic disable-next-line: deprecated
  assert(load(content, program, "t", env))((table.unpack or unpack)(args))
else
  ---@diagnostic disable-next-line: deprecated
  assert(loadfile(program, "t", env))((table.unpack or unpack)(args))
end