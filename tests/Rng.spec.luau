local T = require("./lib/T")
local Rng = require("../src/shared/Rules/Rng")

T.describe("Rng", function()
    T.it("repeats for the same seed", function()
        local a, b = Rng.new(42), Rng.new(42)
        for _ = 1, 20 do
            T.equal(Rng.float(a), Rng.float(b))
        end
    end)

    T.it("stays in range", function()
        local rng = Rng.new(7)
        for _ = 1, 2000 do
            local f = Rng.float(rng)
            T.truthy(f >= 0 and f < 1, "float " .. f)
            local i = Rng.int(rng, 3, 5)
            T.truthy(i >= 3 and i <= 5 and i % 1 == 0, "int " .. i)
        end
    end)

    T.it("survives a zero or huge seed", function()
        T.truthy(Rng.float(Rng.new(0)) >= 0)
        T.truthy(Rng.float(Rng.new(2 ^ 40)) >= 0)
    end)

    T.it("shuffles a copy without losing items", function()
        local list = { 1, 2, 3, 4, 5 }
        local shuffled = Rng.shuffle(Rng.new(3), list)
        T.equal(#shuffled, 5)
        T.equal(list[1], 1, "original untouched")
        table.sort(shuffled)
        for i = 1, 5 do
            T.equal(shuffled[i], i)
        end
    end)
end)
