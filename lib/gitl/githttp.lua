local driver = localRequire("driver")
local gitpak = localRequire("lib/gitl/gitpak")
local http = driver.http

local GIT_USER_AGENT = "git/2.30.0"

local function downloadAvailableRefs(repository)
  local packFileURL = repository .. "info/refs?service=git-upload-pack"
  local packFileHandle = http.get(packFileURL, {
    ["content-type"] = "application/x-git-upload-pack-request",
    ["user-agent"] = GIT_USER_AGENT,
    ["git-protocol"] = "version=1"
  })

  local response = {
    head = nil,
    branches = {},
    capabilities = {}
  }

  local numZerosEncountered = 0
  while numZerosEncountered < 2 do
    local n = packFileHandle.body:read(4)
    local objectLength = tonumber(n, 16) - 4
    if objectLength == -4 then
      numZerosEncountered = numZerosEncountered + 1
    else
      local nextLine = packFileHandle.body:read(objectLength):gsub("[\n\r]", "")
      if nextLine:sub(1, 1) ~= "#" then
        local spaceIndex = nextLine:find(" ")
        local zeroIndex = nextLine:find("\0") or (#nextLine + 1)
        local hash = nextLine:sub(1, spaceIndex - 1)
        local branchName = nextLine:sub(spaceIndex + 1, zeroIndex - 1)
        if branchName == "HEAD" then
          response.head = hash
          for capability in nextLine:sub(zeroIndex + 1):gmatch("[^%s]+") do
            local equalsIndex = capability:find("=")
            if equalsIndex then
              response.capabilities[capability:sub(1, equalsIndex - 1)] = capability:sub(equalsIndex + 1)
            else
              response.capabilities[capability] = true
            end
          end
        else
          response.branches[branchName] = hash
        end
      end
    end
  end

  packFileHandle.body:close()

  return response
end

local function formatLineSize(line)
  return string.format("%04x", #line + 4)
end

local function formatPackFileOptions(options)
  local message = ""
  for _, v in ipairs(options.wants) do
    local wantLine = "want " .. v .. "\n"
    message = message .. formatLineSize(wantLine) .. wantLine
  end
  message = message .. "00000009done\n"
  return message
end

local function downloadPackFile(repository, options, pakOptions)
  local packFileURL = repository .. "git-upload-pack"
  local postBody = formatPackFileOptions(options)
  local packFileHandle = http.post(packFileURL, postBody, {
    ["content-type"] = "application/x-git-upload-pack-request",
    ["user-agent"] = GIT_USER_AGENT,
    ["git-protocol"] = "version=1"
  })

  -- Read all and print
  assert(packFileHandle.body:read(8) == "0008NAK\n", "Expected NAK response")
  gitpak.decodePackFile(packFileHandle.body, pakOptions)
  packFileHandle.body:close()
end

return {
  downloadAvailableRefs = downloadAvailableRefs,
  downloadPackFile = downloadPackFile
}