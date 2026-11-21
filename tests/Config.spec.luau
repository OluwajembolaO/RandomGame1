local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Upgrades = require("../src/shared/Rules/Upgrades")

local KINDS = { Minigame = true, Rest = true, Boss = true, Elite = true }

T.describe("Config", function()
    T.it("lists six zones, top to bottom, ending in Hell", function()
        T.equal(#Configs.Zones, 6)
        T.equal(Configs.Zones[1].Id, "OldMine")
        T.equal(Configs.Zones[6].Id, "Hell")
        T.truthy(Configs.Zones[1].Built, "zone 1 is built")
    end)

    T.it("only references stages that exist", function()
        for _, zone in Configs.Zones do
            for index, leg in zone.Legs or {} do
                local ids = leg.Stop.Fork or { leg.Stop.Stage }
                for _, id in ids do
                    T.truthy(Configs.Stages[id], zone.Id .. " leg " .. index .. " uses unknown stage " .. tostring(id))
                end
            end
        end
    end)

    T.it("gives every stage a name, genre, kind and footprint", function()
        for id, stage in Configs.Stages do
            T.truthy(type(stage.Name) == "string", id .. " Name")
            T.truthy(type(stage.Genre) == "string", id .. " Genre")
            T.truthy(KINDS[stage.Kind], id .. " has unknown Kind " .. tostring(stage.Kind))
            T.truthy(stage.Length > 0, id .. " Length")
            T.truthy(stage.Drop >= 0, id .. " Drop")
        end
    end)

    T.it("keeps every curve within MaxHeading so the track can always turn back", function()
        for _, zone in Configs.Zones do
            local track = zone.Track
            if track then
                T.truthy(track.CurveTurn[2] <= track.MaxHeading, zone.Id .. " CurveTurn")
                T.truthy(track.SharpTurn[2] <= track.MaxHeading, zone.Id .. " SharpTurn")
                T.truthy(track.MaxHeading < math.pi / 2, zone.Id .. " MaxHeading must stay under 90 degrees")
                T.truthy(track.Grade[1] > 0, zone.Id .. " track must always slope down")
            end
        end
    end)

    T.it("keeps the whole built descent above FallenPartsDestroyHeight", function()
        local lowest = Configs.Run.StationHeight
        for _, zone in Configs.Zones do
            for _, leg in zone.Legs or {} do
                lowest -= leg.Ride.Length * zone.Track.Grade[2]
                local deepest = 0
                for _, id in leg.Stop.Fork or { leg.Stop.Stage } do
                    deepest = math.max(deepest, Configs.Stages[id].Drop)
                end
                lowest -= deepest
            end
        end
        T.truthy(lowest > -400, "descent bottoms out at y=" .. lowest)
    end)

    T.it("has valid upgrades", function()
        local ok, problem = Upgrades.validate(Configs.Upgrades, Upgrades.baseStats(Configs))
        T.truthy(ok, problem)
    end)

    T.it("uses whole, non-negative asset ids", function()
        for name, id in Configs.Assets do
            T.truthy(type(id) == "number" and id >= 0 and id % 1 == 0, name .. " asset id")
        end
    end)
end)
