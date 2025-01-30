local args = { ... }
local program = table.remove(args, 1)

local env = {}
for k, v in pairs(_G) do
  env[k] = v
end

---@diagnostic disable: undefined-global
if shell then
  env.WORKING_DIR = shell.dir()
  env.DRIVER_NAME = "driver_cc"
  env.PROGRAM_LOCATION = fs.combine(program, "../..") .. "/"
  env.RUN = shell.run
elseif computer then
  env.DRIVER_NAME = "driver_oc"
  env.PROGRAM_LOCATION = filesystem.concat(program, "../..") .. "/"
end

loadfile(program, "t", env)(table.unpack(args))