--!strict
-- Lays a whole route out in space from the cave kit: the station, each ride leg's rolled pieces, a stop
-- chamber for each stop, and an end cap, joined into one continuous track the cart follows by distance.
-- Every stop (fork or not) uses the same stop chamber, so the track after a fork doesn't depend on the vote.

local Kit = require("./Kit")
local Rng = require("./Rng")
local Route = require("./Route")
local Track = require("./Track")

-- kind is "Station", "Leg", "Slot" or "Cap" (TRAPS #19). leg is 0 for the station.
export type Segment = { kind: string, leg: number, from: number, to: number }

-- Where one kit piece goes: its track starts at `position` heading `heading`, `from` studs along the route.
export type Placement = { piece: string, from: number, to: number, position: Track.Vec, heading: number }

export type Layout = {
    track: Track.Track,
    segments: { Segment },
    placements: { Placement },
    -- Where the cart halts for each leg's stop, by leg index.
    stops: { number },
    -- Where the cart waits at the station.
    parked: number,
}

export type Spec = {
    Start: Track.Vec,
    Heading: number,
    Step: number,
    CartStopOffset: number, -- studs into a stop chamber where the cart halts
}

local Layout = {}

-- The layout settings every run uses, from the Run config. Server and clients both lay the route out from
-- the run's seed with these, so they agree on where every piece (and every light) goes.
function Layout.spec(run: any): Spec
    return {
        Start = { x = 0, y = run.StationHeight, z = 0 },
        Heading = 0,
        Step = run.Track.Step,
        CartStopOffset = run.Track.CartStopOffset,
    }
end

function Layout.build(route: Route.Route, kitSpec: Kit.Spec, pieces: Kit.Pieces, spec: Spec): Layout
    -- Its own random stream, so the cave doesn't change when the route roll does.
    local rng = Rng.new(route.seed * 7 + 3)
    local tracks: { Track.Track } = {}
    local placements: { Placement } = {}
    local segments: { Segment } = {}
    local stops: { number } = {}
    local start, heading, offset = spec.Start, spec.Heading, 0

    local function place(id: string): (number, number)
        local track = Track.build({ Kit.trackPiece(pieces[id]) }, start, heading, spec.Step)
        local from = offset
        table.insert(tracks, track)
        table.insert(
            placements,
            { piece = id, from = from, to = from + track.length, position = start, heading = heading }
        )
        offset += track.length
        start = track.points[#track.points]
        heading = track.endHeading
        return from, offset
    end

    local stationFrom, stationTo = place(kitSpec.Station)
    table.insert(segments, { kind = "Station", leg = 0, from = stationFrom, to = stationTo })
    for _, leg in route.legs do
        local legFrom = offset
        for _, id in Kit.leg(rng, pieces, kitSpec, leg.rideLength, heading, spec.Heading) do
            place(id)
        end
        table.insert(segments, { kind = "Leg", leg = leg.index, from = legFrom, to = offset })
        local slotFrom, slotTo = place(kitSpec.Stop)
        table.insert(segments, { kind = "Slot", leg = leg.index, from = slotFrom, to = slotTo })
        stops[leg.index] = slotFrom + spec.CartStopOffset
    end
    local capFrom, capTo = place(kitSpec.Cap)
    table.insert(segments, { kind = "Cap", leg = #route.legs, from = capFrom, to = capTo })

    return {
        track = Track.concat(tracks),
        segments = segments,
        placements = placements,
        stops = stops,
        parked = (stationFrom + stationTo) / 2,
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

-- The placements whose piece is of `kind` (for example every cavern, for the track dressing).
function Layout.placementsOf(layout: Layout, pieces: Kit.Pieces, kind: string): { Placement }
    local list = {}
    for _, placement in layout.placements do
        if pieces[placement.piece].Kind == kind then
            table.insert(list, placement)
        end
    end
    return list
end

return Layout
