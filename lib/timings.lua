local timingsRate, timings, recentTimings, calls, ongoingTimings = {}, {}, {}, {}, {}

local function displayTimingsReport(name)
  local rate = timingsRate[name]
  if rate then
    local totalTime = timings[name]
    local totalCalls = calls[name]
    local avgTime = totalCalls > 0 and (totalTime / totalCalls) or 0
    local avgRecentTime = totalCalls > 0 and (recentTimings[name] / rate) or 0
    print(string.format(
      "Timings report for %s: Total time: %.2fms, Total calls: %d, Average time: %.2fms, Average recent time: %.2fms",
      name, totalTime * 1000, totalCalls, avgTime * 1000, avgRecentTime * 1000))
  else
    print("No timings data available for " .. name)
  end
end

local function enableTimings(name, rate)
  rate = rate or 100
  timingsRate[name] = rate
  timings[name] = 0
  recentTimings[name] = 0
  calls[name] = 0
end

local function startTiming(name)
  if timings[name] and not ongoingTimings[name] then
    ongoingTimings[name] = os.clock()
    calls[name] = calls[name] + 1
  end
end

local function stopTiming(name)
  if ongoingTimings[name] then
    local elapsed = os.clock() - ongoingTimings[name]
    ongoingTimings[name] = nil
    timings[name] = timings[name] + elapsed
    recentTimings[name] = recentTimings[name] + elapsed
    if calls[name] % timingsRate[name] == 0 then
      displayTimingsReport(name)
      recentTimings[name] = 0
    end
  end
end

return {
  enableTimings = enableTimings,
  startTiming = startTiming,
  stopTiming = stopTiming,
  displayTimingsReport = displayTimingsReport
}