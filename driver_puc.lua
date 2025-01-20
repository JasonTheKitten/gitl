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
driver.filesystem.collapse = function(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 then
                table.remove(parts, #parts)
            end
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    local str = table.concat(parts, "/")

    return #str > 0 and str or "/"
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
driver.filesystem.makeDir = function(path)
    lfs.mkdir(path)
end
driver.filesystem.exists = function(path)
    return lfs.attributes(path) ~= nil
end

return driver