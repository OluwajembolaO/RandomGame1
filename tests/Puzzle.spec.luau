local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Puzzle = require("../src/shared/Rules/Puzzle")
local Rng = require("../src/shared/Rules/Rng")

local stage = Configs.Stages.SignalRoom

local function slotsSeen(assignment)
    local seen = {}
    for _, slots in assignment.clues do
        for _, slot in slots do
            seen[slot] = (seen[slot] or 0) + 1
        end
    end
    return seen
end

T.describe("Puzzle", function()
    T.it("rolls a code of different symbols", function()
        for seed = 1, 50 do
            local code = Puzzle.code(Rng.new(seed), #stage.Symbols, stage.CodeLength)
            T.equal(#code, stage.CodeLength)
            local seen = {}
            for _, symbol in code do
                T.falsy(seen[symbol], "repeated symbol")
                seen[symbol] = true
                T.truthy(symbol >= 1 and symbol <= #stage.Symbols)
            end
        end
    end)

    T.it("splits every clue to exactly one non-keypad player", function()
        for crew = 2, 4 do
            local players = {}
            for i = 1, crew do
                players[i] = 1000 + i
            end
            local assignment = Puzzle.assign(Rng.new(crew), players, stage.CodeLength)
            T.equal(assignment.clues[assignment.keypad], nil, "keypad player sees no clues")
            local seen = slotsSeen(assignment)
            for slot = 1, stage.CodeLength do
                T.equal(seen[slot], 1, crew .. " players, slot " .. slot)
            end
        end
    end)

    T.it("gives a solo player everything", function()
        local assignment = Puzzle.assign(Rng.new(1), { 77 }, stage.CodeLength)
        T.equal(assignment.keypad, 77)
        T.equal(#assignment.clues[77], stage.CodeLength)
    end)

    T.it("checks the entered code", function()
        T.truthy(Puzzle.check({ 3, 1, 4, 2 }, { 3, 1, 4, 2 }))
        T.falsy(Puzzle.check({ 3, 1, 4, 2 }, { 3, 1, 2, 4 }))
        T.falsy(Puzzle.check({ 3, 1, 4, 2 }, { 3, 1, 4 }))
    end)
end)
