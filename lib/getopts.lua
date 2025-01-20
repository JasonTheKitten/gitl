local FLAGS_SYMBOL, FLAGS_MAP_SYMBOL, FLAGLESS_SYMBOL, SUBCOMMANDS_SYMBOL, SUBCOMMANDS_MAP_SYMBOL = {}, {}, {}, {}, {}

-- TODO: Implement mandatory flags, default arguments, and argument conversion

local function reportInvalidArguments(message)
  coroutine.yield(message)
end

local flagless = {}
flagless.collect = function(collector)
  return collector
end

local stop = {}
stop.remaining = function(collected)
  return function(value)
    table.insert(collected, value)
    return true
  end, function()
    return true
  end
end
stop.times = function(times)
  return function(collected)
    return function(value)
      if #collected >= times then
        return false
      end
      table.insert(collected, value)
      return true
    end, function(flagName)
      if #collected ~= times then
        reportInvalidArguments("Expected " .. times .. " argument(s) for flag " .. flagName .. ", got " .. #collected)
      end
    end
  end
end
stop.none = function(collected)
  return function()
    return false
  end, function(flagName)
    if #collected > 0 then
      reportInvalidArguments("No arguments expected for flag " .. flagName .. ", got " .. #collected)
    end
  end
end
stop.single = function(collected)
  return stop.times(1)(collected)
end

local argumentPreprocessors = {}
argumentPreprocessors.detect = function(arguments)
  return arguments
end

local function generateFlagMap(options, flag)
  for _, flagName in ipairs(flag.flag) do
    local name = "--" .. flagName
    if options[FLAGS_MAP_SYMBOL][name] then
      error("Flag " .. name .. " is already defined")
    end
    options[FLAGS_MAP_SYMBOL][name] = flag
  end
  for _, flagName in ipairs(flag.short) do
    local name = "-" .. flagName
    if options[FLAGS_MAP_SYMBOL][name] then
      error("Flag " .. name .. " is already defined")
    end
    options[FLAGS_MAP_SYMBOL][name] = flag
  end
end

local function generateSubcommandMap(options, subcommand)
  for _, subcommandName in ipairs(subcommand.subcommand) do
    if options[SUBCOMMANDS_MAP_SYMBOL][subcommandName] then
      error("Subcommand " .. subcommandName .. " is already defined")
    end
    options[SUBCOMMANDS_MAP_SYMBOL][subcommandName] = subcommand
  end
end

local function tablify(value)
  if type(value) == "table" then
    return value
  elseif value == nil then
    return {}
  else
    return { value }
  end
end

local validateOptionsSpec, validateFlagSpec, validateSubcommandSpec

validateOptionsSpec = function(spec)
  local options = {
    [FLAGS_SYMBOL] = {},
    [FLAGS_MAP_SYMBOL] = {},
    [SUBCOMMANDS_SYMBOL] = {},
    [SUBCOMMANDS_MAP_SYMBOL] = {},
  }

  for key, value in pairs(spec or {}) do
    if type(value) == "table" then
      if value.flag and type(value.flag) == "function" then
        options[key] = value.flag
        if options[FLAGLESS_SYMBOL] then
          error("Flagless argument can only be specified once")
        end
        options[FLAGLESS_SYMBOL] = {
          key = key,
          collector = value.flag
        }
      elseif value.flag then
        local flag = validateFlagSpec(value, key)
        options[key] = flag
        table.insert(options[FLAGS_SYMBOL], flag)
        generateFlagMap(options, flag)
      elseif value.subcommand then
        local subcommand = validateSubcommandSpec(value)
        options[key] = subcommand
        table.insert(options[SUBCOMMANDS_SYMBOL], subcommand)
        generateSubcommandMap(options, subcommand)
      end
    end
  end

  if options[FLAGLESS_SYMBOL] and #options[SUBCOMMANDS_SYMBOL] > 0 then
    error("Flagless argument cannot be used with subcommands")
  end

  return options
end

validateFlagSpec = function(spec, key)
  return {
    key = key,
    flag = tablify(spec.flag),
    short = tablify(spec.short),
    description = spec.description or "No description provided",
    multiple = spec.multiple or stop.none
  }
end

validateSubcommandSpec = function(spec)
  return {
    subcommand = tablify(spec.subcommand),
    description = spec.description or "No description provided",
    options = validateOptionsSpec(spec.options)
  }
end

local function options(spec)
  return validateOptionsSpec(spec)
end

local function generateHelpMessage(options)
  local helpMessage = ""
  if #options[FLAGS_SYMBOL] > 0 then
    helpMessage = helpMessage .. "Flags:\n"
  end
  for _, flag in ipairs(options[FLAGS_SYMBOL]) do
    local formattedFlags = {}
    for _, flagName in ipairs(flag.flag) do
      table.insert(formattedFlags, "--" .. flagName)
    end
    for _, flagName in ipairs(flag.short) do
      table.insert(formattedFlags, "-" .. flagName)
    end
    helpMessage = helpMessage .. "  " .. table.concat(formattedFlags, ", ") .. " - " .. flag.description .. "\n"
  end
  if #options[SUBCOMMANDS_SYMBOL] > 0 then
    helpMessage = helpMessage .. "Subcommands:\n"
  end
  for _, subcommand in ipairs(options[SUBCOMMANDS_SYMBOL]) do
    helpMessage = helpMessage .. "  " .. table.concat(subcommand.subcommand, ", ") .. " - " .. subcommand.description .. "\n"
    helpMessage = helpMessage .. generateHelpMessage(subcommand.options)
  end
  return helpMessage:sub(1, -2)
end

local innerParse
local function determineDefaultCollector(options, arguments, config, results)
  local subcommands, subcommandsMap = options[SUBCOMMANDS_SYMBOL], options[SUBCOMMANDS_MAP_SYMBOL]
  if options[FLAGLESS_SYMBOL] then
    return options[FLAGLESS_SYMBOL].collector
  end

  if #subcommands > 0 then
    return function()
      return function(value, index)
        if not subcommandsMap[value] then
          reportInvalidArguments("Invalid subcommand: " .. value)
        end
        results[config.commandKey] = value
        results[value] = {
          options = innerParse(subcommandsMap[value].options, arguments, index + 1, config)
        }

        return -1
      end, function()
        if not results[config.commandKey] and config.requireSubcommand ~= false then
          reportInvalidArguments("No subcommand provided")
        end
      end
    end
  end

  return function(collected)
    return function(_, index)
      reportInvalidArguments("Unexpected argument: " .. arguments[index])
    end, function()
      if #collected > 0 then
        reportInvalidArguments("Unexpected argument: " .. collected[1])
      end
    end
  end
end

innerParse = function(options, arguments, slice, config)
  local results, stopped, subcommands, flagsMap = {}, false, options[SUBCOMMANDS_SYMBOL], options[FLAGS_MAP_SYMBOL]

  local flaglessArguments = {}
  local defaultCollector = determineDefaultCollector(options, arguments, config, results)
  local defaultCollectorNext, defaultCollectorValidate = defaultCollector(flaglessArguments)

  local currentCollectorNext, currentCollectorValidate, currentArguments = defaultCollectorNext, defaultCollectorValidate, flaglessArguments

  local function endCurrentCollector()
    if currentCollectorNext == defaultCollectorNext then return end
    currentCollectorValidate()
    currentCollectorNext, currentCollectorValidate = defaultCollectorNext, defaultCollectorValidate
    currentArguments = flaglessArguments
  end

  for i = slice, #arguments do
    if stopped then break end

    if arguments[i] == config.delimiter then
      endCurrentCollector()
    elseif flagsMap[arguments[i]] then
      endCurrentCollector()
      local flag = flagsMap[arguments[i]]
      currentArguments = {}
      results[flag.key] = { arguments = currentArguments }
      currentCollectorNext, currentCollectorValidate = flag.multiple(currentArguments)
    else
      local result = currentCollectorNext(arguments[i], i)
      if result == false then
        endCurrentCollector()
        result = currentCollectorNext(arguments[i], i)
      end
      if result == -1 then
        stopped = true
      end
      if result == false then
        reportInvalidArguments("Unexpected argument: " .. arguments[i])
      end
    end
  end

  if #subcommands > 0 and not results[config.commandKey] and config.requireSubcommand ~= false then
    reportInvalidArguments("No subcommand provided")
  end
  
  currentCollectorValidate()
  defaultCollectorValidate()

  if options[FLAGLESS_SYMBOL] then
    results[options[FLAGLESS_SYMBOL].key] = flaglessArguments
  elseif #flaglessArguments > 0 then
    reportInvalidArguments("Unexpected argument: " .. flaglessArguments[1])
  end

  return results
end

local function parse(options, arguments, config)
  local argumentPreprocessor = config.argumentPreprocessor
  local adjustedArguments = argumentPreprocessor and argumentPreprocessor(arguments) or arguments
  local co = coroutine.create(function()
    return innerParse(options, adjustedArguments, 1, config)
  end)
  local ok, result = coroutine.resume(co)
  if not ok then
    error(result)
  end

  if type(result) == "string" then
    return false, result
  else
    if coroutine.status(co) ~= "dead" then
      error("Coroutine unexpectedly still running")
    end
    return true, result
  end
end

return {
  options = options,
  parse = parse,
  generateHelpMessage = generateHelpMessage,
  flagless = flagless,
  stop = stop,
  argumentPreprocessors = argumentPreprocessors
}