--!strict
-- Builds the cave from the Blender kit (art/blender/build_cave_kit.py), one chunk per segment, only around
-- the cart (KitBuilder.stream). Each placed chunk is cloned from ServerStorage.Content.Kit and pivoted onto
-- its spot on the track; then the spores, mist and light-shaft beams listed for it in Config/KitData, its
-- rails and its number plate are added. The kit's lights are made by each client for the chunks that exist
-- (client/CaveLights): lights the server made rendered nothing on clients (TRAPS #42).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Placeholders = require(script.Parent.Placeholders)
local TrackDresser = require(script.Parent.TrackDresser)
local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local RunInfo = require(Shared.RunInfo)
local TrackFrames = require(Shared.TrackFrames)

local KitBuilder = {}

local AHEAD = 700 -- studs of cave built in front of the cart: ~12 s at a pushed run
local BEHIND = 180 -- studs kept behind it
local CHUNKS_PER_STEP = 2 -- most chunks built in one go, so building never hitches the server
local STREAM_EVERY = 0.2

local function vector(list: { number }): Vector3
    return Vector3.new(list[1], list[2], list[3])
end

-- The frame a piece is modeled in: its track's start, facing along the track (LookVector), upright.
function KitBuilder.frame(placement: Layout.Placement): CFrame
    return TrackFrames.piece(placement.position, placement.heading)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
    local particles = Instance.new("ParticleEmitter")
    for key, value in props do
        (particles :: any)[key] = value
    end
    particles.Parent = parent
    return particles
end

local function volume(parent: Instance, name: string, cframe: CFrame, size: Vector3): Part
    local part = World.part(parent, name, size, cframe, Color3.new(), Enum.Material.SmoothPlastic)
    part.Transparency = 1
    return part
end

local function spores(parent: Instance, cframe: CFrame, size: Vector3, colors: { Color3 })
    local box = volume(parent, "Spores", cframe, size)
    for _, color in colors do
        emitter(box, {
            Shape = Enum.ParticleEmitterShape.Box,
            ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
            Texture = "rbxasset://textures/particles/sparkles_main.dds",
            Color = ColorSequence.new(color),
            LightEmission = 1,
            LightInfluence = 0,
            Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.3) }),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.25, 0.2),
                NumberSequenceKeypoint.new(0.75, 0.3),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Lifetime = NumberRange.new(8, 14),
            Rate = math.clamp(size.X * size.Z / 900, 4, 16) / #colors,
            Speed = NumberRange.new(0.3, 1.2),
            SpreadAngle = Vector2.new(180, 180),
            Acceleration = Vector3.new(0, 0.12, 0),
            RotSpeed = NumberRange.new(-40, 40),
        })
    end
end

local function mist(parent: Instance, cframe: CFrame, size: Vector3, color: Color3)
    local box = volume(parent, "Mist", cframe, size)
    emitter(box, {
        Shape = Enum.ParticleEmitterShape.Box,
        ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
        Texture = "rbxasset://textures/particles/smoke_main.dds",
        Color = ColorSequence.new(color),
        LightEmission = 0.15,
        LightInfluence = 0.85,
        Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(1, 26) }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.4, 0.8),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Lifetime = NumberRange.new(14, 20),
        Rate = 3,
        Speed = NumberRange.new(0.4, 1.0),
        SpreadAngle = Vector2.new(180, 8),
        Rotation = NumberRange.new(0, 360),
        RotSpeed = NumberRange.new(-5, 5),
    })
end

local function shaft(parent: Instance, top: Vector3, bottom: Vector3, color: Color3, opacity: number)
    -- The glowing crack and the beams; the shaft's spotlight is made by clients (client/CaveLights).
    local anchor =
        World.part(parent, "ShaftTop", Vector3.new(2.5, 0.6, 2.5), CFrame.new(top), color, Enum.Material.Neon)
    anchor.Transparency = 0.3
    local foot = volume(parent, "ShaftFoot", CFrame.new(bottom), Vector3.one)
    local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
    a0.Parent, a1.Parent = anchor, foot
    -- Three soft overlapping beams read as one shaft of light with a hazy edge.
    for _, layer in { { 6, 14, 0.82 }, { 14, 26, 0.9 }, { 24, 40, 0.95 } } do
        local beam = Instance.new("Beam")
        beam.Attachment0, beam.Attachment1 = a0, a1
        beam.Width0, beam.Width1 = layer[1], layer[2]
        beam.FaceCamera = true
        beam.LightEmission = 1
        beam.LightInfluence = 0
        beam.Color = ColorSequence.new(color)
        -- Fade each layer further toward invisible by the zone's ShaftOpacity.
        local base = 1 - (1 - layer[3]) * opacity
        beam.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, base),
            NumberSequenceKeypoint.new(0.7, base + (1 - base) * 0.4),
            NumberSequenceKeypoint.new(1, 1),
        })
        beam.Parent = anchor
    end
    local height = (top - bottom).Magnitude
    local dust = volume(parent, "ShaftDust", CFrame.new((top + bottom) / 2), Vector3.new(14, height * 0.8, 14))
    emitter(dust, {
        Shape = Enum.ParticleEmitterShape.Box,
        ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
        Texture = "rbxasset://textures/particles/sparkles_main.dds",
        Color = ColorSequence.new(color),
        LightEmission = 1,
        LightInfluence = 0,
        Size = NumberSequence.new(0.18),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.3, 0.35),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Lifetime = NumberRange.new(6, 10),
        Rate = 10,
        Speed = NumberRange.new(0.2, 0.6),
        SpreadAngle = Vector2.new(180, 180),
        Acceleration = Vector3.new(0, -0.05, 0),
    })
end

local warned = false

-- Builds one placed chunk complete: its kit mesh, spores, mist and light shafts, its rails, any gap signs,
-- and its segment number plate. The model's pivot is the chunk's frame and it carries the chunk's Piece,
-- Index and Number as attributes, which is all a client needs to light it (client/CaveLights).
function KitBuilder.chunk(layout: Layout.Layout, index: number, zone: any, folder: Instance): Model
    local placement = layout.placements[index]
    local def = Configs.Kit.Pieces[placement.piece]
    local frame = KitBuilder.frame(placement)
    local palette = zone.Palette
    local model = Instance.new("Model")
    model.Name = if placement.number > 0
        then string.format("%02d_%s", placement.number, placement.piece)
        else placement.piece
    model:SetAttribute("Piece", placement.piece)
    model:SetAttribute("Index", index)
    model:SetAttribute("Number", placement.number)

    local content = ServerStorage:FindFirstChild("Content")
    local kit = content and content:FindFirstChild("Kit")
    local template = kit and kit:FindFirstChild(placement.piece)
    if template and template:IsA("Model") then
        local copy = template:Clone()
        copy:PivotTo(frame)
        copy.Parent = model
    elseif not warned then
        warned = true
        warn("[KitBuilder] ServerStorage.Content.Kit." .. placement.piece .. " is missing; the cave has no walls")
    end

    for _, entry in def.Emitters do
        local at = frame * CFrame.new(vector(entry.Center))
        if entry.Kind == "Spores" then
            local colors = {}
            for _, name in entry.Colors or { "Lamp" } do
                table.insert(colors, World.color(palette[name] or palette.Lamp))
            end
            spores(model, at, vector(entry.Size), colors)
        elseif entry.Kind == "Mist" then
            mist(model, at, vector(entry.Size), World.color(palette.Mist))
        end
    end

    for _, entry in def.Shafts do
        shaft(
            model,
            frame:PointToWorldSpace(vector(entry.Top)),
            frame:PointToWorldSpace(vector(entry.Bottom)),
            World.color(palette.Shaft),
            zone.Mood.ShaftOpacity or 1
        )
    end

    TrackDresser.dress(layout, placement, zone, model)
    Placeholders.gapSigns(model, layout, placement.from, placement.to)
    if placement.number > 0 then
        Placeholders.plate(model, frame, placement.number)
    end

    model.WorldPivot = frame
    model.Parent = folder
    return model
end

-- Keeps the cave built around the cart, the way DOORS builds rooms as you reach them: every chunk within
-- AHEAD studs in front of `focus()` (the cart) and BEHIND studs behind it exists; the rest don't. It also
-- shares which numbered segment the cart is on (RunInfo.Segment). The first fill (around `start`) happens
-- before this returns, so the station is there for the crew to spawn into; after that it runs until the
-- run's folder is cleared (World.reset).
function KitBuilder.stream(layout: Layout.Layout, zone: any, parent: Instance, start: number, focus: () -> number)
    local folder = Instance.new("Folder")
    folder.Name = "Cave"
    folder.Parent = parent
    local built: { [number]: Model } = {}

    -- Builds up to `limit` missing chunks around `at` (nearest first) and clears the ones out of range.
    -- Returns how many it built.
    local function update(at: number, limit: number): number
        local low, high = at - BEHIND, at + AHEAD
        for index, model in built do
            local placement = layout.placements[index]
            if placement.to < low or placement.from > high then
                model:Destroy()
                built[index] = nil
            end
        end
        local wanted = {}
        for index = Layout.placementAt(layout, math.max(0, low)), #layout.placements do
            local placement = layout.placements[index]
            if placement.from > high then
                break
            end
            if not built[index] and placement.to >= low then
                table.insert(wanted, index)
            end
        end
        table.sort(wanted, function(a, b)
            local pa, pb = layout.placements[a], layout.placements[b]
            return math.abs((pa.from + pa.to) / 2 - at) < math.abs((pb.from + pb.to) / 2 - at)
        end)
        local made = 0
        for _, index in wanted do
            if made >= limit then
                break
            end
            built[index] = KitBuilder.chunk(layout, index, zone, folder)
            made += 1
        end
        return made
    end

    while update(start, CHUNKS_PER_STEP) > 0 do
        task.wait()
    end
    task.spawn(function()
        while folder.Parent do
            local at = focus()
            update(at, CHUNKS_PER_STEP)
            RunInfo.set("Segment", Layout.numberAt(layout, at))
            task.wait(STREAM_EVERY)
        end
    end)
end

return KitBuilder
