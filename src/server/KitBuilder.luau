--!strict
-- Builds the cave from the Blender kit (art/blender/build_cave_kit.py). Each placed piece is cloned from
-- ServerStorage.Content.Kit and pivoted onto its spot on the track; then the spores, mist and light-shaft
-- beams listed for it in Config/KitData are added. The kit's lights are made by each client
-- (client/CaveLights): lights the server made rendered nothing on clients (TRAPS #42).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local TrackFrames = require(Shared.TrackFrames)

local KitBuilder = {}

local PIECES_PER_FRAME = 3

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

local function piece(folder: Instance, placement: Layout.Placement, zone: any)
    local def = Configs.Kit.Pieces[placement.piece]
    local frame = KitBuilder.frame(placement)
    local palette = zone.Palette
    local model = Instance.new("Model")
    model.Name = placement.piece

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

    model.Parent = folder
end

-- Builds every piece of the run's cave. Yields while it works.
function KitBuilder.build(layout: Layout.Layout, zone: any, parent: Instance)
    local folder = Instance.new("Folder")
    folder.Name = "Cave"
    folder.Parent = parent
    for index, placement in layout.placements do
        piece(folder, placement, zone)
        if index % PIECES_PER_FRAME == 0 then
            task.wait()
        end
    end
end

return KitBuilder
