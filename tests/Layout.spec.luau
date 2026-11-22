local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Layout = require("../src/shared/Rules/Layout")
local Route = require("../src/shared/Rules/Route")
local Track = require("../src/shared/Rules/Track")

local zone = Configs.Zones[1]
local pieces = Configs.Kit.Pieces
local trackConfig = Configs.Run.Track
local SPEC = {
    Start = { x = 0, y = Configs.Run.StationHeight, z = 0 },
    Heading = 0,
    Step = trackConfig.Step,
    CartStopOffset = trackConfig.CartStopOffset,
}
local RULES = { MaxStep = trackConfig.Step * 1.5, MinY = -400, BaseHeading = 0 }

local function layout(seed: number)
    return Layout.build(Route.generate(zone, seed), zone.Kit, pieces, SPEC)
end

T.describe("Layout", function()
    T.it("lays out a rideable track for every seed", function()
        for seed = 1, 60 do
            local ok, problem = Track.validate(layout(seed).track, RULES)
            T.truthy(ok, "seed " .. seed .. ": " .. tostring(problem))
        end
    end)

    T.it("joins station, legs, stop chambers and the end cap", function()
        local result = layout(2)
        local segments = result.segments
        T.equal(segments[1].kind, "Station")
        T.equal(segments[1].from, 0)
        T.equal(segments[#segments].kind, "Cap")
        for i = 2, #segments do
            T.near(segments[i].from, segments[i - 1].to, 1e-9, "segment " .. i)
        end
        T.near(segments[#segments].to, result.track.length, 1e-6)
        T.equal(#segments, 2 + 2 * #zone.Legs)
    end)

    T.it("numbers the ride's segments 1, 2, 3... through the whole run", function()
        local total = 0
        for _, legSpec in zone.Legs do
            total += legSpec.Ride.Segments
        end
        T.truthy(total > 0, "the zone has a ride")
        for seed = 1, 20 do
            local result = layout(seed)
            T.equal(result.count, total)
            local expected = 1
            for _, placement in result.placements do
                if placement.number > 0 then
                    T.equal(placement.number, expected, "seed " .. seed)
                    T.truthy(placement.leg >= 1, "numbered segments are on a leg")
                    expected += 1
                else
                    T.equal(placement.leg, 0)
                end
            end
            T.equal(expected - 1, total)
        end
    end)

    T.it("finds the segment under any distance", function()
        local result = layout(7)
        T.equal(Layout.numberAt(result, result.parked), 0, "none yet at the station")
        for _, placement in result.placements do
            local middle = (placement.from + placement.to) / 2
            T.equal(result.placements[Layout.placementAt(result, middle)], placement)
            if placement.number > 0 then
                T.equal(Layout.numberAt(result, middle), placement.number)
            end
        end
        T.equal(Layout.numberAt(result, result.track.length), result.count, "the last one by the end")
    end)

    T.it("places pieces end to end along the track", function()
        local result = layout(4)
        for i, placement in result.placements do
            local at = Track.sample(result.track, placement.from)
            T.near(at.x, placement.position.x, 1e-6, "piece " .. i)
            T.near(at.y, placement.position.y, 1e-6, "piece " .. i)
            if i > 1 then
                T.near(placement.from, result.placements[i - 1].to, 1e-9, "piece " .. i)
            end
        end
        T.equal(result.placements[1].piece, zone.Kit.Station)
        T.equal(result.placements[#result.placements].piece, zone.Kit.Cap)
    end)

    T.it("stops the cart inside each leg's stop chamber", function()
        local result = layout(3)
        for leg = 1, #zone.Legs do
            local slot = Layout.slot(result, leg)
            T.truthy(slot, "leg " .. leg .. " has a slot")
            local stop = result.stops[leg]
            T.truthy(stop > slot.from and stop <= slot.to, "leg " .. leg .. " stop")
            T.equal(Layout.segmentAt(result, stop).kind, "Slot")
        end
        T.equal(Layout.segmentAt(result, result.parked).kind, "Station")
    end)

    T.it("keeps sharp bends on the legs", function()
        for seed = 1, 30 do
            local result = layout(seed)
            for _, span in result.track.sharp do
                local segment = Layout.segmentAt(result, (span.from + span.to) / 2)
                T.equal(segment.kind, "Leg", "seed " .. seed)
            end
        end
    end)

    T.it("finds every cavern", function()
        local result = layout(6)
        local caverns = Layout.placementsOf(result, pieces, "Cavern")
        T.truthy(#caverns >= #zone.Legs, "at least one cavern per leg")
        for _, placement in caverns do
            T.equal(pieces[placement.piece].Kind, "Cavern")
        end
    end)

    T.it("is the same for the same seed", function()
        local a, b = layout(9), layout(9)
        T.equal(#a.placements, #b.placements)
        T.equal(a.track.length, b.track.length)
    end)
end)
