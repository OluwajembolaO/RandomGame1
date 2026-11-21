--!strict
-- Track geometry on plain numbers, so Lune can test it. Pieces (straights and curves, always sloping
-- down; the cave kit's, see Rules/Kit) are sampled into points the cart follows by distance.
-- Headings are radians in the XZ plane: direction = (cos h, 0, sin h). Server code turns points into CFrames.

export type Vec = { x: number, y: number, z: number }
-- kind is "Straight" or "Curve" (string literal unions widen across modules; TRAPS #19).
export type Piece = { kind: string, length: number, turn: number, grade: number, sharp: boolean }
export type Span = { from: number, to: number }
export type Track = {
    points: { Vec },
    distances: { number },
    length: number,
    sharp: { Span },
    startHeading: number,
    endHeading: number,
}

export type Rules = { MaxStep: number, MinY: number, BaseHeading: number }

local Track = {}

-- Samples pieces into points about `step` studs apart, starting at `start` facing `heading`.
function Track.build(pieces: { Piece }, start: Vec, heading: number, step: number): Track
    local points: { Vec } = { { x = start.x, y = start.y, z = start.z } }
    local distances = { 0 }
    local sharp: { Span } = {}
    local x, y, z, h = start.x, start.y, start.z, heading
    local travelled = 0
    for _, piece in pieces do
        local count = math.max(1, math.ceil(piece.length / step))
        local ds = piece.length / count
        local dh = piece.turn / count
        local from = travelled
        for _ = 1, count do
            -- Stepping along the midpoint heading keeps arcs accurate.
            local mid = h + dh / 2
            local dx = math.cos(mid) * ds
            local dz = math.sin(mid) * ds
            local dy = -piece.grade * ds
            x += dx
            y += dy
            z += dz
            h += dh
            travelled += math.sqrt(dx * dx + dy * dy + dz * dz)
            table.insert(points, { x = x, y = y, z = z })
            table.insert(distances, travelled)
        end
        if piece.sharp then
            table.insert(sharp, { from = from, to = travelled })
        end
    end
    return {
        points = points,
        distances = distances,
        length = travelled,
        sharp = sharp,
        startHeading = heading,
        endHeading = h,
    }
end

-- A straight piece of `length` horizontal studs that drops `drop` studs (used for stations and stops).
function Track.straight(length: number, drop: number, start: Vec, heading: number, step: number): Track
    local piece = { kind = "Straight", length = length, turn = 0, grade = drop / length, sharp = false }
    return Track.build({ piece }, start, heading, step)
end

-- Joins tracks end to start into one; each track must start where the previous one ended.
function Track.concat(tracks: { Track }): Track
    assert(#tracks > 0, "Track.concat needs at least one track")
    local points: { Vec } = {}
    local distances: { number } = {}
    local sharp: { Span } = {}
    local offset = 0
    for index, track in tracks do
        for i = if index == 1 then 1 else 2, #track.points do
            table.insert(points, track.points[i])
            table.insert(distances, track.distances[i] + offset)
        end
        for _, span in track.sharp do
            table.insert(sharp, { from = span.from + offset, to = span.to + offset })
        end
        offset += track.length
    end
    return {
        points = points,
        distances = distances,
        length = offset,
        sharp = sharp,
        startHeading = tracks[1].startHeading,
        endHeading = tracks[#tracks].endHeading,
    }
end

-- Position and unit direction at `distance` studs along the track (clamped to its ends).
function Track.sample(track: Track, distance: number): (Vec, Vec)
    local d = math.clamp(distance, 0, track.length)
    local distances = track.distances
    local low, high = 1, #distances
    while high - low > 1 do
        local mid = (low + high) // 2
        if distances[mid] <= d then
            low = mid
        else
            high = mid
        end
    end
    local a, b = track.points[low], track.points[high]
    local span = distances[high] - distances[low]
    local t = if span > 0 then (d - distances[low]) / span else 0
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    local size = math.sqrt(dx * dx + dy * dy + dz * dz)
    local position = { x = a.x + dx * t, y = a.y + dy * t, z = a.z + dz * t }
    if size == 0 then
        return position, { x = math.cos(track.startHeading), y = 0, z = math.sin(track.startHeading) }
    end
    return position, { x = dx / size, y = dy / size, z = dz / size }
end

-- The track's shape around `distance`, measured over `reach` studs either side: grade (drop per horizontal
-- stud, positive going downhill) and curvature (heading change per stud, positive turning right).
function Track.shapeAt(track: Track, distance: number, reach: number?): (number, number)
    local span = reach or 4
    local a, aDirection = Track.sample(track, distance - span)
    local b, bDirection = Track.sample(track, distance + span)
    local dx, dz = b.x - a.x, b.z - a.z
    local horizontal = math.sqrt(dx * dx + dz * dz)
    if horizontal < 1e-6 then
        return 0, 0
    end
    local turn = math.atan2(bDirection.z, bDirection.x) - math.atan2(aDirection.z, aDirection.x)
    turn = (turn + math.pi) % (2 * math.pi) - math.pi
    return (a.y - b.y) / horizontal, turn / horizontal
end

function Track.sharpAt(track: Track, distance: number): boolean
    for _, span in track.sharp do
        if distance >= span.from and distance <= span.to then
            return true
        end
    end
    return false
end

-- The next sharp curve that hasn't ended yet, or nil.
function Track.nextSharp(track: Track, distance: number): Span?
    for _, span in track.sharp do
        if span.to >= distance then
            return span
        end
    end
    return nil
end

-- A track is rideable when its points are evenly spaced, it never climbs, it always moves forward along
-- the zone's heading (so it can't cross itself), and it stays above MinY.
function Track.validate(track: Track, rules: Rules): (boolean, string?)
    local points, distances = track.points, track.distances
    if #points < 2 then
        return false, "track has fewer than two points"
    end
    if #points ~= #distances then
        return false, "points and distances differ in length"
    end
    local forwardX, forwardZ = math.cos(rules.BaseHeading), math.sin(rules.BaseHeading)
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local stepLength = distances[i + 1] - distances[i]
        if stepLength <= 0 then
            return false, "distance doesn't increase at point " .. i
        end
        if stepLength > rules.MaxStep then
            return false, string.format("step of %.1f studs at point %d (max %.1f)", stepLength, i, rules.MaxStep)
        end
        if b.y > a.y + 1e-9 then
            return false, "track climbs at point " .. i
        end
        if (b.x - a.x) * forwardX + (b.z - a.z) * forwardZ <= 0 then
            return false, "track turns back at point " .. i
        end
        if b.y < rules.MinY then
            return false, string.format("track drops to y=%.0f at point %d (min %.0f)", b.y, i, rules.MinY)
        end
    end
    return true, nil
end

return Track
