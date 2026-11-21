local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Rng = require("../src/shared/Rules/Rng")
local Track = require("../src/shared/Rules/Track")

local zone = Configs.Zones[1]
local STEP = Configs.Run.Track.Step
local START = { x = 0, y = Configs.Run.StationHeight, z = 0 }
local RULES = { MaxStep = STEP * 1.5, MinY = -400, BaseHeading = 0 }

local function leg(seed: number, length: number?)
    local pieces = Track.pieces(Rng.new(seed), zone.Track, length or 1300, 0, 0)
    return Track.build(pieces, START, 0, STEP), pieces
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
    T.it("rolls a rideable track for every seed", function()
        for seed = 1, 100 do
            local ok, problem = Track.validate(leg(seed), RULES)
            T.truthy(ok, "seed " .. seed .. ": " .. tostring(problem))
        end
    end)

    T.it("adds up to the leg's horizontal length", function()
        local _, pieces = leg(11)
        local total = 0
        for _, piece in pieces do
            total += piece.length
        end
        T.near(total, 1300, 1e-6)
    end)

    T.it("puts at least one sharp curve on every leg", function()
        for seed = 1, 100 do
            T.truthy(#leg(seed).sharp >= 1, "seed " .. seed)
        end
    end)

    T.it("keeps the heading inside MaxHeading", function()
        for seed = 1, 100 do
            local heading = 0
            for _, piece in select(2, leg(seed)) do
                heading += piece.turn
                T.truthy(math.abs(heading) <= zone.Track.MaxHeading + 1e-9, "seed " .. seed)
            end
        end
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
        T.truthy(direction.y < 0, "the track slopes down")
    end)

    T.it("interpolates between sampled points", function()
        local track = leg(3)
        local a, b = track.points[2], track.points[3]
        local mid = Track.sample(track, (track.distances[2] + track.distances[3]) / 2)
        T.near(mid.x, (a.x + b.x) / 2, 1e-9)
        T.near(mid.y, (a.y + b.y) / 2, 1e-9)
    end)

    T.it("knows where the sharp curves are", function()
        local track = leg(4)
        local span = track.sharp[1]
        T.truthy(Track.sharpAt(track, (span.from + span.to) / 2), "inside")
        T.falsy(Track.sharpAt(track, span.from - 1), "before")
        T.equal(Track.nextSharp(track, 0), span)
        T.equal(Track.nextSharp(track, track.length + 1), nil)
    end)

    T.it("catches a track that climbs", function()
        local track = copy(leg(5))
        track.points[10].y += 5
        T.falsy((Track.validate(track, RULES)))
    end)

    T.it("catches a step that's too long", function()
        local track = copy(leg(5))
        track.distances[10] += STEP * 3
        for i = 11, #track.distances do
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
