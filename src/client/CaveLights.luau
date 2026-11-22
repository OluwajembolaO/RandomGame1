--!strict
-- Lights the cave on this client. The server builds the cave a few chunks at a time around the cart
-- (server/KitBuilder.stream), each a model under workspace.Run.Cave pivoted at its chunk's frame and tagged
-- with its kit Piece. As each one arrives this makes its kit lights locally, each on its own small part,
-- and when the server removes it, its lights go too. Every light starts switched off: Fx switches it on
-- once the camera is near, because a light that's on from the start, before the camera gets there, lit
-- nothing (TRAPS #42).
-- Lights are tagged for Fx: "KitLight" (switched off when far), "Flicker" (lanterns) and "Pulse" (crystals).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)

local MAX_RANGE = 60 -- Roblox's cap

local CaveLights = {}

local folder: Folder? = nil
local lit: { [Instance]: Folder } = {} -- each lit chunk's lights

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

-- Lights one chunk the server just built: its kit lights and shaft spotlights, placed from Config/KitData
-- relative to the chunk's pivot.
local function lightChunk(chunk: Instance)
    local container = folder
    if not container or not chunk:IsA("Model") then
        return
    end
    local def = Configs.Kit.Pieces[chunk:GetAttribute("Piece") :: any]
    if not def then
        return
    end
    local zone = Configs.Zones[1]
    local frame = chunk:GetPivot()
    local group = Instance.new("Folder")
    group.Name = chunk.Name
    for _, entry in def.Lights do
        addLight(group, frame:PointToWorldSpace(vector(entry.Position)), entry, zone)
    end
    for _, entry in def.Shafts do
        addShaft(group, frame:PointToWorldSpace(vector(entry.Top)), zone)
    end
    group.Parent = container
    lit[chunk] = group
end

local function unlightChunk(chunk: Instance)
    local group = lit[chunk]
    if group then
        group:Destroy()
        lit[chunk] = nil
    end
end

-- Follows a run's Cave folder: lights each chunk as it arrives and puts its lights out when it goes.
local function watchCave(cave: Instance)
    for chunk in lit do
        unlightChunk(chunk)
    end
    for _, chunk in cave:GetChildren() do
        lightChunk(chunk)
    end
    cave.ChildAdded:Connect(lightChunk)
    cave.ChildRemoved:Connect(unlightChunk)
end

local function watchRun(run: Instance)
    local cave = run:FindFirstChild("Cave")
    if cave then
        watchCave(cave)
    end
    run.ChildAdded:Connect(function(child)
        if child.Name == "Cave" then
            watchCave(child)
        end
    end)
end

function CaveLights.start()
    local container = Instance.new("Folder")
    container.Name = "CaveLights"
    container.Parent = workspace
    folder = container
    local run = workspace:FindFirstChild("Run")
    if run then
        watchRun(run)
    end
    workspace.ChildAdded:Connect(function(child)
        if child.Name == "Run" then
            watchRun(child)
        end
    end)
end

return CaveLights
