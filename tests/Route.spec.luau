local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Route = require("../src/shared/Rules/Route")

local zone = Configs.Zones[1]

T.describe("Route", function()
    T.it("rolls a valid route for every seed", function()
        for seed = 1, 200 do
            local ok, problem = Route.validate(Route.generate(zone, seed), Configs.Stages)
            T.truthy(ok, "seed " .. seed .. ": " .. tostring(problem))
        end
    end)

    T.it("is the same for the same seed", function()
        local a, b = Route.generate(zone, 99), Route.generate(zone, 99)
        for i, leg in a.legs do
            T.equal(leg.ambushes, b.legs[i].ambushes)
            T.equal(table.concat(Route.stagesOf(leg.stop), ","), table.concat(Route.stagesOf(b.legs[i].stop), ","))
        end
    end)

    T.it("follows the prototype route: obby, fork, boss", function()
        local route = Route.generate(zone, 5)
        T.equal(#route.legs, 3)
        T.equal(route.legs[1].stop.stage, "Obby")
        local options = route.legs[2].stop.options
        T.truthy(options and #options == 2, "leg 2 is a two-way fork")
        T.truthy(table.find(options, "SignalRoom") and table.find(options, "SupplyDepot"), "fork branches")
        T.equal(route.legs[3].stop.stage, "ForemanBoss")
    end)

    T.it("rolls ambushes inside each leg's range", function()
        for seed = 1, 100 do
            for i, leg in Route.generate(zone, seed).legs do
                local range = zone.Legs[i].Ride.Ambushes
                T.truthy(leg.ambushes >= range[1] and leg.ambushes <= range[2], "leg " .. i .. " ambushes")
            end
        end
    end)

    T.it("catches a route that doesn't end at a boss", function()
        local route = Route.generate(zone, 1)
        route.legs[3].stop = { stage = "Obby" }
        T.falsy((Route.validate(route, Configs.Stages)))
    end)

    T.it("catches a boss before the end", function()
        local route = Route.generate(zone, 1)
        route.legs[1].stop = { stage = "ForemanBoss" }
        T.falsy((Route.validate(route, Configs.Stages)))
    end)

    T.it("catches forks with unknown, repeated or too few branches", function()
        for _, options in { { "SignalRoom", "Nowhere" }, { "SignalRoom", "SignalRoom" }, { "SignalRoom" } } do
            local route = Route.generate(zone, 1)
            route.legs[2].stop = { options = options }
            T.falsy((Route.validate(route, Configs.Stages)), table.concat(options, ","))
        end
    end)
end)
