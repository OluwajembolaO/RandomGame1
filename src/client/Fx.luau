--!strict
-- Client-side effects: rivet tracers and camera shake. Listens to the server's Effect remote.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Fx = {}

local folder = Instance.new("Folder")
folder.Name = "ClientFx"
folder.Parent = workspace

local shake = 0

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

function Fx.start()
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

    RunService:BindToRenderStep("CartShake", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
        if shake <= 0 then
            return
        end
        local camera = workspace.CurrentCamera
        local size = shake * 0.03
        camera.CFrame *= CFrame.Angles((math.random() - 0.5) * size, (math.random() - 0.5) * size, 0)
        shake = math.max(0, shake - dt * 2.5)
    end)
end

return Fx
