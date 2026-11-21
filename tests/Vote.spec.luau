local T = require("./lib/T")
local Rng = require("../src/shared/Rules/Rng")
local Vote = require("../src/shared/Rules/Vote")

T.describe("Vote", function()
    T.it("counts valid votes only", function()
        local counts = Vote.counts({ [1] = 1, [2] = 2, [3] = 2, [4] = 9, [5] = 1.5 }, 3)
        T.equal(counts[1], 1)
        T.equal(counts[2], 2)
        T.equal(counts[3], 0)
    end)

    T.it("is decided by a majority or when everyone has voted", function()
        T.truthy(Vote.decided({ [1] = 2, [2] = 2 }, 3, 3), "2 of 3 is a majority")
        T.falsy(Vote.decided({ [1] = 1, [2] = 2 }, 3, 4), "split, two still to vote")
        T.truthy(Vote.decided({ [1] = 1, [2] = 2 }, 3, 2), "everyone voted")
        T.falsy(Vote.decided({}, 3, 0), "nobody to vote")
    end)

    T.it("picks the most votes", function()
        T.equal(Vote.winner({ [1] = 3, [2] = 3, [3] = 1 }, 3, Rng.new(1)), 3)
    end)

    T.it("breaks ties between the tied options only", function()
        for seed = 1, 50 do
            local winner = Vote.winner({ [1] = 1, [2] = 3 }, 3, Rng.new(seed))
            T.truthy(winner == 1 or winner == 3, "seed " .. seed)
        end
    end)

    T.it("still picks an option when nobody votes", function()
        local winner = Vote.winner({}, 2, Rng.new(8))
        T.truthy(winner == 1 or winner == 2)
    end)
end)
