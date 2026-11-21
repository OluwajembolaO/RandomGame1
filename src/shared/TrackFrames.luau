--!strict
-- Turns Rules/Track positions into Roblox Vector3s and CFrames (forward is the CFrame's LookVector).
-- Shared so clients could render the cart themselves if server-driven movement ever needs replacing.

local Track = require("./Rules/Track")

local TrackFrames = {}

function TrackFrames.vector(point: Track.Vec): Vector3
    return Vector3.new(point.x, point.y, point.z)
end

function TrackFrames.position(track: Track.Track, distance: number): Vector3
    return TrackFrames.vector((Track.sample(track, distance)))
end

-- Facing along the track. The direction is averaged over `lookAhead` studs either side, so the cart
-- turns smoothly through the sampled points instead of snapping at each one.
function TrackFrames.frame(track: Track.Track, distance: number, lookAhead: number?): CFrame
    local reach = lookAhead or 3
    local position = TrackFrames.position(track, distance)
    local direction = TrackFrames.position(track, distance + reach) - TrackFrames.position(track, distance - reach)
    if direction.Magnitude < 1e-6 then
        local _, along = Track.sample(track, distance)
        direction = TrackFrames.vector(along)
    end
    return CFrame.lookAt(position, position + direction.Unit)
end

-- Same as frame, but upright (no slope): for posts, signs and anything that should stand straight.
function TrackFrames.flat(track: Track.Track, distance: number): CFrame
    local frame = TrackFrames.frame(track, distance)
    local look = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
    if look.Magnitude < 1e-6 then
        look = Vector3.xAxis
    end
    return CFrame.lookAt(frame.Position, frame.Position + look.Unit)
end

return TrackFrames
