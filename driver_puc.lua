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
    if (str:sub(1, 1) == "/") and (path:sub(1, 1) ~= "/") then
        return str:sub(2)
    end
    if (str:sub(1, 1) ~= "/") and (path:sub(1, 1) == "/") then
        return "/" .. str
    end

    return str
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
driver.filesystem.isFile = function(path)
    return lfs.attributes(path, "mode") == "file"
end
driver.filesystem.isDir = function(path)
    return lfs.attributes(path, "mode") == "directory"
end
driver.filesystem.attributes = function(path)
    local rawAttributes = lfs.attributes(path)
    -- TODO: File perms
    return {
        ctime = rawAttributes.change, -- TODO: Check if this is correct
        mtime = rawAttributes.modification,
        dev = rawAttributes.dev,
        ino = rawAttributes.ino,
        uid = rawAttributes.uid,
        gid = rawAttributes.gid,
        size = rawAttributes.size,
    }
end
driver.filesystem.unprefix = function(basePath, otherPath)
    local baseInode = lfs.attributes(basePath, "ino")
    local builtSuffix = ""
    while true do
        local otherInode = lfs.attributes(otherPath, "ino")
        if otherInode == baseInode then
            return builtSuffix
        end
        if otherPath[#otherPath] == "/" then
            otherPath = otherPath:sub(1, #otherPath - 1)
        end
        local lastSlash = otherPath:find("/[^/]*$")
        if not lastSlash then
            error("No common prefix")
        end
        builtSuffix = driver.filesystem.combine(otherPath:sub(lastSlash + 1), builtSuffix)
        otherPath = driver.filesystem.combine(otherPath, "..")
    end
end

local function symbolicPermsToNumeric(perms)
    -- ‘rw-r--r--’ -> 0644
    local numericPerms = 0
    for i = 1, 9 do
        local base = 2 ^ (9 - i)
        local char = perms:sub(i, i)
        if char ~= "-" then
            numericPerms = numericPerms + base
        end
    end

    -- to octal
    local permsStr = string.format("%o", numericPerms)
    if permsStr:sub(-2) == ".0" then
        return permsStr:sub(1, -3)
    end
    return permsStr
end
driver.filesystem.openWriteProtected = function(path, mode)
    local oldPerms = lfs.attributes(path, "permissions")
    if not oldPerms then
        return io.open(path, mode)
    end
    oldPerms = symbolicPermsToNumeric(oldPerms)
    os.execute("chmod 0660 " .. path)
    local file, err = io.open(path, mode)
    if not file then
        os.execute("chmod " .. oldPerms .. " " .. path)
        return file, err
    end

    local newFile = {}
    for k, v in pairs({ "read", "write", "seek", "flush" }) do
        newFile[v] = function(self, ...)
            return file[v](file, ...)
        end
    end
    newFile.close = function(self)
        file:close()
        os.execute("chmod " .. oldPerms .. " " .. path)
    end
    return newFile, err
end

return driver