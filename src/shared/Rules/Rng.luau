--!strict
-- Seeded random numbers (MINSTD). `state * 48271 % 2147483647` stays exact below 2^53 (TRAPS #32),
-- so a route rolled from a seed comes out the same in Lune tests and in Roblox.

local MODULUS = 2147483647
local MULTIPLIER = 48271

export type Rng = { state: number }

local Rng = {}

function Rng.new(seed: number): Rng
    local state = math.floor(math.abs(seed)) % MODULUS
    if state == 0 then
        state = 1
    end
    return { state = state }
end

-- A number in [0, 1).
function Rng.float(rng: Rng): number
    rng.state = (rng.state * MULTIPLIER) % MODULUS
    return (rng.state - 1) / (MODULUS - 1)
end

-- A whole number from low to high, both included.
function Rng.int(rng: Rng, low: number, high: number): number
    return low + math.floor(Rng.float(rng) * (high - low + 1))
end

-- A number from low up to (not including) high.
function Rng.range(rng: Rng, low: number, high: number): number
    return low + Rng.float(rng) * (high - low)
end

function Rng.pick<T>(rng: Rng, list: { T }): T
    assert(#list > 0, "Rng.pick needs a non-empty list")
    return list[Rng.int(rng, 1, #list)]
end

-- A shuffled copy (Fisher-Yates). The original list is left alone.
function Rng.shuffle<T>(rng: Rng, list: { T }): { T }
    local copy = table.clone(list)
    for i = #copy, 2, -1 do
        local j = Rng.int(rng, 1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

return Rng
