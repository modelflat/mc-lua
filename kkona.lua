-- what to use as fuel
FUEL = {
    ["minecraft:coal"] = true,
    ["minecraft:lava"] = true,
}

-- what blocks to gather <- age
GATHERABLE = {
    ["minecraft:wheat"] = 7,
    ["minecraft:carrots"] = 7,
    ["harvestcraft:pamstrawberrycrop"] = 3,
    ["actuallyadditions:block_canola"] = 7,
}

-- what seeds to plant <- priority
PLANTABLE = {
    ["minecraft:wheat_seeds"] = 1,
    ["minecraft:carrot"] = 2,
    ["actuallyadditions:item_canola_seed"] = 1,
}

-- what to interpret as chest
CHESTS = {
    ["minecraft:chest"] = true,
    ["quark:custom_chest"] = true,
}

INVENTORY_SIZE = 16

TICKS_TO_WAIT = 20 * 600

CAN_MOVE_OVER = {
    ["minecraft:water"] = true
}

REFUEL_THRESHOLD = 100

REFUEL_ENABLED = true

REFUEL_COUNT = 1

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

-- search inventory using weight function
function findInInventoryWithPriority(weight)
    local highest = 0
    local highestId = 1
    for i = 1,INVENTORY_SIZE do
        local w = weight(turtle.getItemDetail(i))
        if w ~= nil and w > highest then
            highest = w
            highestId = i
        end
    end
    return highestId
end     

-- test whether the block in front can be gathered
function canGather()
    local notAir, block = turtle.inspect()
    if notAir and GATHERABLE[block.name] then
        return GATHERABLE[block.name] == block.state.age
    end
end

-- gather harvestable block and then plant something in this place
function gatherAndPlant()
    if turtle.dig() then
        turtle.suck()
        local slotToPlant = findInInventoryWithPriority(function(item) return item and PLANTABLE[item.name] end)
        if slotToPlant == nil then
            log("Failed to plant: nothing to plant!")
        else
            turtle.select(slotToPlant)
            local placed = turtle.place()
            if not placed then
                local item = turtle.getItemDetail(slotToPlant)
                log("Failed to plant: " .. item.name)
            end
        end
    else
        log("Failed to gather block!")
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
    PATH = {[0] = Coord(0, 0)}
    MOVE_ID = 0
    COORD = Coord(0, 0)
    DIRECTION = 0
end

-- wait for a number of ticks
function wait(ticks)
    local t = (1 / 20) * ticks
    log("Waiting for " .. t .. "s ...")
    os.sleep(t)
end

-- change selected direction
function rotate(dir)
    if dir == nil or dir == "right" then
        DIRECTION = (DIRECTION + 1) % 4
        turtle.turnRight()
    elseif dir == "left" then
        if DIRECTION == 0 then
            DIRECTION = 3
        else
            DIRECTION = DIRECTION - 1
        end
        turtle.turnLeft()
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
function moveForward()
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

-- test whether we can move in selected direction
function canMove()
    return not turtle.detect()
end

-- test whether we are on a block we are not supposed to be on
function movementConstraintViolated()
    local _, block = turtle.inspectDown()
    return not CAN_MOVE_OVER[block.name]
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

-- take a move
function move()
    local found = false
    if findMove() then
        local dir = DIRECTION
        repeat
            if moveForward() then
                if movementConstraintViolated() then
                    turtle.back()
                    rotate()
                else 
                    found = true
                    break
                end
            else
                error("cannot move in the direction pointed by findMove()")
                break
            end
        until dir == DIRECTION
    end

    if not found then
        log("Cannot move from this position!")
        return false
    end

    return true
end


-- test whether we are in origin (i.e. place we started from)
function isInOrigin()
    return coord_eq(PATH[0], COORD)
end

-- search inventory for fuel and refuel with it
function refuel()
    local fuel = findInInventory(function (item) return item ~= nil and FUEL[item.name] end)
    if fuel == nil then
        return false
    else
        turtle.select(fuel)
        local fuelItem = turtle.getItemDetail()
        local n = math.min(REFUEL_COUNT, fuelItem.count)
        log("Refueling with " .. fuelItem.name .. "x" .. n)
        return turtle.refuel(n)
    end
end

-- test whether we need to be refueled
function needRefuel()
    return turtle.getFuelLevel() < REFUEL_THRESHOLD
end

-- try unloading items into block in front
function tryUnload()
    for i = 1,INVENTORY_SIZE do
        turtle.select(i)
        local item = turtle.getItemDetail()
        if item ~= nil and not FUEL[item.name] then
            if not turtle.drop() then
                return false
            end
            log("Unloaded " .. item.name .. "x" .. item.count)
        end
    end
    return true
end

-- unload products
function unloadProducts()
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
    if movementConstraintViolated() then
        error("Turtle is placed in a position to which it cannot return (due to movement constraint violation)")
        return 1
    end
    reset()
    while true do
        gather()

        if not move() then
            return 1
        end

        if isInOrigin() then
            if not unloadProducts() then
                log("Failed to unload products at origin, either no chest or it is full")
                rotateToDirection(0)
                return 1
            end
            rotateToDirection(0)
            reset()
            wait(TICKS_TO_WAIT)
        end

        if needRefuel() then
            if REFUEL_ENABLED then
                if refuel() then
                    log("Refueled to " .. turtle.getFuelLevel())
                else
                    log("Failed to refuel: no fuel in inventory!")
                    return 1
                end
            else
                log("Too low on fuel!")
                return 1
            end
        end
    end
    return 0
end

main()
