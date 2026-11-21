--!strict
-- Crew votes (fork branches, upgrades). Votes are keyed by UserId; values are option indexes.

local Rng = require("./Rng")

export type Votes = { [number]: number }

local Vote = {}

-- Votes per option. Out-of-range or fractional votes are ignored.
function Vote.counts(votes: Votes, optionCount: number): { number }
    local counts = table.create(optionCount, 0)
    for _, option in votes do
        if option >= 1 and option <= optionCount and option % 1 == 0 then
            counts[option] += 1
        end
    end
    return counts
end

-- True once everyone has voted, or one option has more than half of all voters.
function Vote.decided(votes: Votes, optionCount: number, voterCount: number): boolean
    if voterCount <= 0 then
        return false
    end
    local cast = 0
    for _, count in Vote.counts(votes, optionCount) do
        if count * 2 > voterCount then
            return true
        end
        cast += count
    end
    return cast >= voterCount
end

-- The option with the most votes. Ties, and no votes at all, are broken by the seeded rng.
function Vote.winner(votes: Votes, optionCount: number, rng: Rng.Rng): number
    local best = -1
    local tied: { number } = {}
    for option, count in Vote.counts(votes, optionCount) do
        if count > best then
            best = count
            tied = { option }
        elseif count == best then
            table.insert(tied, option)
        end
    end
    return if #tied == 1 then tied[1] else Rng.pick(rng, tied)
end

return Vote
