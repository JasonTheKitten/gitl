local lfs = require "lfs"

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDir = scriptPath:match("(.*/)") or "./"

local driver = {}

driver.filesystem = {}
driver.filesystem.workingDir = function()
    return lfs.currentdir()
end
driver.filesystem.codeDir = function()
    return scriptDir
end
driver.filesystem.combine = function(...)
    return table.concat({...}, "/")
end
driver.filesystem.list = function(path)
    local files = {}
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            table.insert(files, file)
        end
    end
    return files
end

return driver