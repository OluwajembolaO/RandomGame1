--!strict
-- Lays the rails along the exact track the cart follows: rails and sleepers everywhere, gravel ballast
-- except across caverns, where the Blender kit's timber trestle carries the track instead.
-- Everything else around the track (shoring, trestles, lanterns) comes with the kit pieces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local TrackFrames = require(Shared.TrackFrames)

local trackConfig = Configs.Run.Track

local TrackDresser = {}

local function onTrestle(spans: { Layout.Placement }, distance: number): boolean
    for _, span in spans do
        if distance >= span.from and distance <= span.to then
            return true
        end
    end
    return false
end

-- Lays every rail, sleeper and bit of ballast for the run.
function TrackDresser.dress(layout: Layout.Layout, zone: any, parent: Instance)
    local folder = Instance.new("Folder")
    folder.Name = "Track"
    folder.Parent = parent

    local palette = zone.Palette
    local gauge = trackConfig.RailGauge
    local railColor = World.color(palette.Rail)
    local ballast = World.color(palette.RockDark)
    local timber = World.color(palette.Timber)
    local trestles = Layout.placementsOf(layout, Configs.Kit.Pieces, "Cavern")
    local points, distances = layout.track.points, layout.track.distances

    -- Straight runs of points share one rail part; a run never crosses onto or off a trestle.
    local i = 1
    while i < #points do
        local a = TrackFrames.vector(points[i])
        local direction = (TrackFrames.vector(points[i + 1]) - a).Unit
        local elevated = onTrestle(trestles, distances[i])
        local j = i + 1
        while
            j < #points
            and onTrestle(trestles, distances[j]) == elevated
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
        if not elevated then
            World.part(
                folder,
                "Ballast",
                Vector3.new(gauge + 4, 3, length + 0.5),
                frame * CFrame.new(0, -2, 0),
                ballast,
                Enum.Material.Slate
            )
        end
        i = j
    end

    local distance = 0
    while distance <= layout.track.length do
        World.part(
            folder,
            "Sleeper",
            Vector3.new(gauge + 2.4, 0.35, 1.2),
            TrackFrames.frame(layout.track, distance) * CFrame.new(0, -0.55, 0),
            timber,
            Enum.Material.Wood
        )
        distance += if onTrestle(trestles, distance) then 4 else 8
    end
end

return TrackDresser
