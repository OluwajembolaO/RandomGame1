--!strict
-- Client-side effects: rivet tracers, the ride camera, and the cave's living lights (flicker, pulse,
-- distance culling). Listens to the server's Effect remote.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunInfo = require(ReplicatedStorage.Shared.RunInfo)

local Fx = {}

local folder = Instance.new("Folder")
folder.Name = "ClientFx"
folder.Parent = workspace

local shake = 0

local BASE_FOV = 70
local SPEED_FOV = 12 -- extra field of view at top speed
local TOP_SPEED = 34
local LEAN_FOLLOW = 0.75 -- how much of the cart's lean the camera rolls with

local function cartRoot(): BasePart?
    local run = workspace:FindFirstChild("Run")
    local cart = run and run:FindFirstChild("Cart")
    local root = cart and cart:FindFirstChild("Root")
    return if root and root:IsA("BasePart") then root else nil
end

-- How riding feels, layered on top of the first-person camera every frame (after Roblox's camera update,
-- so nothing accumulates): roll with the cart's lean, a rumble and bob that grow with speed, a nod forward
-- under braking, a wider field of view at speed, and the shake from scraping through sharp bends.
local function startRideCamera()
    local player = Players.LocalPlayer
    local speed, lastSpeed, pitch = 0, 0, 0
    local fov = BASE_FOV
    RunService:BindToRenderStep("RideCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
        local camera = workspace.CurrentCamera
        local riding = player:GetAttribute("Riding") == true
        local reported = RunInfo.get("Speed")
        local target = if riding and type(reported) == "number" then reported else 0
        speed += (target - speed) * math.min(1, dt * 6)
        local fraction = math.clamp(speed / TOP_SPEED, 0, 1)

        fov += ((BASE_FOV + SPEED_FOV * fraction) - fov) * math.min(1, dt * 3)
        camera.FieldOfView = fov

        local offset = CFrame.identity
        if riding then
            local root = cartRoot()
            local roll = if root then math.asin(math.clamp(root.CFrame.RightVector.Y, -1, 1)) * LEAN_FOLLOW else 0
            local accel = (speed - lastSpeed) / math.max(dt, 1e-3)
            pitch += (math.clamp(accel * 0.004, -0.07, 0.05) - pitch) * math.min(1, dt * 5)
            local now = os.clock()
            local bob = math.noise(now * 9, 1.3) * 0.08 * fraction
            local jitterX = math.noise(now * 15, 7.1) * 0.006 * fraction
            local jitterY = math.noise(now * 13, 3.7) * 0.004 * fraction
            offset = CFrame.new(0, bob, 0) * CFrame.Angles(pitch + jitterX, jitterY, roll)
        else
            pitch = 0
        end
        lastSpeed = speed

        if shake > 0 then
            local size = shake * 0.03
            offset *= CFrame.Angles((math.random() - 0.5) * size, (math.random() - 0.5) * size, 0)
            shake = math.max(0, shake - dt * 2.5)
        end
        if offset ~= CFrame.identity then
            camera.CFrame *= offset
        end
    end)
end

function Fx.tracer(from: Vector3, to: Vector3, hitMob: boolean)
    local length = (to - from).Magnitude
    if length < 0.1 then
        return
    end
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = if hitMob then Color3.fromRGB(255, 110, 70) else Color3.fromRGB(255, 220, 150)
    part.Size = Vector3.new(0.1, 0.1, length)
    part.CFrame = CFrame.lookAt((from + to) / 2, to)
    part.Parent = folder
    TweenService:Create(part, TweenInfo.new(0.12), { Transparency = 1 }):Play()
    Debris:AddItem(part, 0.2)

    local spark = Instance.new("Part")
    spark.Anchored = true
    spark.CanCollide = false
    spark.CanQuery = false
    spark.CanTouch = false
    spark.CastShadow = false
    spark.Shape = Enum.PartType.Ball
    spark.Material = Enum.Material.Neon
    spark.Color = part.Color
    spark.Size = Vector3.new(0.6, 0.6, 0.6)
    spark.Position = to
    spark.Parent = folder
    TweenService:Create(spark, TweenInfo.new(0.15), { Transparency = 1, Size = Vector3.new(1.4, 1.4, 1.4) }):Play()
    Debris:AddItem(spark, 0.2)
end

function Fx.shake(amount: number)
    shake = math.max(shake, amount)
end

local ANIMATE_RANGE = 220 -- only lights this close to the camera bother to waver or breathe
local KEEP_LIT_RANGE = 320 -- kit lights further away are switched off (locally) to save frame time
local CULL_EVERY = 0.4

-- Where a light is: lights hang off parts or attachments.
local function lightPosition(light: Light): Vector3?
    local holder = light.Parent
    if holder and holder:IsA("BasePart") then
        return holder.Position
    elseif holder and holder:IsA("Attachment") then
        return holder.WorldPosition
    end
    return nil
end

-- A set of lights with a given tag, kept up to date as the server adds and removes them.
local function tracked(tag: string): { [Light]: number }
    local set: { [Light]: number } = {}
    local function add(instance: Instance)
        if instance:IsA("Light") then
            set[instance] = math.random() * 1000
        end
    end
    for _, instance in CollectionService:GetTagged(tag) do
        add(instance)
    end
    CollectionService:GetInstanceAddedSignal(tag):Connect(add)
    CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
        set[instance :: any] = nil
    end)
    return set
end

-- Lights that feel alive. Lantern flames ("Flicker") waver with two layers of noise; crystals ("Pulse")
-- breathe slowly, each on its own beat. Kit lights ("KitLight") far from the camera are switched off.
-- All local: the server's values never change.
local function startLights()
    local flames = tracked("Flicker")
    local crystals = tracked("Pulse")
    local kitLights = tracked("KitLight")
    local sinceCull = CULL_EVERY

    RunService.RenderStepped:Connect(function(dt: number)
        local now = os.clock()
        local eye = workspace.CurrentCamera.CFrame.Position

        sinceCull += dt
        if sinceCull >= CULL_EVERY then
            sinceCull = 0
            for light in kitLights do
                local at = lightPosition(light)
                local lit = at ~= nil and (at - eye).Magnitude < KEEP_LIT_RANGE
                -- Only write on a real change: rewriting Enabled on every light each pass kept Roblox
                -- re-lighting the scene (TRAPS #41).
                if light.Enabled ~= lit then
                    light.Enabled = lit
                end
            end
        end

        for light, seed in flames do
            local at = lightPosition(light)
            local base, amount = light:GetAttribute("Base"), light:GetAttribute("Flicker")
            if at and type(base) == "number" and type(amount) == "number" and (at - eye).Magnitude < ANIMATE_RANGE then
                local wave = math.noise(now * 2.2, seed) * 0.7 + math.noise(now * 7.5, seed + 50) * 0.3
                light.Brightness = base * (1 + amount * wave * 1.6)
            end
        end

        for light, seed in crystals do
            local at = lightPosition(light)
            local base, amount = light:GetAttribute("Base"), light:GetAttribute("Pulse")
            if at and type(base) == "number" and type(amount) == "number" and (at - eye).Magnitude < ANIMATE_RANGE then
                light.Brightness = base * (1 + amount * math.sin(now * (0.8 + seed % 0.6) + seed))
            end
        end
    end)
end

function Fx.start()
    startLights()
    local me = Players.LocalPlayer
    Remotes.Effect.OnClientEvent:Connect(function(kind: string, ...)
        local args = { ... }
        if kind == "Tracer" then
            -- The shooter already drew their own tracer the moment they fired.
            if args[1] ~= me then
                Fx.tracer(args[2], args[3], args[4] == true)
            end
        elseif kind == "Shake" then
            Fx.shake(tonumber(args[1]) or 0.3)
        end
    end)

    startRideCamera()
end

return Fx
