--!strict
-- Jumping a gap in broken track. The cart leaves the broken lip angled up at Lip degrees and flies a
-- ballistic arc under Gravity; the far side sits `drop` studs below the line the track was on, and the cart
-- makes it when its arc is no more than Clearance studs below the far deck by the time it gets there.
-- Heights are measured from the approach line (the track's line carried on over the gap), and `along` is
-- horizontal studs from the lip. The result is decided at the lip: CartService flies the arc either way.
-- Landing isn't flat: the cart bounces off the rails in smaller and smaller hops, its nose slams down and
-- rocks back, and it jolts a little sideways, all scaled by how hard it came down (Jump.landingKick).

export type Physics = {
    Gravity: number,
    Lip: number,
    Clearance: number,
    Restitution: number?, -- how much of the landing speed the first hop keeps
    PitchKick: number?, -- nose-down spin (radians a second) per stud a second of landing speed
    RollKick: number?, -- the most sideways spin, likewise
}
export type Gap = { length: number, drop: number }

local Jump = {}

local MIN_HOP = 1.5 -- studs a second: a bounce slower than this is too small to see, so it stops

local function angles(physics: Physics): (number, number)
    local lip = math.rad(physics.Lip)
    return math.tan(lip), math.cos(lip)
end

-- The arc's height above the approach line, `along` studs past the lip, leaving at `speed`.
function Jump.height(physics: Physics, speed: number, along: number): number
    if speed <= 0 then
        return if along > 0 then -math.huge else 0
    end
    local tan, cos = angles(physics)
    return along * tan - physics.Gravity * along * along / (2 * speed * speed * cos * cos)
end

-- The slowest the cart can leave the lip and still make the far side.
function Jump.minSpeed(physics: Physics, gap: Gap): number
    local tan, cos = angles(physics)
    local length = gap.length
    return math.sqrt(
        physics.Gravity * length * length / (2 * cos * cos * (length * tan + gap.drop + physics.Clearance))
    )
end

function Jump.clears(physics: Physics, gap: Gap, speed: number): boolean
    return speed >= Jump.minSpeed(physics, gap)
end

-- Where a jump that clears comes down onto the far deck: horizontal studs past the lip (never short of the
-- far edge; a cart that only just makes it is set down on the edge).
function Jump.landing(physics: Physics, gap: Gap, speed: number): number
    local tan, cos = angles(physics)
    local k = physics.Gravity / (2 * speed * speed * cos * cos)
    -- along*tan - k*along^2 = -drop
    local along = (tan + math.sqrt(tan * tan + 4 * k * gap.drop)) / (2 * k)
    return math.max(gap.length, along)
end

-- How long the cart is in the air for `along` horizontal studs.
function Jump.time(physics: Physics, speed: number, along: number): number
    local _, cos = angles(physics)
    return along / (speed * cos)
end

-- How hard a cart lands: its downward speed onto the far deck (studs a second), `along` studs past the lip.
function Jump.impact(physics: Physics, speed: number, along: number): number
    local _, cos = angles(physics)
    return math.max(0, -Jump.slope(physics, speed, along) * speed * cos)
end

-- What a landing at `impact` (Jump.impact) sets going: the first hop's upward speed, the nose-down spin and
-- a sideways spin (`side` from -1 to 1 picks which way and how much).
function Jump.landingKick(physics: Physics, impact: number, side: number): (number, number, number)
    return impact * (physics.Restitution or 0),
        -impact * (physics.PitchKick or 0),
        side * impact * (physics.RollKick or 0)
end

-- The cart hopping on the rails after a landing: `height` studs up and rising at `speed`, it falls under
-- Gravity and bounces off the rails keeping Restitution of its speed, until the hops are too small to see.
-- Returns the new height and speed.
function Jump.bounce(physics: Physics, height: number, speed: number, dt: number): (number, number)
    if height <= 0 and speed <= 0 then
        return 0, 0
    end
    local slices = math.max(1, math.ceil(dt * 240))
    local h = dt / slices
    for _ = 1, slices do
        speed -= physics.Gravity * h
        height += speed * h
        if height <= 0 then
            height = 0
            speed = -speed * (physics.Restitution or 0)
            if speed < MIN_HOP then
                return 0, 0
            end
        end
    end
    return height, speed
end

-- The arc's slope (rise per horizontal stud) `along` studs past the lip, for pitching the cart nose up then down.
function Jump.slope(physics: Physics, speed: number, along: number): number
    local tan, cos = angles(physics)
    return tan - physics.Gravity * along / (speed * speed * cos * cos)
end

return Jump
