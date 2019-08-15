FUEL = {
    ["minecraft:coal"] = true,
    ["minecraft:lava"] = true,
}

GATHERABLE = {
    ["minecraft:wheat"] = 7,
}

PLANTABLE = {
    ["minecraft:seed"] = true,
}

CHESTS = {
    ["minecraft:chest"] = true,
}

INVENTORY_SIZE = 16

TICKS_TO_WAIT = 2000

CAN_MOVE_OVER = {
    ["minecraft:water"] = true
}

REFUEL_THRESHOLD = 100

DO_NOT_REFUEL = true

--------------------------------------------------------------------------------

-- keeps path made by turtle so far
PATH = nil
-- keeps move number
MOVE_ID = nil
-- coordinate of turtle relative to startup point
COORD = nil
-- direction of the turtle (0-3)
DIRECTION = nil

-- construct coordinate
function Coord(a, b)
    return { x = a, y = b }
end

-- copy coordinate
function CoordCopy(a)
    return { x = a.x, y = a.y }
end

-- compare two coordinates
function coord_eq(t1, t2)
    return t1.x == t2.x and t1.y == t2.y
end

-- print message with a timestamp
function log(message)
    print("[" .. os.date() .. " " .. os.time() .. "] " .. message)
end

-- search inventory using predicate
function findInInventory(predicate)
    for i = 1,INVENTORY_SIZE do
        if predicate(turtle.getItemDetail(i)) then
            return i
        end
    end
    return nil
end

-- gather harvestable block and then plant something in this place
function gatherAndPlant()
    if turtle.dig() then
        local slotToPlant = findInInventory(function(item) return PLANTABLE[item.name] end)
        if slotToPlant == nil then
            log("Failed to plant: nothing to plant!")
        else
            turtle.select(slotToPlant)
            local placed = turtle.place()
            if not placed then
                log("Failed to plant: " .. turtle.getItemDetail(slotToPlant))
            end
        end
    else
        log("Failed to gather block: " .. turtle.inspect())
    end
end

-- gather everything we could gather in current position
function gather()
    local function tryGatherAndPlant() if canGather() then gatherAndPlant() end end
    tryGatherAndPlant()
    -- we dont use rotate() because we always do 360 here
    turtle.turnRight()
    tryGatherAndPlant()
    turtle.turnRight()
    turtle.turnRight()
    tryGatherAndPlant()
    turtle.turnRight()
end

-- reset turtle state
function reset()
    log("Resetting state...")
    PATH = {}
    MOVE_ID = 0
    COORD = Tuple(0, 0)
    DIRECTION = 0
end

-- wait for a number of ticks
function wait(ticks)
    local t = (1 / 20) * ticks
    log("Waiting for " .. t .. "s ...")
    os.sleep(t)
end

-- test whether we can move in selected direction
function canMove()
    local hasBlockInFront, _ = turtle.inspect()
    local _, block = turtle.inspectDown()
    return not hasBlockInFront and CAN_MOVE_OVER[block.name]
end

-- change selected direction
function rotate(dir)
    if dir == nil or dir == "right" then
        DIRECTION = (DIRECTION + 1) % 4
    elseif dir == "left" then
        if DIRECTION == 0 then
            DIRECTION = 3
        else
            DIRECTION = DIRECTION - 1
        end
    else
        error("Unknown direction " .. dir)
    end
end

-- change direction to specified
function rotateToDirection(direction)
    if direction == DIRECTION then return end
    while DIRECTION ~= direction do rotate() end
end

-- move in selected direction
function move()
    if turtle.forward() then
        if     DIRECTION == 0 then
            COORD.x = COORD.x + 1
        elseif DIRECTION == 1 then
            COORD.y = COORD.y + 1
        elseif DIRECTION == 2 then
            COORD.x = COORD.x - 1
        elseif DIRECTION == 3 then
            COORD.y = COORD.y - 1
        end
        MOVE_ID = MOVE_ID + 1
        PATH[MOVE_ID] = CoordCopy(COORD)
        return true
    else
        return false
    end
end

-- find move and rotate in correct direction
function findMove()
    if canMove() then return true end
    rotate()
    if canMove() then return true end
    rotate()
    rotate()
    return canMove()
end

-- test whether we are in origin (i.e. place we started from)
function isInOrigin()
    return coord_eq(PATH[MOVE_ID], COORD)
end

-- search inventory for fuel and refuel with it
function refuel()
    local fuel = findInInventory(function (item) return FUEL[item.name] end)
    if fuel == nil then
        return false
    else
        turtle.select(fuel)
        log("Refueling with " .. turtle.getItemDetail())
        return turtle.refuel()
    end
end

-- test whether we need to be refueled
function needRefuel()
    return turtle.getFuelLevel() < REFUEL_THRESHOLD
end

-- unload products
function unloadProducts()
    local function tryUnload()
        for i = 1,INVENTORY_SIZE do
            turtle.select(i)
            local item = turtle.getItemDetail()
            if item ~= nil and not PLANTABLE[item] and not GATHERABLE[item] then
                if not turtle.drop() then
                    return false
                end
            end
        end
        return true
    end

    local successfullyUnloaded = false
    for i = 1,4 do
        local f, block = turtle.inspect()
        if f and CHESTS[block.name] then
            successfullyUnloaded = tryUnload()
        end
        turtle.turnRight()
    end

    return successfullyUnloaded
end

function main()
    log("Starting up...")
    reset()
    while true do
        gather()

        if findMove() then
            move()
        else
            log("Cannot move from this position!")
        end

        if isInOrigin() then
            if not unloadProducts() then
                log("Failed to unload products at origin, either no chest or it is full")
                break
            end
            rotateToDirection(0)
            reset()
            wait()
        end

        if needRefuel() then
            if DO_NOT_REFUEL then
                break;
            end
            if refuel() then
                log("Refueled to " .. turtle.getFuelLevel())
            else
                log("Failed to refuel: no fuel in inventory!")
            end
        end
    end
    log("Shutting down...")
end

main()
