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
                local KIND_OF_TAG = {
                    Cavern = "Cavern",
                    Sharp = "Tunnel",
                    Bend = "Tunnel",
                    Gap = "Tunnel",
                    Split = "Tunnel",
                    Steep = "Tunnel",
                }
                local seen = {}
                for _, chunk in kit.Chunks do
                    T.falsy(seen[chunk.Id], zone.Id .. " lists " .. chunk.Id .. " twice")
                    seen[chunk.Id] = true
                    T.truthy(chunk.Weight > 0, chunk.Id .. " Weight")
                    local def = pieces[chunk.Id]
                    T.truthy(def, zone.Id .. " uses missing kit piece " .. chunk.Id)
                    if chunk.Tag then
                        expect(chunk.Id, KIND_OF_TAG[chunk.Tag] or def.Kind)
                    end
                    T.equal(def.Sharp, chunk.Tag == "Sharp", chunk.Id .. " is tagged Sharp exactly when it's sharp")
                    T.equal(def.Gap ~= nil and def.Kind == "Tunnel", chunk.Tag == "Gap", chunk.Id .. " Gap tag")
                    T.equal(
                        def.Split ~= nil,
                        chunk.Tag == "Split",
                        chunk.Id .. " is tagged Split exactly when it splits"
                    )
                    T.truthy(
                        chunk.Tier == nil or chunk.Tier == 1 or chunk.Tier == 2 or chunk.Tier == 3,
                        chunk.Id .. " Tier is 1, 2 or 3"
                    )
                    if chunk.Tag then
                        T.truthy(kit.Tags[chunk.Tag], chunk.Id .. " Tag " .. chunk.Tag .. " has no rule")
                    end
                    for _, id in chunk.After or {} do
                        T.truthy(pieces[id], chunk.Id .. " After uses missing piece " .. id)
                    end
                end
                T.truthy(seen[kit.Straight], zone.Id .. " pool needs its Straight")
                for tag, rule in kit.Tags do
                    T.truthy(
                        rule.Spacing[1] >= 0 and rule.Spacing[2] >= rule.Spacing[1],
                        zone.Id .. " " .. tag .. " Spacing"
                    )
                end
                for _, tag in kit.EveryLeg do
                    T.truthy(kit.Tags[tag], zone.Id .. " EveryLeg tag " .. tag .. " has no rule")
                end
                for name, difficulty in kit.Difficulty or {} do
                    T.equal(#difficulty.Tiers, 3, name .. " Tiers")
                    T.truthy(difficulty.Tiers[1] > 0, name .. " always has some easy chunks")
                    for tag, spacing in difficulty.Spacing or {} do
                        T.truthy(kit.Tags[tag], name .. " Spacing for unknown tag " .. tag)
                        T.truthy(spacing[1] >= 0 and spacing[2] >= spacing[1], name .. " " .. tag .. " Spacing")
                    end
                    for _, tag in difficulty.EveryLeg or {} do
                        T.truthy(kit.Tags[tag], name .. " EveryLeg tag " .. tag .. " has no rule")
                    end
                end
                for index, leg in zone.Legs do
                    local difficulty = leg.Ride.Difficulty
                    T.truthy(
                        difficulty == nil or (kit.Difficulty and kit.Difficulty[difficulty]),
                        zone.Id .. " leg " .. index .. " has unknown Difficulty " .. tostring(difficulty)
                    )
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
        local Layout = require("../src/shared/Rules/Layout")
        local Route = require("../src/shared/Rules/Route")
        local zone = Configs.Zones[1]
        local lowest = math.huge
        for seed = 1, 200 do
            local layout = Layout.build(Route.generate(zone, seed), zone.Kit, pieces, Layout.spec(Configs.Run))
            for _, point in layout.track.points do
                lowest = math.min(lowest, point.y)
            end
        end
        -- Falling into a chasm takes the cart about 70 studs below the rails before it's hauled back.
        T.truthy(lowest - 150 > -500, "descent bottoms out at y=" .. lowest)
    end)

    T.it("has valid upgrades", function()
        local ok, problem = Upgrades.validate(Configs.Upgrades, Upgrades.baseStats(Configs))
        T.truthy(ok, problem)
    end)

    T.it("gives every sound a real asset id and a sane volume", function()
        local Sounds = require("../src/shared/Config/Sounds")
        local count = 0
        local function check(where: string, spec: any)
            count += 1
            T.truthy(type(spec.Id) == "number" and spec.Id > 0 and spec.Id % 1 == 0, where .. " Id")
            T.truthy(spec.Volume > 0 and spec.Volume <= 2, where .. " Volume")
        end
        for sectionName, section in Sounds do
            if sectionName ~= "Acoustics" then
                for name, spec in section do
                    if spec.Sounds then
                        for index, entry in spec.Sounds do
                            check(sectionName .. "." .. name .. "[" .. index .. "]", entry)
                        end
                    else
                        check(sectionName .. "." .. name, spec)
                    end
                end
            end
        end
        T.truthy(count >= 10, "expected the full sound set, found " .. count)
    end)

    T.it("keeps the cave acoustics in Roblox's ranges", function()
        local Acoustics = require("../src/shared/Config/Sounds").Acoustics
        for _, name in { "Tunnel", "Cavern", "Chamber" } do
            local space = Acoustics[name]
            T.truthy(space, "missing " .. name)
            T.truthy(space.DecayTime >= 0.1 and space.DecayTime <= 20, name .. " DecayTime")
            T.truthy(space.Density >= 0 and space.Density <= 1, name .. " Density")
            T.truthy(space.Diffusion >= 0 and space.Diffusion <= 1, name .. " Diffusion")
            T.truthy(space.EchoDelay >= 0.01 and space.EchoDelay <= 1, name .. " EchoDelay")
            T.truthy(space.EchoFeedback >= 0 and space.EchoFeedback < 1, name .. " EchoFeedback")
            for _, level in { "Wet", "Dry", "EchoWet" } do
                T.truthy(space[level] >= -80 and space[level] <= 0, name .. " " .. level)
            end
            T.truthy(space.HighGain >= -80 and space.HighGain <= 10, name .. " HighGain")
        end
        T.truthy(Acoustics.Cavern.DecayTime > Acoustics.Tunnel.DecayTime, "caverns ring longer than tunnels")
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
                local tier = (Kit.chunk(Configs.Zones[1].Kit, id) or {}).Tier or 1
                if def.Kind == "Tunnel" and tier < 3 then
                    T.truthy(speed(0) > need, id .. ": easy and medium washouts clear at cruise speed")
                end
            end
        end
        T.truthy(count >= 2, "expected the washout and the rift")
    end)

    T.it("makes every junction a straight hall with room for its lanes", function()
        local count = 0
        for id, def in pieces do
            local split = def.Split
            if split then
                count += 1
                T.equal(def.Kind, "Tunnel", id)
                T.equal(def.Turn, 0, id .. " junctions are straight")
                T.falsy(def.Gap, id .. " a junction isn't a jump too")
                T.truthy(split.From >= 16, id .. " needs track before the switch to read the signals")
                T.truthy(split.From + split.Ramp <= split.Buffer, id .. " lanes are apart before the buffers")
                T.truthy(split.Buffer <= split.To - split.Ramp, id .. " the open lane rejoins after the buffers")
                T.truthy(split.To <= def.Length, id .. " rejoins inside the chunk")
                T.truthy(split.Offset >= 7, id .. " lanes far enough apart for the cart")
            end
        end
        T.truthy(count >= 2, "expected the junctions")
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
