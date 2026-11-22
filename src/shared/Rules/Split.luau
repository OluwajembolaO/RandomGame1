--!strict
-- Three-way splits. In a junction chunk the track fans into three lanes: -1 left, 0 middle, 1 right. Each
-- run one lane is open (Layout rolls it); the other two end at buffer stops. The crew picks a lane by how
-- they're leaning as the cart reaches the switch, and a dead lane slams the cart into its buffer.
-- Distances are along the track; the lanes run `offset` studs either side of the line, easing out over
-- `ramp` studs after the switch and (the open lane) back in over `ramp` studs before `to`.

export type Span = { from: number, to: number, buffer: number, offset: number, ramp: number, open: number }

local Split = {}

-- How far the crew has to lean (their average, -1 .. 1) to take a side lane.
Split.PICK = 0.33

function Split.lane(lean: number): number
    if lean <= -Split.PICK then
        return -1
    elseif lean >= Split.PICK then
        return 1
    end
    return 0
end

local function smooth(x: number): number
    local t = math.clamp(x, 0, 1)
    return t * t * (3 - 2 * t)
end

-- How far right of the line (studs) a cart in `lane` is at `distance`.
function Split.offset(span: Span, lane: number, distance: number): number
    if lane == 0 then
        return 0
    end
    local out = smooth((distance - span.from) / span.ramp)
    if lane == span.open then
        out *= smooth((span.to - distance) / span.ramp)
    end
    return lane * span.offset * out
end

function Split.dead(span: Span, lane: number): boolean
    return lane ~= span.open
end

-- Where a lane's rails end: the open lane rejoins the line at `to`; a dead lane stops at its buffer.
function Split.railEnd(span: Span, lane: number): number
    return if lane == span.open then span.to else span.buffer
end

return Split
