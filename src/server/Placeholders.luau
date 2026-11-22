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
local Theme = require(Shared.Theme)
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

local function text(parent: Instance, props: { [string]: any }): TextLabel
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.TextScaled = true
    for key, value in props do
        (label :: any)[key] = value
    end
    label.Parent = parent
    return label
end

-- A weathered plank sign floating in the dark: painted title, stamped line underneath (Shared/Theme).
local function sign(model: Instance, at: CFrame, title: string, subtitle: string, titleColor: Color3?)
    local anchor = World.part(model, "Sign", Vector3.new(1, 1, 1), at, Color3.new(), Enum.Material.SmoothPlastic)
    anchor.Transparency = 1
    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromScale(18, 6) -- studs, so it shrinks with distance (TRAPS #15)
    gui.LightInfluence = 0
    gui.Parent = anchor
    local board = Instance.new("Frame")
    board.Size = UDim2.fromScale(1, 1)
    board.BackgroundColor3 = Color3.new(1, 1, 1)
    board.Parent = gui
    local grain = Instance.new("UIGradient")
    grain.Color = Theme.grain(Theme.Color.WoodLight, Theme.Color.WoodDark)
    grain.Rotation = 90
    grain.Parent = board
    local edge = Instance.new("UIStroke")
    edge.Color = Theme.Color.Iron
    edge.Thickness = 3
    edge.Parent = board
    text(board, {
        Size = UDim2.fromScale(0.9, 0.55),
        Position = UDim2.fromScale(0.05, 0.08),
        FontFace = Theme.Font.Sign,
        TextColor3 = titleColor or Theme.Color.Paper,
        Text = title,
    })
    text(board, {
        Size = UDim2.fromScale(0.9, 0.28),
        Position = UDim2.fromScale(0.05, 0.64),
        FontFace = Theme.Font.Stamp,
        TextColor3 = Theme.Color.PaperDark,
        Text = subtitle,
    })
end

-- A warning sign before each gap whose sign falls between `from` and `to` along the track (so each chunk
-- carries its own signs), with the speed it takes to jump it.
function Placeholders.gapSigns(parent: Instance, layout: Layout.Layout, from: number, to: number)
    local cart = Configs.Run.Cart
    for _, gap in layout.track.gaps do
        local signAt = math.max(0, gap.from - 70)
        if signAt >= from and signAt < to then
            local need = math.ceil(Jump.minSpeed(cart.Jump, gap))
            local cruise = cart.Speed * (1 + cart.SlopeBoost * gap.grade)
            local advice = if need > cruise
                then "NEED " .. need .. " — PUSH!"
                else "NEED " .. need .. " — DON'T BRAKE"
            local at = TrackFrames.flat(layout.track, signAt)
            sign(parent, at * CFrame.new(0, 10, 0), "GAP AHEAD", advice, Theme.Color.Danger)
        end
    end
end

-- The segment's number on a board at its entrance, like a door number: on a timber post to the right of
-- the rails, facing the oncoming cart.
function Placeholders.plate(parent: Instance, frame: CFrame, number: number)
    local timber = Theme.Color.Wood
    local floorTop = trackConfig.FloorTop
    World.part(
        parent,
        "PlatePost",
        Vector3.new(0.6, 9, 0.6),
        frame * CFrame.new(7.5, floorTop + 4.5, -1),
        timber,
        Enum.Material.Wood
    )
    local board = World.part(
        parent,
        "Plate",
        Vector3.new(3.4, 2, 0.3),
        frame * CFrame.new(7.5, floorTop + 8, -0.7),
        Theme.Color.WoodDark,
        Enum.Material.Wood
    )
    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Back -- toward the oncoming cart
    gui.LightInfluence = 0
    gui.Brightness = 1.4
    gui.PixelsPerStud = 60
    gui.Parent = board
    local rim = Instance.new("Frame")
    rim.Size = UDim2.fromScale(1, 1)
    rim.BackgroundColor3 = Theme.Color.WoodDark
    rim.Parent = gui
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Color.Brass
    stroke.Thickness = 6
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = rim
    text(rim, {
        Size = UDim2.fromScale(0.86, 0.8),
        Position = UDim2.fromScale(0.07, 0.1),
        FontFace = Theme.Font.Number,
        TextColor3 = Theme.Color.Brass,
        Text = string.format("%02d", number),
    })
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
