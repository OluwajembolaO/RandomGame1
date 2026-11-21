--!strict
-- Run state the server shares with every client, as attributes on ReplicatedStorage.RunInfo.
-- Keys: Phase, Zone, Leg, Legs, Stop, StopGenre, Seed, Countdown, Message,
-- CartHp, CartMaxHp, Braking, Pushing, BrakeLeft (1 cold .. 0 overheating), BrakeHot, Speed,
-- SharpIn (studs to the next sharp curve, -1 for none), CaveSeed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local folder: Instance
if RunService:IsServer() then
    local existing = ReplicatedStorage:FindFirstChild("RunInfo")
    if existing then
        folder = existing
    else
        local created = Instance.new("Folder")
        created.Name = "RunInfo"
        created.Parent = ReplicatedStorage
        folder = created
    end
else
    folder = ReplicatedStorage:WaitForChild("RunInfo")
end

local RunInfo = {}

function RunInfo.set(key: string, value: any)
    if folder:GetAttribute(key) ~= value then
        folder:SetAttribute(key, value)
    end
end

function RunInfo.get(key: string): any
    return folder:GetAttribute(key)
end

-- The instance holding the attributes (for UI hooks that watch any instance's attributes).
function RunInfo.instance(): Instance
    return folder
end

function RunInfo.changed(key: string, callback: (any) -> ()): RBXScriptConnection
    return folder:GetAttributeChangedSignal(key):Connect(function()
        callback(folder:GetAttribute(key))
    end)
end

return RunInfo
