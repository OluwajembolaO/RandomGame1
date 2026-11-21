--!strict
-- Run upgrades: rolling offers, granting picks, and applying stacks to the run's stats.

local Rng = require("./Rng")

export type Effect = { Stat: string, Add: number?, Mult: number? }
export type Upgrade = { Id: string, Name: string, Description: string, Max: number, Effects: { Effect } }
export type Owned = { [string]: number }
export type Stats = { [string]: number }

local Upgrades = {}

-- The stats upgrades can change, before any upgrades.
function Upgrades.baseStats(configs: any): Stats
    return {
        CartMaxHp = configs.Run.Cart.MaxHp,
        ChewArmor = 1,
        BrakeSeconds = configs.Run.Cart.BrakeSeconds,
        ReviveSeconds = configs.Run.Crew.ReviveSeconds,
        RivetCooldown = configs.Weapons.RivetGun.Cooldown,
        RivetDamage = configs.Weapons.RivetGun.Damage,
        HeadlampRange = configs.Run.Cart.HeadlampRange,
        SpikeDps = 0,
    }
end

function Upgrades.find(pool: { Upgrade }, id: string): Upgrade?
    for _, upgrade in pool do
        if upgrade.Id == id then
            return upgrade
        end
    end
    return nil
end

-- Up to `count` different upgrades the crew doesn't have maxed out yet.
function Upgrades.roll(rng: Rng.Rng, pool: { Upgrade }, owned: Owned, count: number): { string }
    local open = {}
    for _, upgrade in pool do
        if (owned[upgrade.Id] or 0) < upgrade.Max then
            table.insert(open, upgrade.Id)
        end
    end
    local shuffled = Rng.shuffle(rng, open)
    return table.move(shuffled, 1, math.min(count, #shuffled), 1, {})
end

-- Adds one stack. Returns false for unknown or maxed-out upgrades.
function Upgrades.grant(pool: { Upgrade }, owned: Owned, id: string): boolean
    local upgrade = Upgrades.find(pool, id)
    if not upgrade or (owned[id] or 0) >= upgrade.Max then
        return false
    end
    owned[id] = (owned[id] or 0) + 1
    return true
end

-- Base stats with every owned stack applied: all Adds first, then all Mults.
function Upgrades.apply(base: Stats, pool: { Upgrade }, owned: Owned): Stats
    local adds: Stats = {}
    local mults: Stats = {}
    for id, stacks in owned do
        local upgrade = Upgrades.find(pool, id)
        if upgrade then
            for _, effect in upgrade.Effects do
                if effect.Add then
                    adds[effect.Stat] = (adds[effect.Stat] or 0) + effect.Add * stacks
                end
                if effect.Mult then
                    mults[effect.Stat] = (mults[effect.Stat] or 1) * effect.Mult ^ stacks
                end
            end
        end
    end
    local result: Stats = {}
    for stat, value in base do
        result[stat] = (value + (adds[stat] or 0)) * (mults[stat] or 1)
    end
    return result
end

-- Every upgrade has a unique id, a positive Max, and effects that each change a known stat
-- with exactly one of Add or Mult.
function Upgrades.validate(pool: { Upgrade }, base: Stats): (boolean, string?)
    local seen = {}
    for _, upgrade in pool do
        if seen[upgrade.Id] then
            return false, "duplicate upgrade " .. upgrade.Id
        end
        seen[upgrade.Id] = true
        if upgrade.Max < 1 then
            return false, upgrade.Id .. " has Max below 1"
        end
        if #upgrade.Effects == 0 then
            return false, upgrade.Id .. " has no effects"
        end
        for _, effect in upgrade.Effects do
            if base[effect.Stat] == nil then
                return false, upgrade.Id .. " changes unknown stat " .. effect.Stat
            end
            if (effect.Add == nil) == (effect.Mult == nil) then
                return false, upgrade.Id .. " effect needs exactly one of Add or Mult"
            end
        end
    end
    return true, nil
end

return Upgrades
