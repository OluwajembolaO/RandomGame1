local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Kit = require("../src/shared/Rules/Kit")
local Rng = require("../src/shared/Rules/Rng")

local pieces = Configs.Kit.Pieces
local zone = Configs.Zones[1]
local spec = zone.Kit

local function leg(seed: number, count: number?)
    return Kit.leg(Rng.new(seed), pieces, spec, count or 10, 0, 0)
end

local function tagOf(id: string): string?
    local chunk = Kit.chunk(spec, id)
    return chunk and chunk.Tag
end

local function count(sequence, tag: string): number
    local n = 0
    for _, id in sequence do
        if tagOf(id) == tag then
            n += 1
        end
    end
    return n
end

T.describe("Kit", function()
    T.it("rolls rideable legs of exactly the asked number of segments for every seed", function()
        for seed = 1, 300 do
            for _, size in { 10, 14, 30 } do
                local sequence = leg(seed, size)
                T.equal(#sequence, size, "seed " .. seed)
                local ok, problem = Kit.check(sequence, pieces, spec, 0, 0)
                T.truthy(ok, "seed " .. seed .. " x" .. size .. ": " .. tostring(problem))
            end
        end
    end)

    T.it("puts a cavern and a sharp bend on every prototype leg", function()
        for seed = 1, 300 do
            for _, legSpec in zone.Legs do
                local sequence = leg(seed, legSpec.Ride.Segments)
                T.truthy(count(sequence, "Cavern") >= 1, "seed " .. seed .. " has no cavern")
                T.truthy(count(sequence, "Sharp") >= 1, "seed " .. seed .. " has no sharp bend")
            end
        end
    end)

    T.it("keeps each kind of chunk spaced out", function()
        for seed = 1, 100 do
            local last: { [string]: number } = {}
            for index, id in leg(seed, 30) do
                local tag = tagOf(id)
                local rule = tag and spec.Tags[tag]
                if tag and rule then
                    if last[tag] then
                        T.truthy(index - last[tag] > rule.Spacing[1] - 1, "seed " .. seed .. " " .. tag .. " too close")
                    end
                    last[tag] = index
                end
            end
        end
    end)

    T.it("puts every jump straight after a straight run-up, and no sharp bend straight after", function()
        local seen = 0
        for seed = 1, 300 do
            local sequence = leg(seed, 30)
            for index, id in sequence do
                if tagOf(id) == "Gap" then
                    seen += 1
                    local previous = sequence[index - 1]
                    T.equal(pieces[previous].Turn, 0, "seed " .. seed .. " run-up must be straight")
                    T.falsy(pieces[previous].Gap, "seed " .. seed .. " a jump straight into another")
                    T.truthy(tagOf(sequence[index + 1]) ~= "Sharp", "seed " .. seed .. " sharp after a jump")
                end
            end
        end
        T.truthy(seen >= 300, "expected jumps regularly, saw " .. seen)
    end)

    T.it("never rides the same cavern twice in a row", function()
        for seed = 1, 100 do
            local last = nil
            for _, id in leg(seed, 30) do
                if tagOf(id) == "Cavern" then
                    T.truthy(id ~= last, "seed " .. seed .. " repeats " .. id)
                    last = id
                end
            end
        end
    end)

    T.it("draws chunks by weight", function()
        local tally: { [string]: number } = {}
        local total = 0
        for seed = 1, 400 do
            for _, id in leg(seed, 30) do
                tally[id] = (tally[id] or 0) + 1
                total += 1
            end
        end
        for _, chunk in spec.Chunks do
            T.truthy((tally[chunk.Id] or 0) > 0, chunk.Id .. " never turned up")
        end
        T.truthy(tally.Tunnel_BendL > tally.Tunnel_SharpL, "bends are commoner than sharp bends")
        T.truthy(tally[spec.Straight] / total < 0.5, "straights don't swamp the cave")
    end)

    T.it("is the same for the same seed, and differs between seeds", function()
        T.equal(table.concat(leg(42, 30), ","), table.concat(leg(42, 30), ","))
        T.truthy(table.concat(leg(42, 30), ",") ~= table.concat(leg(43, 30), ","))
    end)

    T.it("maps a kit piece onto the track piece it was modeled on", function()
        local bend = Kit.trackPiece(pieces.Tunnel_BendR)
        T.equal(bend.kind, "Curve")
        T.equal(bend.length, pieces.Tunnel_BendR.Length)
        T.near(bend.grade, pieces.Tunnel_BendR.Drop / pieces.Tunnel_BendR.Length)
        T.truthy(bend.turn > 0, "a right bend turns right")
        T.truthy(Kit.trackPiece(pieces.Tunnel_SharpL).sharp, "sharp bends are sharp")
        local washout = Kit.trackPiece(pieces.Tunnel_Washout)
        local gap = washout.gap :: any
        T.near(washout.grade, (pieces.Tunnel_Washout.Drop - gap.drop) / pieces.Tunnel_Washout.Length, 1e-12)
        T.equal(Kit.trackPiece(pieces.Tunnel_Straight).gap, nil)
    end)

    T.it("catches broken legs", function()
        local S, sharp, bend = spec.Straight, "Tunnel_SharpR", "Tunnel_BendR"
        local function bad(sequence, why)
            T.falsy((Kit.check(sequence, pieces, spec, 0, 0)), why)
        end
        local good = { S, S, sharp, S, "Cavern_Lake", S, S, S, S, S }
        T.truthy((Kit.check(good, pieces, spec, 0, 0)), "a fine leg passes")
        bad({}, "empty")
        bad({ S, S, sharp, "Nope", "Cavern_Lake", S, S, S }, "unknown chunk")
        bad({ S, S, bend, bend, bend, sharp, "Cavern_Lake", S, S }, "overturns")
        bad({ "Cavern_Lake", S, sharp, S, S, S, S, S }, "cavern at the start")
        bad({ S, S, sharp, "Cavern_Lake", "Cavern_Chasm", S, S, S }, "caverns too close")
        bad({ S, S, sharp, bend, "Tunnel_Washout", "Cavern_Lake", S, S, S, S }, "washout without a run-up")
        bad({ S, S, "Cavern_Lake", S, S, "Tunnel_Washout", sharp, S, S, S }, "sharp straight after a jump")
        bad({ S, S, S, S, "Cavern_Lake", S, S, S, S, S }, "no sharp bend")
        bad({ S, S, sharp, S, S, S, S, S, S, S }, "no cavern")
        bad({ S, S, sharp, S, "Station", S, "Cavern_Lake", S, S, S }, "station in a leg")
    end)
end)
