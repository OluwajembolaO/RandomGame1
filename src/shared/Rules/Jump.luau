--!strict
-- Jumping a gap in broken track. The cart leaves the broken lip angled up at Lip degrees and flies a
-- ballistic arc under Gravity; the far side sits `drop` studs below the line the track was on, and the cart
-- makes it when its arc is no more than Clearance studs below the far deck by the time it gets there.
-- Heights are measured from the approach line (the track's line carried on over the gap), and `along` is
-- horizontal studs from the lip. The result is decided at the lip: CartService flies the arc either way.

export type Physics = { Gravity: number, Lip: number, Clearance: number }
export type Gap = { length: number, drop: number }

local Jump = {}

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

-- The arc's slope (rise per horizontal stud) `along` studs past the lip, for pitching the cart nose up then down.
function Jump.slope(physics: Physics, speed: number, along: number): number
    local tan, cos = angles(physics)
    return tan - physics.Gravity * along / (speed * speed * cos * cos)
end

return Jump
