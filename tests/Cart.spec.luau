local T = require("./lib/T")
local Cart = require("../src/shared/Rules/Cart")
local Configs = require("../src/shared/Configs")
local Upgrades = require("../src/shared/Rules/Upgrades")

local stats = Cart.stats(Configs.Run.Cart, Upgrades.baseStats(Configs))
local ROLLING = { moving = true, sharp = false, chewers = 0, chewDps = 0 }

local function run(cart, seconds: number, conditions)
    local damage = 0
    for _ = 1, math.round(seconds * 60) do
        damage += Cart.step(cart, stats, 1 / 60, conditions)
    end
    return damage
end

T.describe("Cart", function()
    T.it("starts full and still", function()
        local cart = Cart.new(stats)
        T.equal(cart.hp, stats.MaxHp)
        T.equal(cart.speed, 0)
    end)

    T.it("accelerates up to its speed and no further", function()
        local cart = Cart.new(stats)
        run(cart, 10, ROLLING)
        T.near(cart.speed, stats.Speed, 1e-6)
    end)

    T.it("slows to brake speed, then the brake releases and cools down", function()
        local cart = Cart.new(stats)
        run(cart, 10, ROLLING)
        T.truthy(Cart.pullBrake(cart, stats), "brake pulls")
        T.falsy(Cart.pullBrake(cart, stats), "can't pull twice")
        run(cart, 3, ROLLING)
        T.near(cart.speed, stats.Speed * stats.BrakeFactor, 1e-6)
        run(cart, stats.BrakeSeconds - 3 + 0.1, ROLLING)
        T.falsy(Cart.braking(cart), "brake released")
        T.falsy(Cart.pullBrake(cart, stats), "cooling down")
        run(cart, stats.BrakeCooldown + 0.1, ROLLING)
        T.truthy(Cart.pullBrake(cart, stats), "ready again")
    end)

    T.it("takes damage on a sharp curve at full speed, but not when braked", function()
        local sharp = { moving = true, sharp = true, chewers = 0, chewDps = 0 }
        local fast = Cart.new(stats)
        run(fast, 10, ROLLING)
        T.truthy(run(fast, 2, sharp) > 0, "full speed hurts")

        local braked = Cart.new(stats)
        run(braked, 10, ROLLING)
        Cart.pullBrake(braked, stats)
        run(braked, 1.5, ROLLING) -- brake before the curve
        T.near(run(braked, 2, sharp), 0, 1e-9)
    end)

    T.it("brakes to a safe speed through a sharp curve", function()
        T.truthy(stats.Speed * stats.BrakeFactor < stats.SafeCurveSpeed, "brake speed is safe")
        T.truthy(stats.Speed > stats.SafeCurveSpeed, "full speed is not")
    end)

    T.it("is chewed by crawlers, less with Chew Guard", function()
        local chewing = { moving = true, sharp = false, chewers = 2, chewDps = 5 }
        T.near(run(Cart.new(stats), 1, chewing), 10, 1e-6)
        local guarded = table.clone(stats)
        guarded.ChewArmor = 0.5
        local cart = Cart.new(guarded)
        local damage = 0
        for _ = 1, 60 do
            damage += Cart.step(cart, guarded, 1 / 60, chewing)
        end
        T.near(damage, 5, 1e-6)
    end)

    T.it("repairs up to max HP and is wrecked at zero", function()
        local cart = Cart.new(stats)
        Cart.damage(cart, 50)
        Cart.repair(cart, stats, 500)
        T.equal(cart.hp, stats.MaxHp)
        Cart.damage(cart, stats.MaxHp + 10)
        T.equal(cart.hp, 0)
        T.truthy(Cart.wrecked(cart))
    end)

    T.it("rolls to a stop at a station", function()
        local cart = Cart.new(stats)
        run(cart, 10, ROLLING)
        run(cart, 10, { moving = false, sharp = false, chewers = 0, chewDps = 0 })
        T.near(cart.speed, 0, 1e-6)
    end)
end)
