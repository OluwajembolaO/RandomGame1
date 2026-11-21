--!strict
-- The cart on plain numbers: hit points, speed (with momentum: faster downhill, slower through bends),
-- the brake, and how far it leans in a bend. CartService applies these to the real cart.

export type Stats = {
    MaxHp: number,
    Speed: number,
    Accel: number,
    BrakeFactor: number,
    BrakeSeconds: number,
    BrakeCooldown: number,
    SafeCurveSpeed: number,
    SharpDamagePerSecond: number,
    RepairPerSecond: number,
    ChewArmor: number,
    SlopeBoost: number, -- extra cruising speed per unit of downhill grade (x Speed)
    CurveDrag: number, -- speed lost per radian-per-stud of curvature (as a fraction)
    CurveDragMax: number, -- the most a bend can slow the cart (as a fraction)
    BankPerAccel: number, -- degrees of lean per stud/s^2 of sideways pull
    MaxBank: number, -- degrees
}

export type Cart = { hp: number, speed: number, brakeLeft: number, brakeCooldown: number }

-- What's happening to the cart this tick.
export type Conditions = {
    moving: boolean, -- false at stops: the cart rolls to a halt
    sharp: boolean, -- inside a sharp curve
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
        BrakeSeconds = upgraded.BrakeSeconds,
        BrakeCooldown = config.BrakeCooldown,
        SafeCurveSpeed = config.SafeCurveSpeed,
        SharpDamagePerSecond = config.SharpDamagePerSecond,
        RepairPerSecond = config.RepairPerSecond,
        ChewArmor = upgraded.ChewArmor,
        SlopeBoost = config.SlopeBoost,
        CurveDrag = config.CurveDrag,
        CurveDragMax = config.CurveDragMax,
        BankPerAccel = config.BankPerAccel,
        MaxBank = config.MaxBank,
    }
end

function Cart.new(stats: Stats): Cart
    return { hp = stats.MaxHp, speed = 0, brakeLeft = 0, brakeCooldown = 0 }
end

function Cart.braking(cart: Cart): boolean
    return cart.brakeLeft > 0
end

-- Returns false while the brake is already on or cooling down.
function Cart.pullBrake(cart: Cart, stats: Stats): boolean
    if cart.brakeLeft > 0 or cart.brakeCooldown > 0 then
        return false
    end
    cart.brakeLeft = stats.BrakeSeconds
    return true
end

-- The speed the cart is heading for: it runs faster down steeper track and loses some speed in bends;
-- the brake overrides both.
function Cart.targetSpeed(cart: Cart, stats: Stats, moving: boolean, grade: number?, curvature: number?): number
    if not moving then
        return 0
    end
    if cart.brakeLeft > 0 then
        return stats.Speed * stats.BrakeFactor
    end
    local slope = 1 + stats.SlopeBoost * math.max(0, grade or 0)
    local drag = 1 - math.min(stats.CurveDragMax, stats.CurveDrag * math.abs(curvature or 0))
    return stats.Speed * slope * drag
end

-- How far the cart body leans in a bend, in radians: outward, harder the faster it takes the bend.
-- Positive for right-hand bends (the top tips left).
function Cart.bank(stats: Stats, speed: number, curvature: number): number
    local sideways = speed * speed * curvature
    return math.rad(math.clamp(sideways * stats.BankPerAccel, -stats.MaxBank, stats.MaxBank))
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

-- Advances the brake and speed by dt and applies damage. Returns the damage taken this tick.
function Cart.step(cart: Cart, stats: Stats, dt: number, conditions: Conditions): number
    if cart.brakeLeft > 0 then
        cart.brakeLeft = math.max(0, cart.brakeLeft - dt)
        if cart.brakeLeft == 0 then
            cart.brakeCooldown = stats.BrakeCooldown
        end
    elseif cart.brakeCooldown > 0 then
        cart.brakeCooldown = math.max(0, cart.brakeCooldown - dt)
    end

    -- Brakes bite twice as hard as the cart accelerates; coasting down to a lower speed is gentler.
    local target = Cart.targetSpeed(cart, stats, conditions.moving, conditions.grade, conditions.curvature)
    local slowing = if cart.brakeLeft > 0 then stats.Accel * 2 else stats.Accel * 0.8
    cart.speed += math.clamp(target - cart.speed, -slowing * dt, stats.Accel * dt)

    local damage = 0
    if conditions.sharp and cart.speed > stats.SafeCurveSpeed then
        damage += stats.SharpDamagePerSecond * dt
    end
    damage += conditions.chewers * conditions.chewDps * stats.ChewArmor * dt
    Cart.damage(cart, damage)
    return damage
end

return Cart
