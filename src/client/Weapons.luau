--!strict
-- Rivet Gun input. Hold to keep firing at the gun's rate; each shot sends where the player aimed and
-- draws the tracer right away (the server checks the shot and tells everyone else).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fx = require(script.Parent.Fx)

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local Weapons = {}

local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastShot = 0

local function cart(): Instance?
    local run = workspace:FindFirstChild("Run")
    return run and run:FindFirstChild("Cart")
end

local function cooldown(): number
    local value = player:GetAttribute("RivetCooldown")
    return if type(value) == "number" then value else 0.2
end

local function canFire(): boolean
    local ammo = player:GetAttribute("Ammo")
    return player:GetAttribute("Reloading") ~= true
        and player:GetAttribute("Downed") ~= true
        and type(ammo) == "number"
        and ammo > 0
end

local function fire(tool: Tool)
    local now = os.clock()
    if now - lastShot < cooldown() or not canFire() then
        return
    end
    lastShot = now
    mouse.TargetFilter = cart()
    local aim = mouse.Hit.Position
    Remotes.Fire:FireServer(aim)
    local handle = tool:FindFirstChild("Handle")
    local muzzle = handle and handle:FindFirstChild("Muzzle")
    if muzzle and muzzle:IsA("Attachment") then
        Fx.tracer(muzzle.WorldPosition, aim, false)
    end
end

local function hook(instance: Instance)
    if not instance:IsA("Tool") or instance.Name ~= "RivetGun" or hooked[instance] then
        return
    end
    local tool = instance
    hooked[tool] = true
    local holding = false
    tool.Activated:Connect(function()
        holding = true
        while holding and tool.Parent == player.Character do
            fire(tool)
            task.wait(math.max(0.03, cooldown()))
        end
    end)
    tool.Deactivated:Connect(function()
        holding = false
    end)
    tool.Unequipped:Connect(function()
        holding = false
    end)
end

function Weapons.start()
    -- Tools move into the character when equipped, so watching the character catches every gun.
    local function watch(character: Model)
        for _, child in character:GetChildren() do
            hook(child)
        end
        character.ChildAdded:Connect(hook)
    end
    if player.Character then
        watch(player.Character)
    end
    player.CharacterAdded:Connect(watch)
end

return Weapons
