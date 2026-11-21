local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Kit = require("../src/shared/Rules/Kit")
local Rng = require("../src/shared/Rules/Rng")

local pieces = Configs.Kit.Pieces
local zone = Configs.Zones[1]
local spec = zone.Kit

local function leg(seed: number, length: number?)
    return Kit.leg(Rng.new(seed), pieces, spec, length or 1300, 0, 0)
end

local function count(sequence, kind: string?, sharp: boolean?): number
    local n = 0
    for _, id in sequence do
        local def = pieces[id]
        if (kind == nil or def.Kind == kind) and (sharp == nil or def.Sharp == sharp) then
            n += 1
        end
    end
    return n
end

T.describe("Kit", function()
    T.it("rolls rideable legs for every seed", function()
        for seed = 1, 200 do
            local ok, problem = Kit.check(leg(seed), pieces, spec, 0, 0)
            T.truthy(ok, "seed " .. seed .. ": " .. tostring(problem))
        end
    end)

    T.it("puts a cavern and a sharp bend on every prototype leg", function()
        for seed = 1, 200 do
            for _, legSpec in zone.Legs do
                local sequence = Kit.leg(Rng.new(seed), pieces, spec, legSpec.Ride.Length, 0, 0)
                T.truthy(count(sequence, "Cavern") >= 1, "seed " .. seed .. " has no cavern")
                T.truthy(count(sequence, nil, true) >= 1, "seed " .. seed .. " has no sharp bend")
            end
        end
    end)

    T.it("lands close to the requested length", function()
        for seed = 1, 100 do
            local total = 0
            for _, id in leg(seed) do
                total += pieces[id].Length
            end
            T.truthy(total >= 1300 - pieces[spec.Straight].Length / 2, "seed " .. seed .. " too short: " .. total)
            T.truthy(total <= 1300 + 224, "seed " .. seed .. " too long: " .. total)
        end
    end)

    T.it("never rides the same cavern twice in a row", function()
        for seed = 1, 100 do
            local last = nil
            for _, id in leg(seed, 3000) do
                if pieces[id].Kind == "Cavern" then
                    T.truthy(id ~= last, "seed " .. seed .. " repeats " .. id)
                    last = id
                end
            end
        end
    end)

    T.it("is the same for the same seed", function()
        T.equal(table.concat(leg(42), ","), table.concat(leg(42), ","))
    end)

    T.it("maps a kit piece onto the track piece it was modeled on", function()
        local bend = Kit.trackPiece(pieces.Tunnel_BendR)
        T.equal(bend.kind, "Curve")
        T.equal(bend.length, pieces.Tunnel_BendR.Length)
        T.near(bend.grade, pieces.Tunnel_BendR.Drop / pieces.Tunnel_BendR.Length)
        T.truthy(bend.turn > 0, "a right bend turns right")
        T.truthy(Kit.trackPiece(pieces.Tunnel_SharpL).sharp, "sharp bends are sharp")
    end)

    T.it("catches broken legs", function()
        local straight, bend = spec.Straight, "Tunnel_BendR"
        T.falsy((Kit.check({}, pieces, spec, 0, 0)), "empty")
        T.falsy((Kit.check({ straight, "Nope", straight }, pieces, spec, 0, 0)), "unknown piece")
        T.falsy(
            (Kit.check({ straight, straight, bend, bend, bend, straight, straight }, pieces, spec, 0, 0)),
            "overturns"
        )
        T.falsy((Kit.check({ "Cavern_Lake", straight, straight, straight }, pieces, spec, 0, 0)), "cavern at the start")
        local touching = { straight, straight, "Cavern_Lake", "Cavern_Chasm", straight, straight }
        T.falsy((Kit.check(touching, pieces, spec, 0, 0)), "touching caverns")
        T.falsy(
            (Kit.check({ straight, straight, "Station", straight, straight }, pieces, spec, 0, 0)),
            "station in a leg"
        )
    end)
end)
