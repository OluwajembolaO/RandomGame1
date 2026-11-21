--!strict
-- Crew health with a downed state. A hit that would kill downs you instead; a teammate can revive you
-- (the bleed-out timer pauses while they do); bleeding out means you're out until the next stop.

-- status is "Alive", "Downed" or "Dead" (TRAPS #19).
export type Member = { status: string, health: number, bleed: number }
export type Stats = { MaxHealth: number, BleedOutSeconds: number, ReviveHealthFraction: number }

local Downed = {}

function Downed.new(stats: Stats): Member
    return { status = "Alive", health = stats.MaxHealth, bleed = 0 }
end

-- Returns true when this hit downed them. Hits on downed or dead members do nothing.
function Downed.damage(member: Member, stats: Stats, amount: number): boolean
    if member.status ~= "Alive" or amount <= 0 then
        return false
    end
    member.health -= amount
    if member.health > 0 then
        return false
    end
    member.status = "Downed"
    member.health = 0
    member.bleed = stats.BleedOutSeconds
    return true
end

function Downed.heal(member: Member, stats: Stats, amount: number)
    if member.status == "Alive" then
        member.health = math.min(stats.MaxHealth, member.health + math.max(0, amount))
    end
end

-- Runs the bleed-out timer. Returns true when they bled out this tick.
function Downed.tick(member: Member, dt: number, beingRevived: boolean): boolean
    if member.status ~= "Downed" or beingRevived then
        return false
    end
    member.bleed = math.max(0, member.bleed - dt)
    if member.bleed > 0 then
        return false
    end
    member.status = "Dead"
    return true
end

-- A teammate finished reviving them. Returns false if they weren't downed.
function Downed.revive(member: Member, stats: Stats): boolean
    if member.status ~= "Downed" then
        return false
    end
    member.status = "Alive"
    member.health = math.max(1, stats.MaxHealth * stats.ReviveHealthFraction)
    member.bleed = 0
    return true
end

-- Out for good this stop (fell into the void, or the character was removed).
function Downed.kill(member: Member)
    member.status = "Dead"
    member.health = 0
    member.bleed = 0
end

function Downed.respawn(member: Member, stats: Stats)
    member.status = "Alive"
    member.health = stats.MaxHealth
    member.bleed = 0
end

-- True when nobody in a non-empty crew is still standing.
function Downed.isWipe(members: { Member }): boolean
    if #members == 0 then
        return false
    end
    for _, member in members do
        if member.status == "Alive" then
            return false
        end
    end
    return true
end

return Downed
