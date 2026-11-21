--!strict
-- The cave for one run. Carves terrain for the station, the tunnels and each stop's chamber, then lays
-- rails, ballast, timber supports and lanterns along the track. Everything else lives under workspace.Run.
-- Terrain is filled for every piece first and carved second, so a neighbour never refills a space
-- that was already dug out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local TrackFrames = require(Shared.TrackFrames)

local Terrain = workspace.Terrain
local trackConfig = Configs.Run.Track
local ROCK = Enum.Material.Slate
local TERRAIN_BATCH = 24 -- terrain writes per frame, so building doesn't stall the server
local CARVE_SPACING = 8

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

-- A station or slot chamber: its floor CFrame (rail height at the middle, facing along the track and
-- tilted with it) and its size.
function World.chamber(layout: Layout.Layout, segment: Layout.Segment): (CFrame, Vector3)
    local a = TrackFrames.position(layout.track, segment.from)
    local b = TrackFrames.position(layout.track, segment.to)
    local floor = CFrame.lookAt((a + b) / 2, b)
    return floor, Vector3.new(trackConfig.ChamberWidth, trackConfig.ChamberHeight, (b - a).Magnitude + 16)
end

local function runBatched(jobs: { () -> () })
    for index, job in jobs do
        job()
        if index % TERRAIN_BATCH == 0 then
            task.wait()
        end
    end
end

-- Digs the whole route out of solid rock. Yields while it works.
function World.carve(layout: Layout.Layout, palette: any)
    Terrain:SetMaterialColor(ROCK, World.color(palette.Rock))
    local radius = trackConfig.TunnelRadius
    -- The tube's center sits above the rails so its floor lands just under the ballast.
    local lift = Vector3.new(0, radius - 3, 0)
    local fills: { () -> () } = {}
    local carves: { () -> () } = {}
    for _, segment in layout.segments do
        if segment.kind == "Leg" then
            local distance = segment.from
            while distance <= segment.to do
                local center = TrackFrames.position(layout.track, distance) + lift
                table.insert(fills, function()
                    Terrain:FillBall(center, radius + 6, ROCK)
                end)
                table.insert(carves, function()
                    Terrain:FillBall(center, radius, Enum.Material.Air)
                end)
                distance += CARVE_SPACING
            end
        else
            local floor, size = World.chamber(layout, segment)
            local middle = floor * CFrame.new(0, size.Y / 2 - 3, 0)
            table.insert(fills, function()
                Terrain:FillBlock(middle, size + Vector3.new(14, 14, 14), ROCK)
            end)
            table.insert(carves, function()
                Terrain:FillBlock(middle, size, Enum.Material.Air)
            end)
        end
    end
    runBatched(fills)
    runBatched(carves)
end

-- Rails, ballast and sleepers along the whole track; timber supports with lanterns along the legs.
function World.dress(layout: Layout.Layout, palette: any, parent: Instance)
    local folder = Instance.new("Folder")
    folder.Name = "Track"
    folder.Parent = parent

    local gauge = trackConfig.RailGauge
    local railColor = World.color(palette.Rail)
    local ballastColor = World.color(palette.RockDark)
    local timber = World.color(palette.Timber)
    local lamp = World.color(palette.Lamp)
    local track = layout.track
    local points = track.points

    -- Straight runs of points share one rail part each.
    local i = 1
    while i < #points do
        local a = TrackFrames.vector(points[i])
        local direction = (TrackFrames.vector(points[i + 1]) - a).Unit
        local j = i + 1
        while
            j < #points
            and (TrackFrames.vector(points[j + 1]) - TrackFrames.vector(points[j])).Unit:Dot(direction) > 0.99995
        do
            j += 1
        end
        local b = TrackFrames.vector(points[j])
        local length = (b - a).Magnitude
        local frame = CFrame.lookAt((a + b) / 2, b)
        for _, side in { -1, 1 } do
            World.part(
                folder,
                "Rail",
                Vector3.new(0.35, 0.4, length + 0.25),
                frame * CFrame.new(side * gauge / 2, -0.2, 0),
                railColor,
                Enum.Material.Metal
            )
        end
        World.part(
            folder,
            "Ballast",
            Vector3.new(gauge + 4, 3, length + 0.5),
            frame * CFrame.new(0, -2, 0),
            ballastColor,
            Enum.Material.Slate
        )
        i = j
    end

    local distance = 0
    while distance <= track.length do
        World.part(
            folder,
            "Sleeper",
            Vector3.new(gauge + 2, 0.35, 1.2),
            TrackFrames.frame(track, distance) * CFrame.new(0, -0.55, 0),
            timber,
            Enum.Material.Wood
        )
        distance += 8
    end

    for _, segment in layout.segments do
        if segment.kind == "Leg" then
            local at = segment.from + trackConfig.SupportEvery / 2
            while at < segment.to do
                local frame = TrackFrames.flat(track, at)
                local half = gauge / 2 + 4.5
                for _, side in { -1, 1 } do
                    World.part(
                        folder,
                        "Post",
                        Vector3.new(1, 12, 1),
                        frame * CFrame.new(side * half, 5.5, 0),
                        timber,
                        Enum.Material.Wood
                    )
                end
                World.part(
                    folder,
                    "Beam",
                    Vector3.new(half * 2 + 1, 1, 1),
                    frame * CFrame.new(0, 11.5, 0),
                    timber,
                    Enum.Material.Wood
                )
                local lantern = World.part(
                    folder,
                    "Lantern",
                    Vector3.new(0.8, 1.2, 0.8),
                    frame * CFrame.new(half - 1.5, 10.4, 0),
                    lamp,
                    Enum.Material.Neon
                )
                World.light(lantern, 22, 1.4, lamp, false)
                at += trackConfig.SupportEvery
            end
        end
    end
end

return World
