--!strict
-- Lays the rails along the exact track the cart follows: rails and sleepers everywhere, gravel ballast
-- except across caverns, where the Blender kit's timber trestle carries the track instead. Nothing over a
-- gap (broken track the cart has to jump; Rules/Jump), just twisted rail ends and splintered sleepers at
-- each edge. Everything else around the track (shoring, trestles, lanterns) comes with the kit pieces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local Track = require(Shared.Rules.Track)
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

local function inGap(gaps: { Track.Gap }, distance: number): boolean
    for _, gap in gaps do
        if distance > gap.from + 0.01 and distance < gap.to - 0.01 then
            return true
        end
    end
    return false
end

-- Rail ends bent down into a gap and a splintered sleeper hanging off the edge. `facing` is -1 at the lip
-- (the rails stop going forward) and 1 at the far edge (they stop coming back).
local function brokenEdge(folder: Instance, frame: CFrame, facing: number, railColor: Color3, timber: Color3)
    local gauge = trackConfig.RailGauge
    for _, side in { -1, 1 } do
        local bend = math.rad(22 + side * 9)
        World.part(
            folder,
            "BrokenRail",
            Vector3.new(0.35, 0.4, 1.6),
            frame
                * CFrame.new(side * gauge / 2, -0.2, 0)
                * CFrame.Angles(-facing * bend, 0, 0)
                * CFrame.new(0, 0, facing * 0.8),
            railColor,
            Enum.Material.Metal
        )
    end
    World.part(
        folder,
        "Splinter",
        Vector3.new(gauge + 1.2, 0.3, 0.9),
        frame * CFrame.new(0.5, -0.9, facing * 0.6) * CFrame.Angles(-facing * 0.6, 0.25, 0.15),
        timber,
        Enum.Material.Wood
    )
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
    local gaps = layout.track.gaps
    local points, distances = layout.track.points, layout.track.distances
    local function brokenAt(index: number): boolean
        return inGap(gaps, (distances[index] + distances[index + 1]) / 2)
    end

    -- Straight runs of points share one rail part; a run never crosses onto or off a trestle or a gap.
    local i = 1
    while i < #points do
        local a = TrackFrames.vector(points[i])
        local direction = (TrackFrames.vector(points[i + 1]) - a).Unit
        local elevated = onTrestle(trestles, distances[i])
        local broken = brokenAt(i)
        local j = i + 1
        while
            j < #points
            and onTrestle(trestles, distances[j]) == elevated
            and brokenAt(j) == broken
            and (TrackFrames.vector(points[j + 1]) - TrackFrames.vector(points[j])).Unit:Dot(direction) > 0.99995
        do
            j += 1
        end
        local b = TrackFrames.vector(points[j])
        local length = (b - a).Magnitude
        local frame = CFrame.lookAt((a + b) / 2, b)
        for _, side in { -1, 1 } do
            if not broken then
                World.part(
                    folder,
                    "Rail",
                    Vector3.new(0.35, 0.4, length + 0.25),
                    frame * CFrame.new(side * gauge / 2, -0.2, 0),
                    railColor,
                    Enum.Material.Metal
                )
            end
        end
        if not elevated and not broken then
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
        if not inGap(gaps, distance) then
            World.part(
                folder,
                "Sleeper",
                Vector3.new(gauge + 2.4, 0.35, 1.2),
                TrackFrames.frame(layout.track, distance) * CFrame.new(0, -0.55, 0),
                timber,
                Enum.Material.Wood
            )
        end
        distance += if onTrestle(trestles, distance) then 4 else 8
    end

    for _, gap in gaps do
        brokenEdge(folder, TrackFrames.frame(layout.track, gap.from - 2), -1, railColor, timber)
        brokenEdge(folder, TrackFrames.frame(layout.track, gap.to + 2), 1, railColor, timber)
    end
end

return TrackDresser
