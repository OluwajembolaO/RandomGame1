--!strict
-- The safety net. The cave's rock doesn't collide (the cart rides its rails through it), so the only solid
-- ground is the invisible floor along the track (TrackDresser) and the station and stop floors. Anyone on
-- their feet who still ends up Run.Track.RescueDrop studs below the cart (walked off a cavern walkway, slipped
-- past a tunnel floor's edge) is put back on the track just behind the cart, instead of falling out of the
-- world. Their own client moves them (it owns their physics; TRAPS #44), with a server move as a fallback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Remotes = require(Shared.Remotes)

local Rescue = {}

local CHECK_EVERY = 0.5

-- `safeSpot` says where to put a fallen player right now (nil when there's no cart to measure from).
function Rescue.start(safeSpot: () -> CFrame?)
    local drop = Configs.Run.Track.RescueDrop
    task.spawn(function()
        while true do
            task.wait(CHECK_EVERY)
            local safe = safeSpot()
            if safe then
                for _, player in Players:GetPlayers() do
                    local character = player.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    local standing = humanoid ~= nil and humanoid.Health > 0 and not humanoid.Sit
                    if standing and root and root:IsA("BasePart") and root.Position.Y < safe.Position.Y - drop then
                        Remotes.Effect:FireClient(player, "Place", safe)
                        task.delay(0.4, function()
                            local current = player.Character
                            local again = current and current:FindFirstChild("HumanoidRootPart")
                            if
                                current
                                and again
                                and again:IsA("BasePart")
                                and again.Position.Y < safe.Position.Y - drop
                            then
                                current:PivotTo(safe)
                            end
                        end)
                    end
                end
            end
        end
    end)
end

return Rescue
