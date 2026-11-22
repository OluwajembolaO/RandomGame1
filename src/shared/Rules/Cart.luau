--!strict
-- The cart on plain numbers: hit points, speed (with momentum: faster downhill, slower through bends),
-- the crew's throttle (push it faster or hold the brake), the crew leaning their weight left or right, and
-- tipping over: take a bend too hard and the cart lifts onto its outer wheels and falls over, unless the
-- crew slows down or leans into the bend. CartService applies these to the real cart.

export type Stats = {
    MaxHp: number,
    Speed: number,
    Accel: number,
    BrakeFactor: number,
    PushFactor: number, -- cruising speed multiplier while the crew pushes the cart
    RepairPerSecond: number,
    ChewArmor: number,
    SlopeBoost: number, -- extra cruising speed per unit of downhill grade (x Speed)
    CurveDrag: number, -- speed lost per radian-per-stud of curvature (as a fraction)
    CurveDragMax: number, -- the most a bend can slow the cart (as a fraction)
    BankPerAccel: number, -- degrees of lean per stud/s^2 of sideways pull
    MaxBank: number, -- degrees
    TipLimit: number, -- sideways pull (studs/s^2) the cart takes before it starts to tip
    LeanBonus: number, -- the whole crew leaning into a bend raises the limit by this fraction
    LeanPenalty: number, -- the whole crew leaning out of a bend lowers it by this fraction
    TipRate: number, -- how fast the tilt fills per unit of pull over the limit (full tilt tips the cart)
    TipRecover: number, -- how fast the tilt drains back under the limit, per second
    LeanTilt: number, -- degrees the cart body tilts toward the side the crew leans
    LiftMax: number, -- degrees the cart lifts onto its outer wheels just before tipping
    RockFrequency: number, -- how many times a second the cart body swings as it rocks (Cart.rock)
    RockDamping: number, -- how quickly the rocking dies away (0 never, 1 no overshoot)
    RightSeconds: number, -- how long one player takes to push a tipped cart back onto the rails
    HelperBoost: number, -- each extra player pushing adds this much speed
}

-- throttle: -1 brake, 0 coast, 1 push. lean: the crew's weight, -1 all left .. 1 all right.
-- tilt: 0 on all four wheels .. 1 tipped over.
export type Cart = { hp: number, speed: number, throttle: number, lean: number, tilt: number }

-- What's happening to the cart this tick.
export type Conditions = {
    moving: boolean, -- false at stops: the cart rolls to a halt
    chewers: number, -- crawlers on the cart
    chewDps: number,
    grade: number?, -- the track's downhill grade here (Track.shapeAt)
    curvature: number?, -- the track's curvature here, positive turning right
}

local Cart = {}

-- Cart stats from the Run.Cart config plus the run's upgraded stats (Rules/Upgrades.apply).
function Cart.stats(config: any, upgraded: { [string]: number }): Stats
    return {
        MaxHp = upgraded.CartMaxHp,
        Speed = config.Speed,
        Accel = config.Accel,
        BrakeFactor = config.BrakeFactor,
        PushFactor = config.PushFactor,
        RepairPerSecond = config.RepairPerSecond,
        ChewArmor = upgraded.ChewArmor,
        SlopeBoost = config.SlopeBoost,
        CurveDrag = config.CurveDrag,
        CurveDragMax = config.CurveDragMax,
        BankPerAccel = config.BankPerAccel,
        MaxBank = config.MaxBank,
        TipLimit = upgraded.TipLimit,
        LeanBonus = config.LeanBonus,
        LeanPenalty = config.LeanPenalty,
        TipRate = config.TipRate,
        TipRecover = config.TipRecover,
        LeanTilt = config.LeanTilt,
        LiftMax = config.LiftMax,
        RockFrequency = config.RockFrequency,
        RockDamping = config.RockDamping,
        RightSeconds = upgraded.RightSeconds,
        HelperBoost = config.HelperBoost,
    }
end

function Cart.new(stats: Stats): Cart
    return { hp = stats.MaxHp, speed = 0, throttle = 0, lean = 0, tilt = 0 }
end

-- What the crew is asking for: -1 brake, 0 coast, 1 push (anything else is rounded and clamped).
function Cart.setThrottle(cart: Cart, throttle: number)
    cart.throttle = if throttle ~= throttle then 0 else math.clamp(math.round(throttle), -1, 1)
end

-- One throttle for the whole crew: anyone braking wins (so anyone can save the cart), then anyone pushing.
function Cart.crewThrottle(throttles: { number }): number
    local pushing = false
    for _, throttle in throttles do
        if throttle < 0 then
            return -1
        end
        pushing = pushing or throttle > 0
    end
    return if pushing then 1 else 0
end

-- The crew's lean: the average of every rider's (-1 left .. 1 right), so it takes everyone to lean fully.
function Cart.crewLean(leans: { number }): number
    if #leans == 0 then
        return 0
    end
    local total = 0
    for _, lean in leans do
        if lean == lean then
            total += math.clamp(lean, -1, 1)
        end
    end
    return total / #leans
end

function Cart.setLean(cart: Cart, lean: number)
    cart.lean = if lean ~= lean then 0 else math.clamp(lean, -1, 1)
end

function Cart.braking(cart: Cart): boolean
    return cart.throttle < 0
end

function Cart.pushing(cart: Cart): boolean
    return cart.throttle > 0
end

-- The speed the cart is heading for: it runs faster down steeper track and loses some speed in bends, and
-- faster still while pushed; the brake overrides all of that.
function Cart.targetSpeed(cart: Cart, stats: Stats, moving: boolean, grade: number?, curvature: number?): number
    if not moving then
        return 0
    end
    if Cart.braking(cart) then
        return stats.Speed * stats.BrakeFactor
    end
    local slope = 1 + stats.SlopeBoost * math.max(0, grade or 0)
    local drag = 1 - math.min(stats.CurveDragMax, stats.CurveDrag * math.abs(curvature or 0))
    local push = if Cart.pushing(cart) then stats.PushFactor else 1
    return stats.Speed * slope * drag * push
end

-- Sideways pull in a bend, studs/s^2.
function Cart.pull(speed: number, curvature: number): number
    return speed * speed * math.abs(curvature)
end

-- How much sideways pull the cart takes before it starts to tip: more with the crew leaning into the bend,
-- less with them leaning out of it.
function Cart.tipLimit(stats: Stats, lean: number, curvature: number): number
    local into = if curvature > 0 then lean elseif curvature < 0 then -lean else 0
    return stats.TipLimit * (1 + stats.LeanBonus * math.max(0, into) - stats.LeanPenalty * math.max(0, -into))
end

function Cart.tipped(cart: Cart): boolean
    return cart.tilt >= 1
end

-- How far the cart body leans in a bend, in radians: outward, harder the faster it takes the bend.
-- Positive for right-hand bends (the top tips left).
function Cart.bank(stats: Stats, speed: number, curvature: number): number
    local sideways = speed * speed * curvature
    return math.rad(math.clamp(sideways * stats.BankPerAccel, -stats.MaxBank, stats.MaxBank))
end

-- The whole roll the cart body shows, in radians (same sign as Cart.bank): the bend's lean, tilted toward
-- the side the crew leans, and lifted onto the outer wheels as it starts to tip.
function Cart.roll(cart: Cart, stats: Stats, curvature: number): number
    local outward = if curvature > 0 then 1 elseif curvature < 0 then -1 else 0
    return Cart.bank(stats, cart.speed, curvature)
        - math.rad(stats.LeanTilt) * cart.lean
        + math.rad(stats.LiftMax) * cart.tilt * outward
end

-- Moves the cart body's roll toward `target` (Cart.roll) the way a heavy box on its wheels would: a damped
-- spring, so it swings a little past where it's going and rocks back before it settles, instead of easing
-- straight there. `speed` is the roll's speed (radians a second); returns the new roll and speed. Steps
-- itself in small slices, so it stays steady however long `dt` is.
function Cart.rock(stats: Stats, roll: number, speed: number, target: number, dt: number): (number, number)
    local omega = 2 * math.pi * stats.RockFrequency
    local slices = math.max(1, math.ceil(dt * 240))
    local h = dt / slices
    for _ = 1, slices do
        local push = omega * omega * (target - roll) - 2 * stats.RockDamping * omega * speed
        speed += push * h
        roll += speed * h
    end
    return roll, speed
end

function Cart.damage(cart: Cart, amount: number)
    cart.hp = math.max(0, cart.hp - math.max(0, amount))
end

function Cart.repair(cart: Cart, stats: Stats, amount: number)
    cart.hp = math.min(stats.MaxHp, cart.hp + math.max(0, amount))
end

function Cart.wrecked(cart: Cart): boolean
    return cart.hp <= 0
end

-- How long a tipped cart takes to push back onto the rails with `pushers` players on it.
function Cart.rightSeconds(stats: Stats, pushers: number): number
    if pushers <= 0 then
        return math.huge
    end
    return stats.RightSeconds / (1 + stats.HelperBoost * (pushers - 1))
end

-- Back on the rails: still, and on all four wheels.
function Cart.righted(cart: Cart)
    cart.speed, cart.tilt = 0, 0
end

-- Advances speed and tilt by dt and applies damage. Returns the damage taken this tick.
function Cart.step(cart: Cart, stats: Stats, dt: number, conditions: Conditions): number
    -- Brakes bite twice as hard as the cart accelerates; coasting down to a lower speed is gentler.
    local target = Cart.targetSpeed(cart, stats, conditions.moving, conditions.grade, conditions.curvature)
    local slowing = if Cart.braking(cart) then stats.Accel * 2 else stats.Accel * 0.8
    cart.speed += math.clamp(target - cart.speed, -slowing * dt, stats.Accel * dt)

    -- Over the limit the cart lifts onto its outer wheels, faster the further over it is; back under, it
    -- settles down again.
    local curvature = conditions.curvature or 0
    local over = Cart.pull(cart.speed, curvature) / Cart.tipLimit(stats, cart.lean, curvature) - 1
    if over > 0 then
        cart.tilt = math.min(1, cart.tilt + over * stats.TipRate * dt)
    else
        cart.tilt = math.max(0, cart.tilt - stats.TipRecover * dt)
    end

    local damage = conditions.chewers * conditions.chewDps * stats.ChewArmor * dt
    Cart.damage(cart, damage)
    return damage
end

return Cart
