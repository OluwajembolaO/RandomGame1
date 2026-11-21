local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Upgrades = require("../src/shared/Rules/Upgrades")

local KINDS = { Minigame = true, Rest = true, Boss = true, Elite = true }
local PIECE_KINDS = { Station = true, Stop = true, Tunnel = true, Cavern = true, Cap = true }
local pieces = Configs.Kit.Pieces

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

    T.it("gives every stage a name, genre and kind", function()
        for id, stage in Configs.Stages do
            T.truthy(type(stage.Name) == "string", id .. " Name")
            T.truthy(type(stage.Genre) == "string", id .. " Genre")
            T.truthy(KINDS[stage.Kind], id .. " has unknown Kind " .. tostring(stage.Kind))
        end
    end)

    T.it("builds every zone's cave from kit pieces of the right kind", function()
        for _, zone in Configs.Zones do
            local kit = zone.Kit
            if kit then
                local function expect(id, kind)
                    T.truthy(pieces[id], zone.Id .. " uses missing kit piece " .. tostring(id))
                    T.equal(pieces[id].Kind, kind, zone.Id .. " " .. id)
                end
                expect(kit.Station, "Station")
                expect(kit.Stop, "Stop")
                expect(kit.Cap, "Cap")
                expect(kit.Straight, "Tunnel")
                for _, id in kit.Bends do
                    expect(id, "Tunnel")
                end
                for _, id in kit.Sharps do
                    expect(id, "Tunnel")
                    T.truthy(pieces[id].Sharp, id .. " is meant to be sharp")
                end
                for _, id in kit.Caverns do
                    expect(id, "Cavern")
                end
                T.truthy(kit.MaxHeading < math.pi / 2, zone.Id .. " MaxHeading must stay under 90 degrees")
            end
        end
    end)

    T.it("has kit pieces modeled on the game's track steps", function()
        T.equal(Configs.Kit.Step, Configs.Run.Track.Step)
        for id, def in pieces do
            T.truthy(PIECE_KINDS[def.Kind], id .. " Kind")
            T.truthy(def.Length > 0 and def.Length % Configs.Kit.Step == 0, id .. " Length must be whole steps")
            T.truthy(def.Drop >= 0, id .. " never climbs")
            T.truthy(math.abs(def.Turn) <= Configs.Zones[1].Kit.MaxHeading, id .. " Turn")
            if def.Kind ~= "Tunnel" then
                T.equal(def.Turn, 0, id .. " should be straight")
            end
            if def.Kind == "Station" or def.Kind == "Stop" then
                T.equal(def.Drop, 0, id .. " needs a flat floor")
            end
        end
    end)

    T.it("only lights the kit with palette colors, within Roblox's light range", function()
        local palette = Configs.Zones[1].Palette
        for id, def in pieces do
            for index, light in def.Lights do
                T.truthy(palette[light.Color], id .. " light " .. index .. " uses unknown color " .. light.Color)
                T.truthy(light.Range > 0 and light.Range <= 60, id .. " light " .. index .. " Range")
                T.truthy(light.Brightness > 0, id .. " light " .. index .. " Brightness")
            end
            for _, emitter in def.Emitters do
                for _, color in emitter.Colors or {} do
                    T.truthy(palette[color], id .. " emitter uses unknown color " .. color)
                end
            end
        end
    end)

    T.it("keeps the whole built descent above FallenPartsDestroyHeight", function()
        local steepest = 0
        for _, def in pieces do
            steepest = math.max(steepest, def.Drop / def.Length)
        end
        local lowest = Configs.Run.StationHeight
        for _, zone in Configs.Zones do
            for _, leg in zone.Legs or {} do
                -- A leg can overshoot its length by up to one cavern.
                lowest -= (leg.Ride.Length + 224) * steepest
            end
        end
        T.truthy(lowest > -400, "descent bottoms out at y=" .. lowest)
    end)

    T.it("has valid upgrades", function()
        local ok, problem = Upgrades.validate(Configs.Upgrades, Upgrades.baseStats(Configs))
        T.truthy(ok, problem)
    end)

    T.it("gives every sound a real asset id and a sane volume", function()
        local Sounds = require("../src/shared/Config/Sounds")
        local count = 0
        for sectionName, section in Sounds do
            if type(section) == "table" then
                for name, spec in section do
                    count += 1
                    local where = sectionName .. "." .. name
                    T.truthy(type(spec.Id) == "number" and spec.Id > 0 and spec.Id % 1 == 0, where .. " Id")
                    T.truthy(spec.Volume > 0 and spec.Volume <= 2, where .. " Volume")
                end
            end
        end
        T.truthy(count >= 10, "expected the full sound set, found " .. count)
    end)

    T.it("makes every gap jumpable by pushing, and never under the brake", function()
        local Cart = require("../src/shared/Rules/Cart")
        local Jump = require("../src/shared/Rules/Jump")
        local Kit = require("../src/shared/Rules/Kit")
        local stats = Cart.stats(Configs.Run.Cart, Upgrades.baseStats(Configs))
        local physics = Configs.Run.Cart.Jump
        local count = 0
        for id, def in pieces do
            local gap = def.Gap
            if gap then
                count += 1
                T.equal(def.Turn, 0, id .. " gaps only on straight pieces")
                T.truthy(
                    gap.From % Configs.Kit.Step == 0 and gap.To % Configs.Kit.Step == 0,
                    id .. " gap on whole steps"
                )
                T.truthy(gap.From >= 16 and gap.To < def.Length, id .. " gap inside the piece with a run-up")
                local track = Kit.trackPiece(def)
                local need = Jump.minSpeed(physics, { length = gap.To - gap.From, drop = gap.Drop })
                local function speed(throttle: number): number
                    local cart = Cart.new(stats)
                    Cart.setThrottle(cart, throttle)
                    return Cart.targetSpeed(cart, stats, true, track.grade, 0)
                end
                T.truthy(speed(1) > need + 2, id .. " can't be cleared even pushing")
                T.truthy(speed(-1) < need, id .. " can be cleared under the brake")
                if def.Kind == "Tunnel" then
                    T.truthy(speed(0) > need, id .. ": washouts clear at cruise speed")
                end
            end
        end
        T.truthy(count >= 2, "expected the washout and the rift")
    end)

    T.it("keeps the ride camera gentle", function()
        local camera = Configs.Camera
        for _, share in { camera.Sensitivity, camera.RideSensitivity } do
            T.truthy(share > 0 and share <= 1, "look sensitivity is a share of Roblox's")
        end
        T.truthy(camera.LeanFollow >= 0 and camera.LeanFollow <= 1, "LeanFollow")
        T.truthy(camera.NodDown <= 3 and camera.NodUp <= 3, "nod stays under 3 degrees")
        T.truthy(camera.Shake <= 2, "shake stays under 2 degrees")
        T.truthy(camera.Fov + camera.FovAtSpeed <= 90, "field of view")
        for _, rate in { camera.LookRate, camera.FollowRate, camera.LeanRate, camera.NodRate } do
            T.truthy(rate > 0, "every rate eases toward its target")
        end
    end)

    T.it("uses whole, non-negative asset ids", function()
        for name, id in Configs.Assets do
            T.truthy(type(id) == "number" and id >= 0 and id % 1 == 0, name .. " asset id")
        end
    end)
end)
