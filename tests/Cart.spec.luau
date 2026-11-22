local T = require("./lib/T")
local Cart = require("../src/shared/Rules/Cart")
local Configs = require("../src/shared/Configs")
local Upgrades = require("../src/shared/Rules/Upgrades")

local stats = Cart.stats(Configs.Run.Cart, Upgrades.baseStats(Configs))
local pieces = Configs.Kit.Pieces
local ROLLING = { moving = true, chewers = 0, chewDps = 0 }
local DT = 1 / 60

local function run(cart, seconds: number, conditions)
    local damage = 0
    for _ = 1, math.round(seconds * 60) do
        damage += Cart.step(cart, stats, DT, conditions)
    end
    return damage
end

local function on(id: string, curved: boolean)
    local def = pieces[id]
    return {
        moving = true,
        chewers = 0,
        chewDps = 0,
        grade = def.Drop / def.Length,
        curvature = if curved then def.Turn / def.Length else 0,
    }
end

-- Rolls up to cruise on straight tunnel, then through bend piece `id` with the crew holding `throttle` and
-- leaning `lean`. Returns whether the cart tipped over, and the most it tilted.
local function throughBend(id: string, throttle: number, lean: number): (boolean, number)
    local cart = Cart.new(stats)
    Cart.setThrottle(cart, throttle)
    if throttle < 0 then
        Cart.setThrottle(cart, 0)
        run(cart, 10, on("Tunnel_Straight", false))
        Cart.setThrottle(cart, -1)
        run(cart, 3, on("Tunnel_Straight", false)) -- braking well before the bend
    else
        run(cart, 10, on("Tunnel_Straight", false))
    end
    Cart.setLean(cart, lean)
    local conditions = on(id, true)
    local along, peak = 0, 0
    while along < pieces[id].Length and not Cart.tipped(cart) do
        Cart.step(cart, stats, DT, conditions)
        along += cart.speed * DT
        peak = math.max(peak, cart.tilt)
    end
    return Cart.tipped(cart), peak
end

T.describe("Cart", function()
    T.it("starts full, still and level", function()
        local cart = Cart.new(stats)
        T.equal(cart.hp, stats.MaxHp)
        T.equal(cart.speed, 0)
        T.equal(cart.tilt, 0)
    end)

    T.it("accelerates up to its speed and no further", function()
        local cart = Cart.new(stats)
        run(cart, 10, ROLLING)
        T.near(cart.speed, stats.Speed, 1e-6)
    end)

    T.it("slows to brake speed while the brake is held, for as long as it's held", function()
        local cart = Cart.new(stats)
        run(cart, 10, ROLLING)
        Cart.setThrottle(cart, -1)
        T.truthy(Cart.braking(cart), "braking")
        run(cart, 30, ROLLING)
        T.near(cart.speed, stats.Speed * stats.BrakeFactor, 1e-6)
        Cart.setThrottle(cart, 0)
        run(cart, 10, ROLLING)
        T.near(cart.speed, stats.Speed, 1e-6)
    end)

    T.it("runs faster while pushed", function()
        local cart = Cart.new(stats)
        Cart.setThrottle(cart, 1)
        T.truthy(Cart.pushing(cart))
        run(cart, 10, ROLLING)
        T.near(cart.speed, stats.Speed * stats.PushFactor, 1e-6)
        T.truthy(stats.PushFactor > 1, "pushing is faster than coasting")
    end)

    T.it("takes one throttle from the crew: anyone braking wins, then anyone pushing", function()
        T.equal(Cart.crewThrottle({}), 0)
        T.equal(Cart.crewThrottle({ 0, 0 }), 0)
        T.equal(Cart.crewThrottle({ 0, 1 }), 1)
        T.equal(Cart.crewThrottle({ 1, -1, 1 }), -1)
        local cart = Cart.new(stats)
        Cart.setThrottle(cart, 7)
        T.equal(cart.throttle, 1)
        Cart.setThrottle(cart, -0.4)
        T.equal(cart.throttle, 0)
        Cart.setThrottle(cart, 0 / 0)
        T.equal(cart.throttle, 0, "NaN coasts")
    end)

    T.it("leans as a crew: everyone has to lean for the full effect", function()
        T.equal(Cart.crewLean({}), 0)
        T.equal(Cart.crewLean({ 1 }), 1)
        T.equal(Cart.crewLean({ 1, 0, 0, 0 }), 0.25)
        T.equal(Cart.crewLean({ 1, -1 }), 0)
        T.equal(Cart.crewLean({ 5, 0 / 0 }), 0.5, "out-of-range and NaN leans are tamed")
        local cart = Cart.new(stats)
        Cart.setLean(cart, -3)
        T.equal(cart.lean, -1)
    end)

    T.it("takes a normal bend at cruise speed without tipping", function()
        local tipped, peak = throughBend("Tunnel_BendR", 0, 0)
        T.falsy(tipped)
        T.truthy(peak < 0.25, "barely lifts: " .. peak)
        T.falsy((throughBend("Tunnel_BendL", 0, 0)), "left bends too")
    end)

    T.it("tips over in a sharp bend at cruise speed, unless the crew leans into it", function()
        T.truthy((throughBend("Tunnel_SharpR", 0, 0)), "right")
        T.truthy((throughBend("Tunnel_SharpL", 0, 0)), "left")
        T.falsy((throughBend("Tunnel_SharpR", 0, 1)), "leaning right into a right bend")
        T.falsy((throughBend("Tunnel_SharpL", 0, -1)), "leaning left into a left bend")
    end)

    T.it("tips over leaning the wrong way, even in a normal bend", function()
        T.truthy((throughBend("Tunnel_BendR", 0, -1)))
        T.truthy((throughBend("Tunnel_BendL", 0, 1)))
    end)

    T.it("tips over pushing through a bend without leaning", function()
        T.truthy((throughBend("Tunnel_BendR", 1, 0)))
    end)

    T.it("never tips under the brake, not even in a sharp bend", function()
        local tipped, peak = throughBend("Tunnel_SharpR", -1, 0)
        T.falsy(tipped)
        T.equal(peak, 0)
    end)

    T.it("settles back onto all four wheels once under the limit", function()
        local cart = Cart.new(stats)
        cart.tilt = 0.6
        run(cart, 1, ROLLING)
        T.equal(cart.tilt, 0)
    end)

    T.it("takes bends harder with Wide Axles", function()
        local wide = table.clone(stats)
        wide.TipLimit *= 1.2
        T.near(Cart.tipLimit(wide, 0, 0.01), Cart.tipLimit(stats, 0, 0.01) * 1.2, 1e-9)
        T.truthy(Cart.tipLimit(stats, 1, 0.01) > Cart.tipLimit(stats, 0, 0.01), "leaning in helps")
        T.truthy(Cart.tipLimit(stats, -1, 0.01) < Cart.tipLimit(stats, 0, 0.01), "leaning out hurts")
        T.equal(Cart.tipLimit(stats, 1, 0), stats.TipLimit, "leaning does nothing on a straight")
    end)

    T.it("shows the crew's lean and the lift onto its outer wheels in the cart's roll", function()
        local cart = Cart.new(stats)
        T.near(Cart.roll(cart, stats, 0), 0)
        Cart.setLean(cart, 1)
        T.truthy(Cart.roll(cart, stats, 0) < 0, "leaning right tips the top right")
        Cart.setLean(cart, 0)
        cart.tilt = 1
        T.near(Cart.roll(cart, stats, 0.01), math.rad(stats.LiftMax), 1e-9, "lifts outward in a right bend")
        T.near(Cart.roll(cart, stats, -0.01), -math.rad(stats.LiftMax), 1e-9, "and in a left bend")
    end)

    T.it("rocks back past upright when the crew stops leaning, then settles", function()
        local leaned = math.rad(stats.LeanTilt)
        local roll, speed = leaned, 0
        local furthest, settled = 0, nil
        for frame = 1, 60 * 4 do
            roll, speed = Cart.rock(stats, roll, speed, 0, 1 / 60)
            furthest = math.min(furthest, roll)
            if not settled and frame > 30 and math.abs(roll) < leaned * 0.03 and math.abs(speed) < 0.02 then
                settled = frame / 60
            end
        end
        T.truthy(furthest < -leaned * 0.1, "swings past upright the other way")
        T.truthy(furthest > -leaned * 0.6, "but not wildly")
        T.truthy(settled and settled < 2.5, "settles within a couple of seconds, took " .. tostring(settled))
        T.near(roll, 0, leaned * 0.01, "and comes to rest upright")
    end)

    T.it("rocks into a lean the same way, and stays steady on a long frame", function()
        local target = -math.rad(stats.LeanTilt)
        local roll, speed = 0, 0
        local beyond = 0
        for _ = 1, 60 * 3 do
            roll, speed = Cart.rock(stats, roll, speed, target, 1 / 60)
            beyond = math.min(beyond, roll)
        end
        T.truthy(beyond < target, "leans a little past before it settles")
        T.near(roll, target, math.abs(target) * 0.02)
        local slow, slowSpeed = Cart.rock(stats, 0, 0, target, 0.5)
        T.truthy(slow == slow and math.abs(slow) < math.abs(target) * 2, "a half-second frame doesn't blow up")
        T.truthy(slowSpeed == slowSpeed, "no NaN")
    end)

    T.it("is pushed back onto the rails faster with more of the crew pushing", function()
        T.equal(Cart.rightSeconds(stats, 1), stats.RightSeconds)
        T.truthy(Cart.rightSeconds(stats, 4) < Cart.rightSeconds(stats, 2), "four beat two")
        T.equal(Cart.rightSeconds(stats, 0), math.huge, "nobody pushing never rights it")
        local cart = Cart.new(stats)
        cart.speed, cart.tilt = 20, 1
        Cart.righted(cart)
        T.equal(cart.speed, 0)
        T.falsy(Cart.tipped(cart))
    end)

    T.it("is chewed by crawlers, less with Chew Guard", function()
        local chewing = { moving = true, chewers = 2, chewDps = 5 }
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

    T.it("runs faster downhill and slower through bends", function()
        local downhill = Cart.new(stats)
        run(downhill, 10, { moving = true, chewers = 0, chewDps = 0, grade = 0.0625 })
        T.near(downhill.speed, stats.Speed * (1 + stats.SlopeBoost * 0.0625), 1e-6)
        local bend = Cart.new(stats)
        run(bend, 10, { moving = true, chewers = 0, chewDps = 0, curvature = 0.016 })
        T.near(bend.speed, stats.Speed * (1 - stats.CurveDrag * 0.016), 1e-6)
        local braked = Cart.new(stats)
        run(braked, 10, ROLLING)
        Cart.setThrottle(braked, -1)
        run(braked, 3, { moving = true, chewers = 0, chewDps = 0, grade = 0.2 })
        T.near(braked.speed, stats.Speed * stats.BrakeFactor, 1e-6, "the brake ignores the slope")
    end)

    T.it("leans outward in bends, more at speed, up to a limit", function()
        T.near(Cart.bank(stats, 28, 0), 0)
        T.truthy(Cart.bank(stats, 28, 0.008) > 0, "right bend leans one way")
        T.truthy(Cart.bank(stats, 28, -0.008) < 0, "left bend leans the other")
        T.truthy(Cart.bank(stats, 28, 0.008) > Cart.bank(stats, 12, 0.008), "faster leans more")
        T.near(Cart.bank(stats, 100, 1), math.rad(stats.MaxBank), 1e-9)
    end)

    T.it("rolls to a stop at a station", function()
        local cart = Cart.new(stats)
        run(cart, 10, ROLLING)
        run(cart, 10, { moving = false, chewers = 0, chewDps = 0 })
        T.near(cart.speed, 0, 1e-6)
    end)
end)
