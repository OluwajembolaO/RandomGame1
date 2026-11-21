--!strict
-- The cave kit: Blender-made pieces (Config/KitData, from art/blender/build_cave_kit.py) snapped end to end.
-- A leg's pieces are rolled from a seed: tunnel straights and bends, a sharp bend every few pieces, and a
-- big cavern every so often, never turning further than MaxHeading from the zone's heading (so the route
-- can't cross itself). Every piece is modeled around the exact track Track.build makes from it.

local Rng = require("./Rng")
local Track = require("./Track")

-- A KitData piece. Kind is "Station", "Stop", "Tunnel", "Cavern" or "Cap" (TRAPS #19).
export type PieceDef = { Kind: string, Length: number, Turn: number, Drop: number, Sharp: boolean }
export type Pieces = { [string]: PieceDef }

-- A zone's Kit config.
export type Spec = {
    Station: string,
    Stop: string,
    Cap: string,
    Straight: string,
    Bends: { string },
    Sharps: { string },
    Caverns: { string },
    CavernGap: { number },
    EdgeTunnels: number,
    SharpEvery: { number },
    StraightChance: number,
    MaxHeading: number,
}

local Kit = {}

-- The track piece a kit piece is modeled around.
function Kit.trackPiece(def: PieceDef): Track.Piece
    return {
        kind = if def.Turn == 0 then "Straight" else "Curve",
        length = def.Length,
        turn = def.Turn,
        grade = if def.Length > 0 then def.Drop / def.Length else 0,
        sharp = def.Sharp,
    }
end

local function fits(def: PieceDef, heading: number, base: number, limit: number): boolean
    return math.abs(heading + def.Turn - base) <= limit + 1e-9
end

local function fitting(ids: { string }, pieces: Pieces, heading: number, base: number, limit: number): { string }
    local list = {}
    for _, id in ids do
        if fits(pieces[id], heading, base, limit) then
            table.insert(list, id)
        end
    end
    return list
end

-- The pieces for one ride leg of about `length` studs, starting at `heading`.
function Kit.leg(rng: Rng.Rng, pieces: Pieces, spec: Spec, length: number, heading: number, base: number): { string }
    local sequence: { string } = {}
    local total = 0
    local tunnel = pieces[spec.Straight].Length
    local edge = spec.EdgeTunnels * tunnel
    local untilCavern = Rng.range(rng, spec.CavernGap[1], spec.CavernGap[2]) / 2
    local untilSharp = Rng.int(rng, spec.SharpEvery[1], spec.SharpEvery[2])
    local lastCavern: string? = nil

    local function add(id: string)
        table.insert(sequence, id)
        total += pieces[id].Length
        heading += pieces[id].Turn
    end

    while total < length - tunnel / 2 do
        local remaining = length - total
        local placed = false
        -- A cavern, once it's time, with tunnel to spare at both ends of the leg, never the same one twice running.
        if total >= edge and untilCavern <= 0 then
            local options = {}
            for _, id in fitting(spec.Caverns, pieces, heading, base, spec.MaxHeading) do
                if id ~= lastCavern and remaining - pieces[id].Length >= edge then
                    table.insert(options, id)
                end
            end
            if #options > 0 then
                local id = Rng.pick(rng, options)
                add(id)
                lastCavern = id
                untilCavern = Rng.range(rng, spec.CavernGap[1], spec.CavernGap[2])
                placed = true
            end
        end
        if not placed then
            local choice: string? = nil
            untilSharp -= 1
            if untilSharp <= 0 then
                local sharps = fitting(spec.Sharps, pieces, heading, base, spec.MaxHeading)
                if #sharps > 0 then
                    choice = Rng.pick(rng, sharps)
                    untilSharp = Rng.int(rng, spec.SharpEvery[1], spec.SharpEvery[2])
                end
            end
            if not choice and Rng.float(rng) >= spec.StraightChance then
                local bends = fitting(spec.Bends, pieces, heading, base, spec.MaxHeading)
                if #bends > 0 then
                    choice = Rng.pick(rng, bends)
                end
            end
            local id = choice or spec.Straight
            add(id)
            untilCavern -= pieces[id].Length
        end
    end
    return sequence
end

-- A leg is rideable when every piece exists, the heading never leaves base +/- MaxHeading, the first and last
-- EdgeTunnels pieces are tunnels, and no two caverns touch.
function Kit.check(sequence: { string }, pieces: Pieces, spec: Spec, heading: number, base: number): (boolean, string?)
    if #sequence == 0 then
        return false, "leg has no pieces"
    end
    for index, id in sequence do
        local def = pieces[id]
        if not def then
            return false, "unknown piece " .. id
        end
        -- Plain booleans: comparing Kind repeatedly trips the old type solver's narrowing.
        local isTunnel = def.Kind == "Tunnel"
        local isCavern = def.Kind == "Cavern"
        if not isTunnel and not isCavern then
            return false, id .. " (" .. def.Kind .. ") can't be part of a leg"
        end
        heading += def.Turn
        if math.abs(heading - base) > spec.MaxHeading + 1e-9 then
            return false, "heading leaves the limit at piece " .. index
        end
        local nearEnd = index <= spec.EdgeTunnels or index > #sequence - spec.EdgeTunnels
        if nearEnd and not isTunnel then
            return false, "piece " .. index .. " is a " .. def.Kind .. " too close to the end of the leg"
        end
        local previous = sequence[index - 1]
        local afterCavern = previous ~= nil and pieces[previous].Kind == "Cavern"
        if isCavern and afterCavern then
            return false, "caverns touch at piece " .. index
        end
    end
    return true, nil
end

return Kit
