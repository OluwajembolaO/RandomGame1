local T = require("./lib/T")
local Configs = require("../src/shared/Configs")
local Rng = require("../src/shared/Rules/Rng")
local Upgrades = require("../src/shared/Rules/Upgrades")

local pool = Configs.Upgrades
local base = Upgrades.baseStats(Configs)

T.describe("Upgrades", function()
    T.it("offers three different upgrades", function()
        for seed = 1, 50 do
            local offer = Upgrades.roll(Rng.new(seed), pool, {}, 3)
            T.equal(#offer, 3)
            T.truthy(offer[1] ~= offer[2] and offer[2] ~= offer[3] and offer[1] ~= offer[3], "seed " .. seed)
        end
    end)

    T.it("never offers a maxed-out upgrade", function()
        local owned = {}
        for _, upgrade in pool do
            owned[upgrade.Id] = upgrade.Max
        end
        owned[pool[1].Id] = 0
        local offer = Upgrades.roll(Rng.new(1), pool, owned, 3)
        T.equal(#offer, 1)
        T.equal(offer[1], pool[1].Id)
    end)

    T.it("grants up to Max stacks", function()
        local owned = {}
        local first = pool[1]
        for _ = 1, first.Max do
            T.truthy(Upgrades.grant(pool, owned, first.Id))
        end
        T.falsy(Upgrades.grant(pool, owned, first.Id), "past Max")
        T.falsy(Upgrades.grant(pool, owned, "NoSuchUpgrade"), "unknown")
    end)

    T.it("applies adds, then multipliers, per stack", function()
        local stats = Upgrades.apply(base, pool, { ReinforcedFrame = 2, RapidRivets = 2 })
        T.near(stats.CartMaxHp, base.CartMaxHp + 120)
        T.near(stats.RivetCooldown, base.RivetCooldown * 0.8 * 0.8)
        T.near(stats.RivetDamage, base.RivetDamage, 1e-9, "untouched stats stay")
    end)

    T.it("catches broken upgrade configs", function()
        local function broken(effects, max)
            return { { Id = "X", Name = "X", Description = "", Max = max or 1, Effects = effects } }
        end
        T.falsy((Upgrades.validate(broken({ { Stat = "Nope", Add = 1 } }), base)), "unknown stat")
        T.falsy((Upgrades.validate(broken({ { Stat = "SpikeDps" } }), base)), "no Add or Mult")
        T.falsy((Upgrades.validate(broken({ { Stat = "SpikeDps", Add = 1, Mult = 2 } }), base)), "both")
        T.falsy((Upgrades.validate(broken({ { Stat = "SpikeDps", Add = 1 } }, 0), base)), "Max 0")
        T.falsy((Upgrades.validate(broken({}), base)), "no effects")
    end)
end)
