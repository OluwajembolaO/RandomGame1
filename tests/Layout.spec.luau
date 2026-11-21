local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Layout = require("../src/shared/Rules/Layout")
local Route = require("../src/shared/Rules/Route")
local Track = require("../src/shared/Rules/Track")

local zone = Configs.Zones[1]
local trackConfig = Configs.Run.Track
local SPEC = {
    Start = { x = 0, y = Configs.Run.StationHeight, z = 0 },
    Heading = 0,
    Step = trackConfig.Step,
    StationLength = trackConfig.StationLength,
    CartStopOffset = trackConfig.CartStopOffset,
}
local RULES = { MaxStep = trackConfig.Step * 1.5, MinY = -400, BaseHeading = 0 }

local function layout(seed: number)
    return Layout.build(Route.generate(zone, seed), zone, Configs.Stages, SPEC)
end

T.describe("Layout", function()
    T.it("lays out a rideable track for every seed", function()
        for seed = 1, 60 do
            local ok, problem = Track.validate(layout(seed).track, RULES)
            T.truthy(ok, "seed " .. seed .. ": " .. tostring(problem))
        end
    end)

    T.it("joins station, legs and slots end to end", function()
        local result = layout(2)
        local segments = result.segments
        T.equal(segments[1].kind, "Station")
        T.equal(segments[1].from, 0)
        for i = 2, #segments do
            T.near(segments[i].from, segments[i - 1].to, 1e-9, "segment " .. i)
        end
        T.near(segments[#segments].to, result.track.length, 1e-6)
        T.equal(#segments, 1 + 2 * #zone.Legs)
    end)

    T.it("stops the cart inside each leg's slot", function()
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

    T.it("keeps sharp curves out of stations and slots", function()
        for seed = 1, 30 do
            local result = layout(seed)
            for _, span in result.track.sharp do
                local segment = Layout.segmentAt(result, (span.from + span.to) / 2)
                T.equal(segment.kind, "Leg", "seed " .. seed)
            end
        end
    end)

    T.it("sizes a fork's slot for its biggest branch", function()
        local stop = { options = { "SignalRoom", "SupplyDepot" } }
        local footprint = Layout.footprint(stop, Configs.Stages)
        T.equal(footprint.length, math.max(Configs.Stages.SignalRoom.Length, Configs.Stages.SupplyDepot.Length))
        T.equal(footprint.drop, math.max(Configs.Stages.SignalRoom.Drop, Configs.Stages.SupplyDepot.Drop))
    end)

    T.it("is the same for the same seed", function()
        local a, b = layout(9), layout(9)
        T.equal(#a.track.points, #b.track.points)
        T.equal(a.track.length, b.track.length)
    end)
end)
