--!strict
-- Lights the cave on this client. The server builds the cave's meshes and publishes the run's seed as
-- RunInfo.CaveSeed once they're in place; this lays the same route out from that seed (Rules/Layout is
-- deterministic, so it matches the server piece for piece) and makes every kit light locally, each on its
-- own small part. Every light starts switched off: Fx switches it on once the camera is near, because a
-- light that's on from the start, before the camera gets there, lit nothing (TRAPS #42).
-- Lights are tagged for Fx: "KitLight" (switched off when far), "Flicker" (lanterns) and "Pulse" (crystals).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local Route = require(Shared.Rules.Route)
local RunInfo = require(Shared.RunInfo)
local TrackFrames = require(Shared.TrackFrames)

local MAX_RANGE = 60 -- Roblox's cap
local PIECES_PER_FRAME = 4

local CaveLights = {}

local folder: Folder? = nil
local generation = 0

local function rgb(color: { number }): Color3
    return Color3.fromRGB(color[1], color[2], color[3])
end

local function vector(list: { number }): Vector3
    return Vector3.new(list[1], list[2], list[3])
end

local function holder(parent: Instance, at: Vector3, name: string): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Size = Vector3.new(0.2, 0.2, 0.2)
    part.CFrame = CFrame.new(at)
    part.Parent = parent
    return part
end

local function addLight(parent: Instance, at: Vector3, entry: any, zone: any)
    local scale = if entry.Color == "Lamp" then nil else zone.Mood.CrystalLight
    local point = Instance.new("PointLight")
    point.Range = math.min(MAX_RANGE, entry.Range * (if scale then scale.Range else 1))
    point.Brightness = entry.Brightness * (if scale then scale.Brightness else 1)
    point.Color = rgb(zone.Palette[entry.Color] or zone.Palette.Lamp)
    point.Shadows = false
    point.Enabled = false -- Fx turns it on once the camera is near (TRAPS #42)
    point:SetAttribute("Base", point.Brightness)
    point.Parent = holder(parent, at, "Light")
    CollectionService:AddTag(point, "KitLight")
    if entry.Flicker then
        point:SetAttribute("Flicker", zone.Mood.Flicker)
        CollectionService:AddTag(point, "Flicker")
    elseif entry.Pulse then
        point:SetAttribute("Pulse", zone.Mood.Pulse)
        CollectionService:AddTag(point, "Pulse")
    end
end

local function addShaft(parent: Instance, top: Vector3, zone: any)
    local spot = Instance.new("SpotLight")
    spot.Face = Enum.NormalId.Bottom
    spot.Range = MAX_RANGE
    spot.Angle = 40
    spot.Brightness = 2
    spot.Color = rgb(zone.Palette.Shaft)
    spot.Shadows = true
    spot.Enabled = false -- Fx turns it on once the camera is near (TRAPS #42)
    spot.Parent = holder(parent, top, "ShaftLight")
    CollectionService:AddTag(spot, "KitLight")
end

local function build(seed: number)
    generation += 1
    local mine = generation
    if folder then
        folder:Destroy()
        folder = nil
    end
    if seed == 0 then
        return -- the server is building a new cave; lights come when it publishes the seed
    end
    local zone = Configs.Zones[1]
    local layout = Layout.build(Route.generate(zone, seed), zone.Kit, Configs.Kit.Pieces, Layout.spec(Configs.Run))
    local container = Instance.new("Folder")
    container.Name = "CaveLights"
    container.Parent = workspace
    folder = container
    for index, placement in layout.placements do
        if mine ~= generation then
            return -- a newer cave replaced this one while it was being lit
        end
        local def = Configs.Kit.Pieces[placement.piece]
        local frame = TrackFrames.piece(placement.position, placement.heading)
        local group = Instance.new("Folder")
        group.Name = placement.piece
        for _, entry in def.Lights do
            addLight(group, frame:PointToWorldSpace(vector(entry.Position)), entry, zone)
        end
        for _, entry in def.Shafts do
            addShaft(group, frame:PointToWorldSpace(vector(entry.Top)), zone)
        end
        group.Parent = container
        if index % PIECES_PER_FRAME == 0 then
            task.wait()
        end
    end
end

function CaveLights.start()
    RunInfo.changed("CaveSeed", function(seed)
        task.spawn(build, if type(seed) == "number" then seed else 0)
    end)
    local current = RunInfo.get("CaveSeed")
    if type(current) == "number" and current ~= 0 then
        task.spawn(build, current)
    end
end

return CaveLights
