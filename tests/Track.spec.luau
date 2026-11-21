local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Kit = require("../src/shared/Rules/Kit")
local Rng = require("../src/shared/Rules/Rng")
local Track = require("../src/shared/Rules/Track")

local pieces = Configs.Kit.Pieces
local spec = Configs.Zones[1].Kit
local STEP = Configs.Run.Track.Step
local START = { x = 0, y = Configs.Run.StationHeight, z = 0 }
local RULES = { MaxStep = STEP * 1.5, MinY = -400, BaseHeading = 0 }

local function trackOf(ids: { string })
    local list = {}
    for _, id in ids do
        table.insert(list, Kit.trackPiece(pieces[id]))
    end
    return Track.build(list, START, 0, STEP)
end

local function leg(seed: number)
    return trackOf(Kit.leg(Rng.new(seed), pieces, spec, 1300, 0, 0))
end

local function copy(track)
    local points = {}
    for i, p in track.points do
        points[i] = { x = p.x, y = p.y, z = p.z }
    end
    local result = table.clone(track)
    result.points = points
    result.distances = table.clone(track.distances)
    return result
end

T.describe("Track", function()
    T.it("builds a rideable track from every rolled leg", function()
        for seed = 1, 100 do
            local ok, problem = Track.validate(leg(seed), RULES)
            T.truthy(ok, "seed " .. seed .. ": " .. tostring(problem))
        end
    end)

    T.it("ends a bend facing its turn and lower by its drop", function()
        local bend = pieces.Tunnel_BendR
        local track = trackOf({ "Tunnel_BendR" })
        T.near(track.endHeading, bend.Turn, 1e-9)
        T.near(track.points[#track.points].y, START.y - bend.Drop, 1e-9)
    end)

    T.it("samples positions and unit directions by distance", function()
        local track = leg(3)
        local first = Track.sample(track, 0)
        T.near(first.x, START.x)
        T.near(first.y, START.y)
        local last = Track.sample(track, track.length + 50)
        local tail = track.points[#track.points]
        T.near(last.x, tail.x)
        T.near(last.z, tail.z)
        local _, direction = Track.sample(track, track.length / 2)
        T.near(math.sqrt(direction.x ^ 2 + direction.y ^ 2 + direction.z ^ 2), 1, 1e-9)
        T.truthy(direction.y <= 0, "the track never climbs")
    end)

    T.it("interpolates between sampled points", function()
        local track = leg(3)
        local a, b = track.points[2], track.points[3]
        local mid = Track.sample(track, (track.distances[2] + track.distances[3]) / 2)
        T.near(mid.x, (a.x + b.x) / 2, 1e-9)
        T.near(mid.y, (a.y + b.y) / 2, 1e-9)
    end)

    T.it("knows where the sharp bends are", function()
        local track = trackOf({ spec.Straight, "Tunnel_SharpR", spec.Straight })
        T.equal(#track.sharp, 1)
        local span = track.sharp[1]
        T.truthy(Track.sharpAt(track, (span.from + span.to) / 2), "inside")
        T.falsy(Track.sharpAt(track, span.from - 1), "before")
        T.equal(Track.nextSharp(track, 0), span)
        T.equal(Track.nextSharp(track, track.length + 1), nil)
    end)

    T.it("measures grade and curvature along the track", function()
        local straight = pieces[spec.Straight]
        local grade, curvature = Track.shapeAt(trackOf({ spec.Straight }), 32)
        T.near(grade, straight.Drop / straight.Length, 1e-6)
        T.near(curvature, 0, 1e-9)
        local bend = pieces.Tunnel_BendR
        local _, right = Track.shapeAt(trackOf({ "Tunnel_BendR" }), 32)
        T.near(right, bend.Turn / bend.Length, 1e-3)
        local _, left = Track.shapeAt(trackOf({ "Tunnel_BendL" }), 32)
        T.truthy(left < 0, "left bends curve negative")
    end)

    T.it("joins tracks end to end", function()
        local a = trackOf({ spec.Straight })
        local b = Track.build({ Kit.trackPiece(pieces.Tunnel_BendL) }, a.points[#a.points], a.endHeading, STEP)
        local joined = Track.concat({ a, b })
        T.near(joined.length, a.length + b.length, 1e-9)
        T.equal(#joined.points, #a.points + #b.points - 1)
        T.near(joined.endHeading, b.endHeading)
    end)

    T.it("catches a track that climbs", function()
        local track = copy(leg(5))
        track.points[10].y += 5
        T.falsy((Track.validate(track, RULES)))
    end)

    T.it("catches a step that's too long", function()
        local track = copy(leg(5))
        for i = 10, #track.distances do
            track.distances[i] += STEP * 3
        end
        T.falsy((Track.validate(track, RULES)))
    end)

    T.it("catches a track that turns back on itself", function()
        local track = copy(leg(5))
        track.points[10].x = track.points[9].x - 1
        T.falsy((Track.validate(track, RULES)))
    end)

    T.it("catches a track that drops too low", function()
        T.falsy((Track.validate(leg(5), { MaxStep = RULES.MaxStep, MinY = START.y - 1, BaseHeading = 0 })))
    end)
end)
