--!strict
-- Runs the game, one run at a time per server: builds the cave, waits at the station, rides each leg,
-- runs each stop, and ends in victory or a wipe. Every phase change is checked against Rules/RunState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartService = require(script.Parent.CartService)
local KitBuilder = require(script.Parent.KitBuilder)
local Placeholders = require(script.Parent.Placeholders)
local Rescue = require(script.Parent.Rescue)
local Survivors = require(script.Parent.Survivors)
local Weapons = require(script.Parent.Weapons)
local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Cart = require(Shared.Rules.Cart)
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local Route = require(Shared.Rules.Route)
local Remotes = require(Shared.Remotes)
local RunInfo = require(Shared.RunInfo)
local RunState = require(Shared.Rules.RunState)
local Upgrades = require(Shared.Rules.Upgrades)

local run = Configs.Run

local Director = {}

local phase: string? = nil
local building = false

local function setPhase(nextPhase: string)
    if phase ~= nil and not RunState.canMove(phase, nextPhase) then
        error("bad phase change " .. phase .. " -> " .. nextPhase)
    end
    phase = nextPhase
    RunInfo.set("Phase", nextPhase)
end

function Director.phase(): string?
    return phase
end

local function message(text: string)
    RunInfo.set("Message", text)
end

local function countdown(seconds: number, label: string)
    message(label)
    for left = seconds, 1, -1 do
        RunInfo.set("Countdown", left)
        task.wait(1)
    end
    RunInfo.set("Countdown", 0)
    message("")
end

local function rollSeed(): number
    return if run.Seed ~= 0 then run.Seed else Random.new():NextInteger(1, 2147483646)
end

local function waitForLever(lever: ProximityPrompt)
    local pulled = false
    local connection = lever.Triggered:Connect(function()
        pulled = true
    end)
    while not pulled do
        task.wait(0.2)
    end
    connection:Disconnect()
    lever.Enabled = false
    local post = lever.Parent
    if post and post:IsA("BasePart") then
        Remotes.Effect:FireAllClients("Sound", "Lever", post.Position)
    end
end

local function besideCart(): CFrame
    return CartService.frame() * CFrame.new(8, 4, 0)
end

local function boardAll()
    Survivors.respawnDead(besideCart())
    for _, player in Survivors.crew() do
        CartService.seat(player)
    end
end

local function finish(nextPhase: string, text: string)
    CartService.setLocked(false)
    CartService.halt()
    setPhase(nextPhase)
    message(text)
    task.wait(run.EndScreenSeconds)
    message("")
end

local function runOnce()
    building = true
    local folder = World.reset()
    local zone = Configs.Zones[1]
    local seed = rollSeed()
    local route = Route.generate(zone, seed)
    local ok, problem = Route.validate(route, Configs.Stages)
    assert(ok, "bad route: " .. tostring(problem))
    local layout = Layout.build(route, zone.Kit, Configs.Kit.Pieces, Layout.spec(run))

    RunInfo.set("Seed", seed) -- clients lay the same route out from it (the HUD's depth meter)
    RunInfo.set("Segments", layout.count)
    RunInfo.set("Segment", 0)
    RunInfo.set("Difficulty", route.legs[1].difficulty)
    RunInfo.set("Zone", zone.Name)
    RunInfo.set("Legs", #route.legs)
    RunInfo.set("Leg", 0)
    RunInfo.set("Stop", "")
    RunInfo.set("StopGenre", "")
    World.mood(zone)
    message("Digging out the mine...")
    -- The cave is built a few segments at a time around the cart as it rides, like DOORS rooms. Until this
    -- run's cart exists, around the station.
    local cartReady = false
    KitBuilder.stream(layout, zone, folder, layout.parked, function(): number
        return if cartReady then CartService.distance() else layout.parked
    end)
    local stationFloor, stationLength = World.chamber(layout, layout.segments[1])
    local station = Placeholders.station(folder, stationFloor, stationLength, zone.Palette)
    Survivors.setSpawn(station.spawn)

    local owned: Upgrades.Owned = {}
    local stats = Upgrades.apply(Upgrades.baseStats(Configs), Configs.Upgrades, owned)
    Weapons.setStats(stats)
    CartService.spawn(folder, layout.track, layout.parked, zone.Palette, Cart.stats(run.Cart, stats))
    cartReady = true
    for _, player in Players:GetPlayers() do
        Survivors.spawn(player)
    end
    building = false
    setPhase("Station")
    message("")

    waitForLever(station.lever)
    countdown(run.StartCountdown, "Get in the cart!")

    for _, leg in route.legs do
        boardAll()
        CartService.setLocked(true)
        setPhase("Riding")
        RunInfo.set("Leg", leg.index)
        RunInfo.set("Difficulty", leg.difficulty)
        RunInfo.set("Stop", "")
        RunInfo.set("StopGenre", "")
        CartService.rideTo(layout.stops[leg.index])
        if not CartService.waitForArrival() then
            finish("Wipe", "The cart was wrecked")
            return
        end
        CartService.setLocked(false)
        setPhase("AtStop")

        -- The fork vote arrives with Votes; until then, take the first branch.
        local options = leg.stop.options
        local stageId = leg.stop.stage or (options and options[1]) or "SupplyDepot"
        local stage = Configs.Stages[stageId]
        local slot = Layout.slot(layout, leg.index)
        assert(slot, "no slot for leg " .. leg.index)
        local floor, length = World.chamber(layout, slot)
        local arena = Placeholders.arena(folder, floor, length, stageId)
        RunInfo.set("Stop", stage.Name)
        RunInfo.set("StopGenre", stage.Genre)
        CartService.unseatAll()
        task.wait()
        Survivors.respawnDead(arena.spawn)
        for _, player in Survivors.crew() do
            Survivors.teleport(player, arena.spawn)
        end

        -- Stages arrive in step 5; for the cart spike each stop is a short pause.
        message(stage.Blurb)
        task.wait(8)

        if stage.Kind == "Boss" then
            finish("Victory", "You made it through " .. zone.Name)
            return
        end
        countdown(run.AllAboardSeconds, "All aboard!")
    end
end

function Director.start()
    CartService.setCrewSource(Survivors.crew)
    -- Anyone who falls out of the cave is put back on the track just behind the cart.
    Rescue.start(function(): CFrame?
        return if CartService.model() then CartService.frame() * CFrame.new(0, 3, 9) else nil
    end)
    Weapons.setIgnore(function(): { Instance }
        local cart = CartService.model()
        return if cart then { cart } else {}
    end)

    Players.PlayerAdded:Connect(function(player)
        if building or phase == nil then
            return -- everyone is spawned once the cave is built
        end
        if phase == "Station" then
            Survivors.spawn(player)
        else
            Survivors.spawn(player, besideCart())
            if phase == "Riding" then
                CartService.seat(player)
            end
        end
    end)

    task.spawn(function()
        while true do
            local ok, err = pcall(function(): any
                runOnce()
                return nil
            end)
            if not ok then
                warn("[Director] run failed: " .. tostring(err))
                phase = nil
                task.wait(3)
            end
        end
    end)
end

return Director
