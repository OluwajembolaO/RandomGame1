--!strict
-- The Signal Room: the door code, and who sees what. One player gets the keypad and everyone else
-- splits the clues, so nobody can open the door alone (except when playing solo).

local Rng = require("./Rng")

-- clues maps a UserId to the code slots (1-based) that player can see.
export type Assignment = { keypad: number, clues: { [number]: { number } } }

local Puzzle = {}

-- `length` different symbols, as indexes into the stage's symbol list.
function Puzzle.code(rng: Rng.Rng, symbolCount: number, length: number): { number }
    assert(length <= symbolCount, "the code can't be longer than the symbol list")
    local symbols = {}
    for i = 1, symbolCount do
        symbols[i] = i
    end
    return table.move(Rng.shuffle(rng, symbols), 1, length, 1, {})
end

function Puzzle.assign(rng: Rng.Rng, players: { number }, length: number): Assignment
    assert(#players > 0, "the Signal Room needs at least one player")
    local sorted = table.clone(players)
    table.sort(sorted)
    local keypad = Rng.pick(rng, sorted)
    local others = {}
    for _, id in sorted do
        if id ~= keypad then
            table.insert(others, id)
        end
    end
    local clues: { [number]: { number } } = {}
    if #others == 0 then
        local all = {}
        for slot = 1, length do
            all[slot] = slot
        end
        clues[keypad] = all
        return { keypad = keypad, clues = clues }
    end
    others = Rng.shuffle(rng, others)
    for slot = 1, length do
        local id = others[(slot - 1) % #others + 1]
        clues[id] = clues[id] or {}
        table.insert(clues[id], slot)
    end
    return { keypad = keypad, clues = clues }
end

function Puzzle.check(code: { number }, entry: { number }): boolean
    if #entry ~= #code then
        return false
    end
    for i, symbol in code do
        if entry[i] ~= symbol then
            return false
        end
    end
    return true
end

return Puzzle
