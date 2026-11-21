--!strict
-- The Rivet Gun, a raycast gun every crew member carries. Clients send where they aimed; the server
-- checks the fire rate and ammo, traces from the shooter's head (so nobody shoots through a wall from
-- the muzzle), and hands hits on tagged "Mob" models to whoever registered with onHit.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Remotes = require(Shared.Remotes)

local config = Configs.Weapons.RivetGun
local TOOL_NAME = "RivetGun"
local LATENCY_SLACK = 0.85 -- accept shots slightly early, since remote timing jitters

local Weapons = {}

local cooldown: number = config.Cooldown
local damage: number = config.Damage
local lastShot: { [Player]: number } = {}
local ammo: { [Player]: number } = {}
local hitHandler: ((Model, number, Player) -> ())? = nil
local ignoreSource: () -> { Instance } = function()
    return {}
end

-- Rivet stats after upgrades (RivetCooldown, RivetDamage).
function Weapons.setStats(stats: { [string]: number })
    cooldown = stats.RivetCooldown
    damage = stats.RivetDamage
    for _, player in Players:GetPlayers() do
        player:SetAttribute("RivetCooldown", cooldown)
    end
end

function Weapons.onHit(handler: (Model, number, Player) -> ())
    hitHandler = handler
end

-- Extra things shots pass through (the cart, so riders can shoot over its walls).
function Weapons.setIgnore(source: () -> { Instance })
    ignoreSource = source
end

local function buildTool(): Tool
    local tool = Instance.new("Tool")
    tool.Name = TOOL_NAME
    tool.ToolTip = "Rivet Gun"
    tool.CanBeDropped = false
    tool.RequiresHandle = true
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.5, 0.9, 2.2)
    handle.Color = Color3.fromRGB(72, 70, 66)
    handle.Material = Enum.Material.Metal
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool
    local barrel = Instance.new("Part")
    barrel.Name = "Barrel"
    barrel.Size = Vector3.new(0.3, 0.3, 1.2)
    barrel.Color = Color3.fromRGB(150, 110, 60)
    barrel.Material = Enum.Material.Metal
    barrel.CanCollide = false
    barrel.Massless = true
    barrel.CFrame = handle.CFrame * CFrame.new(0, 0.25, -1.5)
    barrel.Parent = tool
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = handle
    weld.Part1 = barrel
    weld.Parent = barrel
    local muzzle = Instance.new("Attachment")
    muzzle.Name = "Muzzle"
    muzzle.Position = Vector3.new(0, 0.25, -2.2)
    muzzle.Parent = handle
    return tool
end

local function setAmmo(player: Player, count: number)
    ammo[player] = count
    player:SetAttribute("Ammo", count)
end

-- Gives a fresh Rivet Gun with a full magazine (call after the character loads).
function Weapons.give(player: Player)
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack and not backpack:FindFirstChild(TOOL_NAME) then
        buildTool().Parent = backpack
    end
    setAmmo(player, config.Magazine)
    player:SetAttribute("Reloading", false)
    player:SetAttribute("RivetCooldown", cooldown)
end

local function mobFrom(instance: Instance): Model?
    local current: Instance? = instance
    while current and current ~= workspace do
        if current:IsA("Model") and CollectionService:HasTag(current, "Mob") then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function reload(player: Player)
    player:SetAttribute("Reloading", true)
    task.delay(config.ReloadSeconds, function()
        if player.Parent then
            setAmmo(player, config.Magazine)
            player:SetAttribute("Reloading", false)
        end
    end)
end

Remotes.Fire.OnServerEvent:Connect(function(player: Player, aim: unknown)
    if typeof(aim) ~= "Vector3" then
        return
    end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local head = character and character:FindFirstChild("Head")
    local tool = character and character:FindFirstChild(TOOL_NAME)
    if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") or not tool then
        return
    end
    if player:GetAttribute("Downed") == true or player:GetAttribute("Reloading") == true then
        return
    end
    local now = os.clock()
    if now - (lastShot[player] or 0) < cooldown * LATENCY_SLACK then
        return
    end
    local left = ammo[player] or config.Magazine
    if left <= 0 then
        return
    end
    lastShot[player] = now
    setAmmo(player, left - 1)
    if left - 1 == 0 then
        reload(player)
    end

    local origin = head.Position
    local offset = aim - origin
    if offset.Magnitude < 0.5 then
        return
    end
    local direction = offset.Unit * config.Range
    local ignore = ignoreSource()
    for _, other in Players:GetPlayers() do
        if other.Character then
            table.insert(ignore, other.Character)
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local result = workspace:Raycast(origin, direction, params)
    local hitAt = if result then result.Position else origin + direction

    local hitMob = false
    if result and hitHandler then
        local mob = mobFrom(result.Instance)
        if mob then
            hitMob = true
            hitHandler(mob, damage, player)
        end
    end

    local handle = tool:FindFirstChild("Handle")
    local muzzle = handle and handle:FindFirstChild("Muzzle")
    local from = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else origin
    Remotes.Effect:FireAllClients("Tracer", player, from, hitAt, hitMob)
end)

Players.PlayerRemoving:Connect(function(player)
    lastShot[player] = nil
    ammo[player] = nil
end)

return Weapons
