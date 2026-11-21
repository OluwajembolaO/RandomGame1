--!strict
-- What the game adds to the kit's station and stop chamber until each stop's own content is built: an
-- invisible walkable floor matching the kit's floor (Run.Track.FloorTop and Floors), the start lever, a sign
-- and spawn points. The kit pieces bring the look and the lanterns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Jump = require(Shared.Rules.Jump)
local Layout = require(Shared.Rules.Layout)
local TrackFrames = require(Shared.TrackFrames)

local trackConfig = Configs.Run.Track

local Placeholders = {}

export type Station = { model: Model, spawn: CFrame, lever: ProximityPrompt }
export type Arena = { model: Model, spawn: CFrame }

-- `floor` is rail height at the middle of the room, facing along the track; floors sit FloorTop below it.
local function walkable(model: Model, floor: CFrame, length: number, kind: string)
    local spec = trackConfig.Floors[kind]
    local slab = World.part(
        model,
        "Floor",
        Vector3.new(spec.Width, 1, length - 8),
        floor * CFrame.new(spec.Offset, trackConfig.FloorTop - 0.5, 0),
        Color3.new(),
        Enum.Material.SmoothPlastic
    )
    slab.Transparency = 1
    slab.CanCollide = true
    slab.CanQuery = true
end

local function standing(floor: CFrame, x: number, z: number): CFrame
    return floor * CFrame.new(x, trackConfig.FloorTop + 3, z)
end

local function sign(model: Model, at: CFrame, title: string, subtitle: string)
    local anchor = World.part(model, "Sign", Vector3.new(1, 1, 1), at, Color3.new(), Enum.Material.SmoothPlastic)
    anchor.Transparency = 1
    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromScale(18, 5) -- studs, so it shrinks with distance (TRAPS #15)
    gui.LightInfluence = 0
    gui.Parent = anchor
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 0.65)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 214, 150)
    label.Text = title
    label.Parent = gui
    local small = Instance.new("TextLabel")
    small.Position = UDim2.fromScale(0, 0.65)
    small.Size = UDim2.fromScale(1, 0.35)
    small.BackgroundTransparency = 1
    small.Font = Enum.Font.GothamMedium
    small.TextScaled = true
    small.TextColor3 = Color3.fromRGB(220, 210, 200)
    small.Text = subtitle
    small.Parent = gui
end

-- A warning sign before every gap in the track, with the speed it takes to jump it.
function Placeholders.gapSigns(parent: Instance, layout: Layout.Layout)
    local model = Instance.new("Model")
    model.Name = "GapSigns"
    model.Parent = parent
    local cart = Configs.Run.Cart
    for _, gap in layout.track.gaps do
        local need = math.ceil(Jump.minSpeed(cart.Jump, gap))
        local cruise = cart.Speed * (1 + cart.SlopeBoost * gap.grade)
        local advice = if need > cruise then "NEED " .. need .. " — PUSH!" else "NEED " .. need .. " — DON'T BRAKE"
        local at = TrackFrames.flat(layout.track, math.max(0, gap.from - 70))
        sign(model, at * CFrame.new(0, 10, 0), "GAP AHEAD", advice)
    end
end

-- The station: a floor around the parked cart and the lever that starts the run.
function Placeholders.station(parent: Instance, floor: CFrame, length: number, palette: any): Station
    local model = Instance.new("Model")
    model.Name = "Station"
    walkable(model, floor, length, "Station")

    local base = trackConfig.FloorTop
    local post = World.part(
        model,
        "LeverPost",
        Vector3.new(1, 4, 1),
        floor * CFrame.new(7, base + 2, -2),
        World.color(palette.Timber),
        Enum.Material.Wood
    )
    post.CanQuery = true
    local handle = World.part(
        model,
        "LeverHandle",
        Vector3.new(0.4, 2.5, 0.4),
        floor * CFrame.new(7, base + 4.6, -2) * CFrame.Angles(0, 0, math.rad(25)),
        Color3.fromRGB(190, 40, 40),
        Enum.Material.Metal
    )
    handle.CanQuery = true
    local lever = Instance.new("ProximityPrompt")
    lever.ActionText = "Start the descent"
    lever.ObjectText = "Lever"
    lever.HoldDuration = 0.5
    lever.MaxActivationDistance = 12
    lever.RequiresLineOfSight = false
    lever.Parent = post

    sign(model, floor * CFrame.new(10, 18, -length / 2 + 8), "LAST CART DOWN", "Pull the lever when the crew is ready")
    model.Parent = parent
    return { model = model, spawn = standing(floor, 14, 6), lever = lever }
end

-- A stop that hasn't been built yet: the chamber's floor and the stage's name on a sign.
function Placeholders.arena(parent: Instance, floor: CFrame, length: number, stageId: string): Arena
    local stage = Configs.Stages[stageId]
    local model = Instance.new("Model")
    model.Name = stageId
    walkable(model, floor, length, "Stop")
    sign(model, floor * CFrame.new(8, 20, 0), stage.Name, stage.Genre .. " stage (placeholder)")
    model.Parent = parent
    return { model = model, spawn = standing(floor, 14, 0) }
end

return Placeholders
