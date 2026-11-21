--!strict
-- The cart on plain numbers: hit points, speed and the brake. CartService applies these to the real cart.

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
}

export type Cart = { hp: number, speed: number, brakeLeft: number, brakeCooldown: number }

-- What's happening to the cart this tick.
export type Conditions = {
    moving: boolean, -- false at stops: the cart rolls to a halt
    sharp: boolean, -- inside a sharp curve
    chewers: number, -- crawlers on the cart
    chewDps: number,
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

function Cart.targetSpeed(cart: Cart, stats: Stats, moving: boolean): number
    if not moving then
        return 0
    end
    return if cart.brakeLeft > 0 then stats.Speed * stats.BrakeFactor else stats.Speed
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

    -- Brakes bite twice as hard as the cart accelerates.
    local target = Cart.targetSpeed(cart, stats, conditions.moving)
    cart.speed += math.clamp(target - cart.speed, -stats.Accel * 2 * dt, stats.Accel * dt)

    local damage = 0
    if conditions.sharp and cart.speed > stats.SafeCurveSpeed then
        damage += stats.SharpDamagePerSecond * dt
    end
    damage += conditions.chewers * conditions.chewDps * stats.ChewArmor * dt
    Cart.damage(cart, damage)
    return damage
end

return Cart
