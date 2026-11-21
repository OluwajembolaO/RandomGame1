--!strict
-- Shared building helpers for one run's world, plus the zone's mood (fog, bloom, color grading).
-- KitBuilder places the cave and TrackDresser lays the track; everything lives under workspace.Run.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Layout = require(Shared.Rules.Layout)
local TrackFrames = require(Shared.TrackFrames)

local Terrain = workspace.Terrain

local World = {}

function World.color(rgb: { number }): Color3
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- An anchored part that only exists to be seen (no collisions, touches or raycasts).
function World.part(
    parent: Instance,
    name: string,
    size: Vector3,
    cframe: CFrame,
    color: Color3,
    material: Enum.Material
): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Size = size
    part.CFrame = cframe
    part.Color = color
    part.Material = material
    part.Parent = parent
    return part
end

function World.light(parent: Instance, range: number, brightness: number, color: Color3, shadows: boolean): PointLight
    local light = Instance.new("PointLight")
    light.Range = range
    light.Brightness = brightness
    light.Color = color
    light.Shadows = shadows
    light.Parent = parent
    return light
end

-- Marks a light as a flame; clients make it waver by `amount` (a fraction of its brightness).
function World.flicker(light: Light, amount: number)
    light:SetAttribute("Base", light.Brightness)
    light:SetAttribute("Flicker", amount)
    CollectionService:AddTag(light, "Flicker")
end

-- A small glowing lantern with a flickering light.
function World.lantern(parent: Instance, at: CFrame, palette: any, mood: any, range: number): Part
    local lamp = World.color(palette.Lamp)
    World.part(
        parent,
        "LanternCap",
        Vector3.new(1.1, 0.3, 1.1),
        at * CFrame.new(0, 0.75, 0),
        Color3.fromRGB(40, 36, 32),
        Enum.Material.Metal
    )
    local glass = World.part(parent, "Lantern", Vector3.new(0.8, 1.2, 0.8), at, lamp, Enum.Material.Neon)
    World.flicker(World.light(glass, range, 2.4, lamp, false), mood.Flicker)
    return glass
end

-- Clears the last run's cave and parts, and returns a fresh workspace.Run folder.
function World.reset(): Folder
    Terrain:Clear()
    local old = workspace:FindFirstChild("Run")
    if old then
        old:Destroy()
    end
    local folder = Instance.new("Folder")
    folder.Name = "Run"
    folder.Parent = workspace
    return folder
end

-- A station or stop chamber: rail height at its middle, facing along the track (it's flat and straight),
-- and its length.
function World.chamber(layout: Layout.Layout, segment: Layout.Segment): (CFrame, number)
    local a = TrackFrames.position(layout.track, segment.from)
    local b = TrackFrames.position(layout.track, segment.to)
    return CFrame.lookAt((a + b) / 2, b), (b - a).Magnitude
end

local function effect(className: string, name: string): Instance
    local existing = Lighting:FindFirstChild(name)
    if existing and existing.ClassName == className then
        return existing
    end
    if existing then
        existing:Destroy()
    end
    local created = Instance.new(className)
    created.Name = name
    created.Parent = Lighting
    return created
end

-- The zone's lighting mood: ambient light, fog that swallows the distance, bloom on the flames, and a
-- color grade. Lighting.Technology (Future) is set in default.project.json; scripts can't (TRAPS #12).
function World.mood(zone: any)
    local mood = zone.Mood
    Lighting.Ambient = World.color(mood.Ambient)
    Lighting.ExposureCompensation = mood.Exposure or 0

    local atmosphere = effect("Atmosphere", "CaveAtmosphere") :: Atmosphere
    atmosphere.Density = mood.Atmosphere.Density
    atmosphere.Offset = mood.Atmosphere.Offset
    atmosphere.Color = World.color(mood.Atmosphere.Color)
    atmosphere.Decay = World.color(mood.Atmosphere.Decay)
    atmosphere.Glare = 0
    atmosphere.Haze = mood.Atmosphere.Haze

    local bloom = effect("BloomEffect", "CaveBloom") :: BloomEffect
    bloom.Intensity = mood.Bloom.Intensity
    bloom.Size = mood.Bloom.Size
    bloom.Threshold = mood.Bloom.Threshold

    local grade = effect("ColorCorrectionEffect", "CaveGrade") :: ColorCorrectionEffect
    grade.Brightness = mood.Grade.Brightness
    grade.Contrast = mood.Grade.Contrast
    grade.Saturation = mood.Grade.Saturation
    grade.TintColor = World.color(mood.Grade.Tint)
end

return World
