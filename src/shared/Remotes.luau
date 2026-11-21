--!strict
-- Every client-server message, named in one place. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
    "Fire", -- client -> server: (aim: Vector3) a Rivet Gun shot
    "Drive", -- client -> server: (throttle: number, lean: number) brake -1 / push 1, lean -1 left .. 1 right
    "Vote", -- client -> server: (option: number) a fork or upgrade vote
    "Keypad", -- client -> server: (entry: { number }) the Signal Room code
    "Effect", -- server -> client: (kind: string, ...) tracers, hits, shakes, titles
    "Stage", -- server -> client: (action: "Enter" | "Leave", stage: string, context: table)
}

local folder: Instance
if RunService:IsServer() then
    local existing = ReplicatedStorage:FindFirstChild("Remotes")
    if existing then
        folder = existing
    else
        local created = Instance.new("Folder")
        created.Name = "Remotes"
        created.Parent = ReplicatedStorage
        folder = created
    end
    for _, name in NAMES do
        if not folder:FindFirstChild(name) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = name
            remote.Parent = folder
        end
    end
else
    folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function event(name: string): RemoteEvent
    return folder:WaitForChild(name) :: RemoteEvent
end

return {
    Fire = event("Fire"),
    Drive = event("Drive"),
    Vote = event("Vote"),
    Keypad = event("Keypad"),
    Effect = event("Effect"),
    Stage = event("Stage"),
}
