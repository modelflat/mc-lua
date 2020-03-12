REACTOR_SIDE = "back"

UPDATE_FREQUENCY = 40

ENERGY_THRESHOLD_LOW  =  3000000
ENERGY_THRESHOLD_HIGH = 11000000

WASTE_EJECTION_THRESHOLD = 144 * 64

N_DATA_POINTS_TO_KEEP = 128
N_REGRESS = N_DATA_POINTS_TO_KEEP

GOOD_TREND_REST = 0.0
GOOD_TREND_DELTA = 500.0

SHOW_CHART = true
SHOW_CHART_EACH_TICK = 10

CHART_W = 32
CHART_H = 10
CHART_FILL = "#"
CHART_EMPTY = " "
CHART_FILL_TREND = "."

-- print message with a timestamp
function log(message)
    print("[" .. os.date() .. " " .. os.time() .. "] " .. message)
end

-- sleep for a specified number of ticks
function sleep(ticks)
    local t = (1 / 20) * ticks
    log("Sleeping for " .. t .. "s ...")
    os.sleep(t)
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
function barChartWithTrend(series, w, h, fill, empty, trendA, trendB, trendFill)
    local min, max = getMinMax(series, w)

    local function interp(val)
        return h - math.ceil((val - min) / (max - min) * h)
    end

    for i = 1, h - 1 do
        local line = ""
        for j = 1, w do
            local trendY = trendA + trendB * j

            local trend = interp(trendY)
            if trend == i then
                line = line .. trendFill
            else
                if series[j] == nil then
                    break
                end

                local sh = interp(series[j])

                if sh <= i then
                    line = line .. fill
                else
                    line = line .. empty
                end
            end
        end
        print(line)
    end
    print(string.format("|min = %8d, max = %8d, trend = %.1f", min, max, trendB))
end


function closeTo(x, val, delta)
    return math.abs(x - val) < delta
end


-- main loop
function main()
    local reactor = connectReactor(REACTOR_SIDE)
    if reactor == nil then return end

    print("Connected reactor (" .. side .. ", # control rods: " .. reactor.getNumberOfControlRods() .. ").")

    local dataPoints = {}
    local tickN = 0

    while true do
        local energy = reactor.getEnergyStored()

        pushPoint(dataPoints, N_DATA_POINTS_TO_KEEP, energy)

        local a, b = regress(dataPoints, N_REGRESS)

        if (energy + b) < ENERGY_THRESHOLD_LOW then
            -- TODO: more sophisticated strategy?
            local allControlRodLevels = reactor.getControlRodLevel(0)
            local newLevels = allControlRodLevels - 1
            if newLevels >= 0 then
                print("! control rod levels: " .. tostring(allControlRodLevels) .. " -> " .. tostring(newLevels))
                reactor.setAllControlRodLevels(newLevels)
            else
                print("!!! energy underprovisioning, cannot increase production any further !!!")
            end
        end

        -- TODO review this condition
        if (energy + b) > ENERGY_THRESHOLD_HIGH or closeTo(b, GOOD_TREND_REST, GOOD_TREND_DELTA) then
            -- TODO: more sophisticated strategy?
            local allControlRodLevels = reactor.getControlRodLevel(0)
            local newLevels = allControlRodLevels + 1
            if newLevels <= 99 then
                print("! control rod levels: " .. tostring(allControlRodLevels) .. " -> " .. tostring(newLevels))
                reactor.setAllControlRodLevels(newLevels)
            else
                print("!!! energy overprovisioning, cannot decrease production any further !!!")
            end
        end

        local waste = reactor.getWasteAmount()
        if waste > WASTE_EJECTION_THRESHOLD then
            reactor.doEjectWaste()
        end

        if SHOW_CHART and (tickN % SHOW_CHART_EACH_TICK == 0) then
            barChartWithTrend(dataPoints, CHART_W, CHART_H, CHART_FILL, CHART_EMPTY, a, b, CHART_FILL_TREND)
        end

        tickN = tickN + 1
        sleep(UPDATE_FREQUENCY)
    end

    print("Shutting down...")
end

main()
