--!strict
-- Lays a whole route out in space: the station, each ride leg, and a straight "slot" for each stop,
-- joined into one continuous track that the cart follows by distance. Laid out (and carved) once per run.
-- A fork's slot takes the biggest footprint of its branches, so the track after it is the same
-- whichever branch wins the vote.

local Route = require("./Route")
local Rng = require("./Rng")
local Track = require("./Track")

-- kind is "Station", "Leg" or "Slot" (TRAPS #19). leg is 0 for the station.
export type Segment = { kind: string, leg: number, from: number, to: number }
export type Footprint = { length: number, drop: number }
export type Layout = {
    track: Track.Track,
    segments: { Segment },
    -- Where the cart halts for each leg's stop, by leg index.
    stops: { number },
    -- Where the cart waits at the station.
    parked: number,
}

export type Spec = {
    Start: Track.Vec,
    Heading: number,
    Step: number,
    StationLength: number,
    CartStopOffset: number, -- studs into a slot where the cart halts
}

-- Fields read from Config/Stages entries.
type StageSpec = { Length: number, Drop: number }

local Layout = {}

function Layout.footprint(stop: Route.Stop, stages: { [string]: StageSpec }): Footprint
    local length, drop = 0, 0
    for _, id in Route.stagesOf(stop) do
        length = math.max(length, stages[id].Length)
        drop = math.max(drop, stages[id].Drop)
    end
    return { length = length, drop = drop }
end

function Layout.build(route: Route.Route, zone: any, stages: { [string]: StageSpec }, spec: Spec): Layout
    -- Its own random stream, so the track shape doesn't change when the route roll does.
    local rng = Rng.new(route.seed * 7 + 3)
    local pieces: { Track.Track } = {}
    local kinds: { { kind: string, leg: number } } = {}
    local start, heading = spec.Start, spec.Heading

    local function add(track: Track.Track, kind: string, leg: number)
        table.insert(pieces, track)
        table.insert(kinds, { kind = kind, leg = leg })
        start = track.points[#track.points]
        heading = track.endHeading
    end

    add(Track.straight(spec.StationLength, 0, start, heading, spec.Step), "Station", 0)
    for _, leg in route.legs do
        local legPieces = Track.pieces(rng, zone.Track, leg.rideLength, heading, spec.Heading)
        add(Track.build(legPieces, start, heading, spec.Step), "Leg", leg.index)
        local footprint = Layout.footprint(leg.stop, stages)
        add(Track.straight(footprint.length, footprint.drop, start, heading, spec.Step), "Slot", leg.index)
    end

    local segments: { Segment } = {}
    local stops: { number } = {}
    local offset = 0
    for index, piece in pieces do
        local segment = { kind = kinds[index].kind, leg = kinds[index].leg, from = offset, to = offset + piece.length }
        table.insert(segments, segment)
        if segment.kind == "Slot" then
            stops[segment.leg] = segment.from + math.min(spec.CartStopOffset, piece.length)
        end
        offset += piece.length
    end

    return {
        track = Track.concat(pieces),
        segments = segments,
        stops = stops,
        parked = spec.StationLength / 2,
    }
end

-- The segment containing `distance` (the first one, on a boundary).
function Layout.segmentAt(layout: Layout, distance: number): Segment
    for _, segment in layout.segments do
        if distance <= segment.to then
            return segment
        end
    end
    return layout.segments[#layout.segments]
end

-- The slot segment for a leg's stop.
function Layout.slot(layout: Layout, leg: number): Segment?
    for _, segment in layout.segments do
        if segment.kind == "Slot" and segment.leg == leg then
            return segment
        end
    end
    return nil
end

return Layout
