REACTOR_SIDE = "right"
MONITOR_SIDE = "monitor_0"
MONITOR_BACKGROUND_COLOR = colors.gray
MONITOR_CHART_COLOR = "1" -- colors.orange
MONITOR_CHART_BACKGROUND_COLOR = "f" -- colors.black
MONITOR_TEXT_COLOR = colors.white

REACTOR_STATE_CHANGE_COOLDOWN = 4

UPDATE_FREQUENCY = 10

ENERGY_THRESHOLD_LOW  = 7500000
ENERGY_THRESHOLD_HIGH = 7700000

WASTE_EJECTION_THRESHOLD = 144 * 64

N_DATA_POINTS_TO_KEEP = 64
N_REGRESS = N_DATA_POINTS_TO_KEEP

GOOD_TREND_REST = 0.0
GOOD_TREND_DELTA = 500.0

SHOW_CHART = true

CHART_W = 32
CHART_H = 10

-- sleep for a specified number of ticks
function sleep(ticks)
    local t = (1 / 20) * ticks
    os.sleep(t)
end


function closeTo(x, val, delta)
    return math.abs(x - val) < delta
end


function crlf(monitor)
    local x, y = monitor.getCursorPos()
    monitor.setCursorPos(1, y + 1)
end


function connectMonitor(side)
    local monitor = peripheral.wrap(side)
    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(MONITOR_BACKGROUND_COLOR)
    monitor.clear()
    monitor.setCursorPos(1, 1)
    return monitor
end

-- connect to a reactor at specified side
function connectReactor(side)
    local reactor = peripheral.wrap(side)
    if reactor == nil then
        print("Failed to connect reactor at side " .. side)
        return nil
    end
    if not reactor.getConnected() then
        print("Reactor is in invalid state! Check for integrity.")
        return nil
    end
    if reactor.isActivelyCooled() then
        print("Active cooling is not supported.")
        return nil
    end
    return reactor
end

-- prints series, mostly for debugging
function printSeries(series, length)
    local line = ""
    for i = 1, length do
        if series[i] == nil then
            line = line .. ", nil"
        else
            if i == 1 then
                line = tostring(series[i])
            else
                line = line .. ", " .. tostring(series[i])
            end
        end
    end
    print(line)
end

-- pushes point into series. if series reached max length, discards the oldest value.
function pushPoint(series, maxLength, val)
    if series[maxLength] ~= nil then
        for i = 1,maxLength do
            series[i] = series[i + 1]
        end
        series[maxLength] = val
    else
        for i = 1,maxLength do
            if series[i] == nil then
                series[i] = val
                break
            end
        end
    end
end

-- computes min and max over the series. stops when either length or NIL value reached
function getMinMax(series, length)
    local min =  1e100
    local max = -1e100
    for i = 1, length do
        if series[i] == nil then
            break
        end
        if series[i] < min then
            min = series[i]
        end
        if series[i] > max then
            max = series[i]
        end
    end
    return min, max
end

-- performs simple linear regression on time series, returns A and B, where y' = A + B*x'
function regress(series, length)
    local sy, sxy = 0, 0
    for i = 1, length do
        if series[i] == nil then
            length = i - 1
            break
        end
        sy  = sy  + series[i]
        sxy = sxy + series[i]*i
    end
    local sx = length * (length + 1) / 2
    local sxx = length * (length + 1) * (2*length + 1) / 6
    local b = (length * sxy - sx * sy) / (length * sxx - sx * sx)
    local a = (sy - b * sx) / length
    return a, b
end

-- prints out the bar chart, showing the series and trend.
-- - will truncate series at `w` points, drawing one index per column
-- - min, max and trendB are printed out below the chart
function barChartWithTrend(monitor, series, w, h, trendA, trendB)
    local min, max = getMinMax(series, w)

    local fill = "."
    local empty = "."
    local trendFill = "."

    local function interp(val)
        return h - math.ceil((val - min) / (max - min) * h)
    end

    local trendColor;
    if trendB <= 0 then
        trendColor = "e" -- colors.red
    else
        trendColor = "d" -- colors.green
    end

    local x, y = monitor.getCursorPos()
    monitor.setCursorPos(1, y)

    local mW, mH = monitor.getSize()
    local seriesCutoff = 0
    if w > mW then
        -- TODO this feels hacky, implement cleaner solution?
        local realLength = 0
        for i = 1,w do
            if series[i] == nil then 
                realLength = i
                break 
            end
        end
        if realLength > mW then
            seriesCutoff = realLength - mW
        end
    end

    for i = 1, h - 1 do
        local line = ""
        local colors = ""
        
        for j = 1, w do
            local trendY = trendA + trendB * (j + seriesCutoff)
            local trend = interp(trendY)

            if trend == i then
                line = line .. trendFill
                colors = colors .. trendColor
            else
                if series[j] == nil then
                    line = line .. string.rep(empty, w - j + 1)
                    colors  = colors .. string.rep(MONITOR_CHART_BACKGROUND_COLOR, w - j + 1)
                    break
                end

                local sh = interp(series[j + seriesCutoff])

                if sh <= i then
                    line = line .. fill
                    colors = colors .. MONITOR_CHART_COLOR
                else
                    line = line .. empty
                    colors = colors .. MONITOR_CHART_BACKGROUND_COLOR
                end
            end
        end
        monitor.blit(line, colors, colors)
        crlf(monitor)
    end

    monitor.setTextColor(MONITOR_TEXT_COLOR)
    monitor.write(string.format("min = %8d, max = %8d, trend = %8d", min, max, trendB))
    crlf(monitor)
end




-- main loop
function main()
    local reactor = connectReactor(REACTOR_SIDE)
    if reactor == nil then return end
    print(
        "Connected reactor | " .. REACTOR_SIDE .. 
        ", # control rods: " .. reactor.getNumberOfControlRods()
    )

    local monitor = connectMonitor(MONITOR_SIDE)
    local monW, monH = monitor.getSize()
    if monitor ~= nil then
        print(
            "Connected monitor | " .. MONITOR_SIDE .. 
            ", color = " .. tostring(monitor.isColor()) .. 
            ", res: " .. tostring(monW) .. "x" .. tostring(monH)
        )
    end


    local dataPoints = {}
    local tickN = 0
    local lastReactorStateChange = 0
    local lastTrend = 0

    while true do
        local energy = reactor.getEnergyStored()

        pushPoint(dataPoints, N_DATA_POINTS_TO_KEEP, energy)
        -- printSeries(dataPoints, N_DATA_POINTS_TO_KEEP)

        local a, b = regress(dataPoints, N_REGRESS)

        local waste = reactor.getWasteAmount()
        if waste > WASTE_EJECTION_THRESHOLD then
            reactor.doEjectWaste()
        end

        monitor.setBackgroundColor(MONITOR_BACKGROUND_COLOR)
        monitor.clear()
        monitor.setCursorPos(1, 1)

        if SHOW_CHART then
            barChartWithTrend(monitor, dataPoints, monW, monH - 4, a, b)
        end

        monitor.setTextColor(colors.yellow)
        monitor.write(
            "levels: " .. tostring(reactor.getControlRodLevel(0)) .. 
            " / fuel: " .. tostring(reactor.getFuelAmount()) ..
            " / waste: " .. tostring(reactor.getWasteAmount()) 
        )
        crlf(monitor)

        if (energy + b) < ENERGY_THRESHOLD_LOW then
            -- TODO: more sophisticated strategy?
            local allControlRodLevels = reactor.getControlRodLevel(0)
            local newLevels = allControlRodLevels - 1
            if tickN - lastReactorStateChange > REACTOR_STATE_CHANGE_COOLDOWN and b <= lastTrend then
                if newLevels >= 0 then
                    monitor.write("! control rod levels: " .. tostring(allControlRodLevels) .. " -> " .. tostring(newLevels))
                    crlf(monitor)
                    lastReactorStateChange = tickN
                    reactor.setAllControlRodLevels(newLevels)
                else
                    monitor.setBackgroundColor(colors.red)
                    monitor.write("!!! energy underprovisioning, cannot increase production any further !!!")
                    crlf(monitor)
                end
            end
        -- TODO review this condition
        elseif (energy + b) > ENERGY_THRESHOLD_HIGH or closeTo(b, GOOD_TREND_REST, GOOD_TREND_DELTA) then
            -- TODO: more sophisticated strategy?
            local allControlRodLevels = reactor.getControlRodLevel(0)
            local newLevels = allControlRodLevels + 1
            if tickN - lastReactorStateChange > REACTOR_STATE_CHANGE_COOLDOWN and b >= lastTrend then
                if newLevels <= 99 then
                    monitor.write("! control rod levels: " .. tostring(allControlRodLevels) .. " -> " .. tostring(newLevels))
                    crlf(monitor)
                    lastReactorStateChange = tickN
                    reactor.setAllControlRodLevels(newLevels)
                else
                    monitor.setBackgroundColor(colors.red)
                    monitor.write("!!! energy overprovisioning, cannot decrease production any further !!!")
                    crlf(monitor)
                end
            end
        end

        tickN = tickN + 1
        lastTrend = b
        sleep(UPDATE_FREQUENCY)
    end

    print("Shutting down...")
end

main()
