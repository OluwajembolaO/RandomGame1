--!strict
-- Lays the rails along the exact track the cart follows: rails and sleepers everywhere, gravel ballast
-- except across caverns, where the Blender kit's timber trestle carries the track instead. Nothing over a
-- gap (broken track the cart has to jump; Rules/Jump), just twisted rail ends and splintered sleepers at
-- each edge. Through a three-way split (Rules/Split), three lanes fan out: the dead two end at buffer stops,
-- and a signal board before the switch shows which lane is open (a green arrow) and which aren't (red
-- crosses). The kit's rock doesn't collide, so an invisible floor runs along the track too (everywhere but
-- over gaps), for anyone on foot. Everything else around the track (shoring, trestles, lanterns) comes with
-- the kit pieces.
-- Dressed one chunk at a time, as KitBuilder builds each segment ahead of the cart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local Split = require(Shared.Rules.Split)
local Theme = require(Shared.Theme)
local Track = require(Shared.Rules.Track)
local TrackFrames = require(Shared.TrackFrames)

local trackConfig = Configs.Run.Track

local TrackDresser = {}

local LANE_STEP = 4 -- studs between the points a split lane's rails are laid through
local ARROWS = { [-1] = "◀", [0] = "▲", [1] = "▶" }

type Colors = { rail: Color3, ballast: Color3, timber: Color3 }

-- Whether the main line has no rails at `distance`: over a gap, or through a split (its lanes have them).
local function offLine(gaps: { Track.Gap }, splits: { Track.SplitSpan }, distance: number): boolean
    for _, gap in gaps do
        if distance > gap.from + 0.01 and distance < gap.to - 0.01 then
            return true
        end
    end
    for _, split in splits do
        if distance > split.from + 0.01 and distance < split.to - 0.01 then
            return true
        end
    end
    return false
end

-- Rail ends bent down into a gap and a splintered sleeper hanging off the edge. `facing` is -1 at the lip
-- (the rails stop going forward) and 1 at the far edge (they stop coming back).
local function brokenEdge(folder: Instance, frame: CFrame, facing: number, colors: Colors)
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
            colors.rail,
            Enum.Material.Metal
        )
    end
    World.part(
        folder,
        "Splinter",
        Vector3.new(gauge + 1.2, 0.3, 0.9),
        frame * CFrame.new(0.5, -0.9, facing * 0.6) * CFrame.Angles(-facing * 0.6, 0.25, 0.15),
        colors.timber,
        Enum.Material.Wood
    )
end

-- Where a split lane runs at `distance`: off the line by its offset, turned along it.
local function laneFrame(track: Track.Track, split: Track.SplitSpan, which: number, distance: number): CFrame
    local here = Split.offset(split, which, distance)
    local ahead = Split.offset(split, which, distance + 1)
    return TrackFrames.frame(track, distance) * CFrame.new(here, 0, 0) * CFrame.Angles(0, -math.atan(ahead - here), 0)
end

-- The buffer stop at the end of a dead lane: a red-and-white beam on two timber posts braced from behind,
-- with a red lamp on top. `frame` is the lane at the buffer, facing along the track (the cart comes from
-- behind).
local function bufferStop(folder: Instance, frame: CFrame, colors: Colors)
    local gauge = trackConfig.RailGauge
    for _, side in { -1, 1 } do
        World.part(
            folder,
            "BufferPost",
            Vector3.new(0.9, 3.4, 0.9),
            frame * CFrame.new(side * gauge / 2, 1.2, 0),
            colors.timber,
            Enum.Material.Wood
        )
        World.part(
            folder,
            "BufferBrace",
            Vector3.new(0.6, 0.6, 3.6),
            frame * CFrame.new(side * gauge / 2, 1.3, -1.5) * CFrame.Angles(math.rad(-35), 0, 0),
            colors.timber,
            Enum.Material.Wood
        )
    end
    World.part(
        folder,
        "BufferBeam",
        Vector3.new(gauge + 2.4, 1.2, 1),
        frame * CFrame.new(0, 2.2, 0.4),
        Theme.Color.Danger,
        Enum.Material.SmoothPlastic
    )
    for _, x in { -1.6, 0, 1.6 } do
        World.part(
            folder,
            "BufferStripe",
            Vector3.new(0.5, 1.22, 1.02),
            frame * CFrame.new(x, 2.2, 0.4) * CFrame.Angles(0, 0, math.rad(30)),
            Theme.Color.Paper,
            Enum.Material.SmoothPlastic
        )
    end
    local lamp = World.part(
        folder,
        "BufferLamp",
        Vector3.new(0.8, 0.8, 0.8),
        frame * CFrame.new(0, 3.3, 0.4),
        Theme.Color.Danger,
        Enum.Material.Neon
    )
    lamp.Shape = Enum.PartType.Ball
end

-- The signal board before a split's switch: posts either side, a beam across, and over each lane a panel
-- (a green arrow for the open lane, a red cross for a dead one) with a lamp of the same color.
local function signals(folder: Instance, frame: CFrame, split: Track.SplitSpan, colors: Colors)
    local reach = split.offset + 5
    for _, side in { -1, 1 } do
        World.part(
            folder,
            "SignalPost",
            Vector3.new(0.8, 12, 0.8),
            frame * CFrame.new(side * reach, 5, 0),
            colors.timber,
            Enum.Material.Wood
        )
    end
    World.part(
        folder,
        "SignalBeam",
        Vector3.new(reach * 2 + 1, 0.8, 0.8),
        frame * CFrame.new(0, 11, 0),
        colors.timber,
        Enum.Material.Wood
    )
    for which = -1, 1 do
        local open = which == split.open
        local color = if open then Theme.Color.Safe else Theme.Color.Danger
        local panel = World.part(
            folder,
            "SignalPanel",
            Vector3.new(3.2, 3.2, 0.3),
            frame * CFrame.new(which * split.offset, 8.8, 0),
            Theme.Color.WoodDark,
            Enum.Material.Wood
        )
        local gui = Instance.new("SurfaceGui")
        gui.Face = Enum.NormalId.Back -- toward the oncoming cart
        gui.LightInfluence = 0
        gui.Brightness = 1.6
        gui.PixelsPerStud = 40
        gui.Parent = panel
        local face = Instance.new("TextLabel")
        face.Size = UDim2.fromScale(1, 1)
        face.BackgroundColor3 = color:Lerp(Theme.Color.Ink, 0.6)
        face.FontFace = Theme.Font.Number
        face.TextScaled = true
        face.TextColor3 = color
        face.Text = if open then ARROWS[which] else "✕"
        face.Parent = gui
        local rim = Instance.new("UIStroke")
        rim.Color = Theme.Color.Brass
        rim.Thickness = 4
        rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        rim.Parent = face
        local lamp = World.part(
            folder,
            "SignalLamp",
            Vector3.new(0.9, 0.9, 0.9),
            frame * CFrame.new(which * split.offset, 10.9, 0),
            color,
            Enum.Material.Neon
        )
        lamp.Shape = Enum.PartType.Ball
    end
end

-- Lays one lane of a split: rails through points LANE_STEP studs apart, sleepers and ballast, from the
-- switch to where it ends (the open lane rejoins the line; a dead one stops at its buffer stop).
local function lane(folder: Instance, track: Track.Track, split: Track.SplitSpan, which: number, colors: Colors)
    local gauge = trackConfig.RailGauge
    local stop = Split.railEnd(split, which)
    local d = split.from
    local previous = laneFrame(track, split, which, d).Position
    while d < stop - 1e-6 do
        local nextD = math.min(stop, d + LANE_STEP)
        local here = laneFrame(track, split, which, nextD).Position
        local length = (here - previous).Magnitude
        local frame = CFrame.lookAt((previous + here) / 2, here)
        for _, side in { -1, 1 } do
            World.part(
                folder,
                "Rail",
                Vector3.new(0.35, 0.4, length + 0.25),
                frame * CFrame.new(side * gauge / 2, -0.2, 0),
                colors.rail,
                Enum.Material.Metal
            )
        end
        World.part(
            folder,
            "Ballast",
            Vector3.new(gauge + 4, 3, length + 0.5),
            frame * CFrame.new(0, -2, 0),
            colors.ballast,
            Enum.Material.Slate
        )
        previous, d = here, nextD
    end
    local sleeper = math.ceil(split.from / 8) * 8
    while sleeper < stop do
        World.part(
            folder,
            "Sleeper",
            Vector3.new(gauge + 2.4, 0.35, 1.2),
            laneFrame(track, split, which, sleeper) * CFrame.new(0, -0.55, 0),
            colors.timber,
            Enum.Material.Wood
        )
        sleeper += 8
    end
    if Split.dead(split, which) then
        bufferStop(folder, laneFrame(track, split, which, split.buffer), colors)
    end
end

-- The invisible floor along one chunk, FLOOR_STEP studs at a time, sloping with the track, at the kit's
-- floor height; thick so nobody passes through it landing hard (TRAPS #44).
local FLOOR_STEP = 8
local function floor(folder: Instance, layout: Layout.Layout, placement: Layout.Placement, width: number)
    local track = layout.track
    local d = placement.from
    while d < placement.to - 1e-6 do
        local length = math.min(FLOOR_STEP, placement.to - d)
        local middle = d + length / 2
        local overGap = false
        for _, gap in track.gaps do
            if d + length > gap.from and d < gap.to then
                overGap = true
            end
        end
        if not overGap then
            local slab = World.part(
                folder,
                "Floor",
                Vector3.new(width, 6, length + 0.5),
                TrackFrames.frame(track, middle) * CFrame.new(0, trackConfig.FloorTop - 3, 0),
                Color3.new(),
                Enum.Material.SmoothPlastic
            )
            slab.Transparency = 1
            slab.CanCollide = true
        end
        d += length
    end
end

-- The index of the first track point at or after `distance`.
local function pointAt(distances: { number }, distance: number): number
    local low, high = 1, #distances
    while low < high do
        local mid = (low + high) // 2
        if distances[mid] < distance - 1e-6 then
            low = mid + 1
        else
            high = mid
        end
    end
    return low
end

-- Lays the rails, sleepers and ballast along one placed chunk (Layout.Placement), into `parent`.
function TrackDresser.dress(layout: Layout.Layout, placement: Layout.Placement, zone: any, parent: Instance)
    local folder = Instance.new("Folder")
    folder.Name = "Track"
    folder.Parent = parent

    local palette = zone.Palette
    local gauge = trackConfig.RailGauge
    local colors: Colors = {
        rail = World.color(palette.Rail),
        ballast = World.color(palette.RockDark),
        timber = World.color(palette.Timber),
    }
    local elevated = Configs.Kit.Pieces[placement.piece].Kind == "Cavern"
    local gaps = layout.track.gaps
    local splits = layout.track.splits
    local points, distances = layout.track.points, layout.track.distances
    local function brokenAt(index: number): boolean
        return offLine(gaps, splits, (distances[index] + distances[index + 1]) / 2)
    end

    -- Straight runs of points share one rail part; a run never crosses onto or off a gap or split. Chunks
    -- end on sampled points, so each chunk's rails stop exactly where the next one's start.
    local i = pointAt(distances, placement.from)
    local last = pointAt(distances, placement.to)
    while i < last do
        local a = TrackFrames.vector(points[i])
        local direction = (TrackFrames.vector(points[i + 1]) - a).Unit
        local broken = brokenAt(i)
        local j = i + 1
        while
            j < last
            and brokenAt(j) == broken
            and (TrackFrames.vector(points[j + 1]) - TrackFrames.vector(points[j])).Unit:Dot(direction) > 0.99995
        do
            j += 1
        end
        local b = TrackFrames.vector(points[j])
        local length = (b - a).Magnitude
        local frame = CFrame.lookAt((a + b) / 2, b)
        if not broken then
            for _, side in { -1, 1 } do
                World.part(
                    folder,
                    "Rail",
                    Vector3.new(0.35, 0.4, length + 0.25),
                    frame * CFrame.new(side * gauge / 2, -0.2, 0),
                    colors.rail,
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
                colors.ballast,
                Enum.Material.Slate
            )
        end
        i = j
    end

    -- Sleepers on a grid along the whole track, so they're evenly spaced across chunk joins.
    local spacing = if elevated then 4 else 8
    local distance = math.ceil(placement.from / spacing) * spacing
    while distance < placement.to do
        if not offLine(gaps, splits, distance) then
            World.part(
                folder,
                "Sleeper",
                Vector3.new(gauge + 2.4, 0.35, 1.2),
                TrackFrames.frame(layout.track, distance) * CFrame.new(0, -0.55, 0),
                colors.timber,
                Enum.Material.Wood
            )
        end
        distance += spacing
    end

    local function inside(at: number): boolean
        return at >= placement.from and at < placement.to
    end
    for _, gap in gaps do
        if inside(gap.from - 2) then
            brokenEdge(folder, TrackFrames.frame(layout.track, gap.from - 2), -1, colors)
        end
        if inside(gap.to + 2) then
            brokenEdge(folder, TrackFrames.frame(layout.track, gap.to + 2), 1, colors)
        end
    end
    local splitHere = false
    for _, split in splits do
        if inside(split.from) then
            splitHere = true
            for which = -1, 1 do
                lane(folder, layout.track, split, which, colors)
            end
            local board = math.max(placement.from + 2, split.from - 22)
            signals(folder, TrackFrames.flat(layout.track, board), split, colors)
        end
    end

    local widths = trackConfig.TrackFloor
    local kind = Configs.Kit.Pieces[placement.piece].Kind
    floor(folder, layout, placement, if splitHere then widths.Split else widths[kind] or widths.Tunnel)
end

return TrackDresser
