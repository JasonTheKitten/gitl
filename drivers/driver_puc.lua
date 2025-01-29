local lfs = require "lfs"
local httpRequest = require "http.request"

local driver = {}

driver.filesystem = {}
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
    local result = table.concat({...}, "/")
    
    local hasSlash, args, i = false, {...}, 1
    while i ~= -1 and args[i] do
        if args[i] == "" then
            i = i + 1
        elseif args[i]:sub(1, 1) == "/" then
            hasSlash = true
            i = -1
        else
            i = i + 1
        end
    end

    if not hasSlash and result:sub(1, 1) == "/" then
        return result:sub(2)
    end
    return result
end

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDir = driver.filesystem.combine(scriptPath:match("(.*/)") or "./", "..")
driver.filesystem.workingDir = function()
    return lfs.currentdir()
end
driver.filesystem.codeDir = function()
    return scriptDir
end
driver.filesystem.homeDir = function()
    return os.getenv("HOME")
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
driver.filesystem.makeDir = function(path, recursive)
    if recursive then
        local parent = driver.filesystem.collapse(driver.filesystem.combine(path, ".."))
        if parent ~= "" and not driver.filesystem.exists(parent) then
            driver.filesystem.makeDir(parent, true)
        end
    end
    lfs.mkdir(driver.filesystem.collapse(path))
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

local function getNanoTime(path)
    local statPHandle = io.popen("stat " .. path)
    if not statPHandle then return end
    local statOutput = statPHandle:read("*a")
    statPHandle:close()

    local ctimeNs = statOutput:match("Change: ([^\n]+)\n")
    if ctimeNs then
        ctimeNs = tonumber(ctimeNs:match("%.(%d+) "))
    end

    local mtimeNs = statOutput:match("Modify: ([^\n]+)\n")
    if mtimeNs then
        mtimeNs = tonumber(mtimeNs:match("%.(%d+) "))
    end

    return ctimeNs, mtimeNs
end
driver.filesystem.attributes = function(path)
    local ctimeNanos, mtimeNanos = getNanoTime(path)
    local rawAttributes = lfs.attributes(path)
    -- TODO: File perms
    return {
        ctime = rawAttributes.change,
        ctimeNanos = ctimeNanos,
        mtime = rawAttributes.modification,
        mtimeNanos = mtimeNanos,
        fmode = rawAttributes.permissions,
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

driver.filesystem.rm = function(path, recursive)
    if recursive and driver.filesystem.isDir(path) then
        for file in lfs.dir(path) do
            if file ~= "." and file ~= ".." then
                driver.filesystem.rm(driver.filesystem.combine(path, file), true)
            end
        end
    end
    os.remove(path)
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

driver.http = {}
driver.http.get = function(url, headers)
    local req = httpRequest.new_from_uri(url)
    req.headers:upsert(":method", "GET")
    for k, v in pairs(headers) do
        req.headers:upsert(k, v)
    end
    local respHeaders, stream = assert(req:go())
    local body = assert(stream:get_body_as_file())
    return {
        headers = respHeaders,
        status = tonumber(respHeaders:get(":status")),
        body = body,
    }
end
driver.http.post = function(url, headers, body)
    local req = httpRequest.new_from_uri(url)
    req.headers:upsert(":method", "POST")
    for k, v in pairs(headers) do
        req.headers:upsert(k, v)
    end
    req:set_body(body)
    local respHeaders, stream = assert(req:go())

    local respBody = {}
    local currentChunk, chunkPointer = "", 0
    function respBody:read(n)
        local builtResponse, builtResponseLen = {}, 0
        while builtResponseLen < n do
            if chunkPointer == #currentChunk then
                currentChunk = stream:get_next_chunk()
                chunkPointer = 0
            end
            if not currentChunk then
                error("No more data from remote (Did it time out?)")
            end

            local toRead = math.min(n - builtResponseLen, #currentChunk - chunkPointer)
            table.insert(builtResponse, currentChunk:sub(chunkPointer + 1, chunkPointer + toRead))
            builtResponseLen = builtResponseLen + toRead
            chunkPointer = chunkPointer + toRead
        end

        return table.concat(builtResponse)
    end
    function respBody:close()
        stream:shutdown()
    end
    
    return {
        headers = respHeaders,
        status = tonumber(respHeaders:get(":status")),
        body = respBody,
    }
end

driver.timeAndOffset = function()
    local timestamp = os.time()
    local utcTime = os.date("!*t", timestamp)
    local localTime = os.date("*t", timestamp)

    ---@diagnostic disable-next-line: param-type-mismatch
    local timezoneOffsetSeconds = os.difftime(os.time(localTime), os.time(utcTime))

    local sign = (timezoneOffsetSeconds >= 0) and "+" or "-"
    local absTimezoneOffsetSeconds = math.abs(timezoneOffsetSeconds)
    local hours = math.floor(absTimezoneOffsetSeconds / 3600)
    local minutes = math.floor((absTimezoneOffsetSeconds % 3600) / 60)
    local timezoneOffsetStr = string.format("%s%02d%02d", sign, hours, minutes)

    return timestamp, timezoneOffsetStr
end

driver.edit = function(file, editorOverride)
    if editorOverride then
        os.execute(editorOverride .. " " .. file)
        return
    end

    local envEditor = os.getenv("EDITOR")
    local editorSearchList = { "vim", "vi", "nano", "emacs" }
    if envEditor then
        table.insert(editorSearchList, 1, envEditor)
    end
    for _, editor in ipairs(editorSearchList) do
        if driver.filesystem.exists(editor) then
            os.execute(editor .. " " .. file)
            return
        end

        local path = os.getenv("PATH") or ""
        for dir in path:gmatch("[^:]+") do
            if driver.filesystem.exists(driver.filesystem.combine(dir, editor)) then
                os.execute(driver.filesystem.combine(dir, editor) .. " " .. file)
                return
            end
        end
    end

    error("No editor found")
end

local function openFallbackLongMessageDisplay()
    local display = {}
    function display:write(...)
        io.write(...)
    end
    function display:close()
        io.write("\n")
    end

    return display
end

driver.openLongMessageDisplay = function(message)
    local pager = os.getenv("PAGER") or "/usr/bin/less"
    local pagerBin = driver.filesystem.combine("/usr/bin", pager)
    if not (driver.filesystem.exists(pager) or driver.filesystem.exists(pagerBin)) then
        return openFallbackLongMessageDisplay()
    end
    return assert(io.popen(pager, "w"))
end

driver.disableCursor = function()
    io.write("\27[?25l")
end
driver.enableCursor = function()
    io.write("\27[?25h")
end
driver.resetCursor = function()
    io.write("\r")
end

driver.readPassword = function()
    os.execute("stty -echo")
    local password = io.read()
    os.execute("stty echo")
    return password
end

driver.hasFileModes = function()
    return true
end
driver.hasPreciseTime = function()
    return true
end

return driver