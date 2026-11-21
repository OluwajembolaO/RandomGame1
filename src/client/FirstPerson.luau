--!strict
-- The first-person camera (tuned in Config/Camera). Everywhere: slower, gently smoothed mouse look. While
-- riding the cart, also:
--   * the view turns with the cart through bends, eased so the cart's wobble doesn't reach it,
--   * a little roll with the cart's lean, a nod under braking, a soft bob and a wider view at speed,
--   * the knock from scraping a sharp bend too fast.
--
-- Roblox's camera builds each frame's view from the last frame's camera.CFrame, so anything layered on top
-- of it piles up frame after frame (TRAPS #43). So this runs twice a frame: before Roblox's camera update it
-- puts back the clean view from last frame (turned with the cart), and after the update it keeps only part
-- of the turn the mouse made, remembers that as the new clean view, and only then layers on the rest.
-- It stands aside whenever the camera isn't the normal first-person one (a stage's scripted camera).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tuning = require(ReplicatedStorage.Shared.Config.Camera)

local FirstPerson = {}

local player = Players.LocalPlayer
local shake = 0

local MAX_SPEED = 110 -- studs/s: anything faster is the cart being moved, not riding
local SNAP = math.rad(45) -- a bigger turn in one frame is the game setting the camera, not the mouse

local function cartRoot(): BasePart?
    local run = workspace:FindFirstChild("Run")
    local cart = run and run:FindFirstChild("Cart")
    local root = cart and cart:FindFirstChild("Root")
    return if root and root:IsA("BasePart") then root else nil
end

local function active(camera: Camera): boolean
    return camera.CameraType == Enum.CameraType.Custom and player.CameraMode == Enum.CameraMode.LockFirstPerson
end

-- Moves toward `target` at the same pace at any frame rate.
local function ease(current: number, target: number, rate: number, dt: number): number
    return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function wrap(angle: number): number
    return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function yawOf(look: Vector3): number
    return math.atan2(-look.X, -look.Z)
end

local function pitchOf(look: Vector3): number
    return math.asin(math.clamp(look.Y, -1, 1))
end

local function view(position: Vector3, yaw: number, pitch: number): CFrame
    return CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end

-- Keeps `share` of a turn, unless the turn is too big to be the mouse.
local function slowed(from: number, to: number, share: number): number
    local turn = wrap(to - from)
    return if math.abs(turn) > SNAP then to else from + turn * share
end

function FirstPerson.shake(amount: number)
    shake = math.max(shake, amount)
end

function FirstPerson.start()
    -- The view Roblox's camera should see next frame: its own, minus everything this module adds.
    local clean: CFrame? = nil
    local subject: Instance? = nil
    local handled = false
    -- Where the view was before Roblox's update (to slow the mouse), and the smoothed view shown.
    local fromYaw, fromPitch = 0, 0
    local shownYaw, shownPitch = 0, 0
    local cartYaw: number? = nil
    local lastPosition: Vector3? = nil
    local speed, lastSpeed, accel = 0, 0, 0
    local roll, nod = 0, 0
    local fov = Tuning.Fov

    RunService:BindToRenderStep("FirstPersonBefore", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
        local camera = workspace.CurrentCamera
        handled = false
        if not active(camera) then
            if clean then
                camera.CFrame = clean
            end
            clean, cartYaw = nil, nil
            return
        end
        -- A new character (or anything else to follow) starts again from Roblox's own view.
        if camera.CameraSubject ~= subject then
            subject = camera.CameraSubject
            clean, cartYaw = nil, nil
        end
        local base = clean or camera.CFrame
        local yaw, pitch = yawOf(base.LookVector), pitchOf(base.LookVector)
        if not clean then
            shownYaw, shownPitch = yaw, pitch
        end

        -- Turn with the cart: follow its eased heading, so a bend swings the view around with it.
        local root = if player:GetAttribute("Riding") == true then cartRoot() else nil
        if root then
            local heading = yawOf(root.CFrame.LookVector)
            local before = cartYaw or heading
            local after = before + wrap(heading - before) * (1 - math.exp(-Tuning.FollowRate * dt))
            cartYaw = after
            local turn = wrap(after - before)
            yaw += turn
            shownYaw += turn
        else
            cartYaw = nil
        end

        fromYaw, fromPitch = yaw, pitch
        camera.CFrame = view(base.Position, yaw, pitch)
        handled = true
    end)

    RunService:BindToRenderStep("FirstPersonAfter", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
        if not handled then
            return
        end
        local camera = workspace.CurrentCamera
        local riding = player:GetAttribute("Riding") == true
        local root = if riding then cartRoot() else nil

        -- Speed from the cart's own movement every frame (the server's Speed is rounded and arrives in steps).
        local measured = 0
        if root then
            local position = root.Position
            if lastPosition and dt > 0 then
                measured = math.min((position - lastPosition).Magnitude / dt, MAX_SPEED)
            end
            lastPosition = position
        else
            lastPosition = nil
        end
        speed = ease(speed, measured, 3, dt)
        accel = ease(accel, (speed - lastSpeed) / math.max(dt, 1e-3), 2, dt)
        lastSpeed = speed
        local fraction = math.clamp(speed / Tuning.TopSpeed, 0, 1)

        fov = ease(fov, Tuning.Fov + Tuning.FovAtSpeed * fraction, 2.5, dt)
        camera.FieldOfView = fov

        -- Slow the mouse: keep only part of the turn Roblox's camera just made.
        local fresh = camera.CFrame
        local share = if riding then Tuning.RideSensitivity else Tuning.Sensitivity
        local yaw = slowed(fromYaw, yawOf(fresh.LookVector), share)
        local pitch = slowed(fromPitch, pitchOf(fresh.LookVector), share)
        clean = view(fresh.Position, yaw, pitch)

        -- Glide the shown view toward it.
        local glide = 1 - math.exp(-Tuning.LookRate * dt)
        shownYaw += wrap(yaw - shownYaw) * glide
        shownPitch += (pitch - shownPitch) * glide

        -- The ride on top (all of it settles back to nothing off the cart).
        local lean = if root then math.asin(math.clamp(root.CFrame.RightVector.Y, -1, 1)) else 0
        roll = ease(roll, lean * Tuning.LeanFollow, Tuning.LeanRate, dt)
        local nodTarget = if root then math.clamp(accel * Tuning.NodPerAccel, -Tuning.NodDown, Tuning.NodUp) else 0
        nod = ease(nod, math.rad(nodTarget), Tuning.NodRate, dt)
        local now = os.clock()
        local bob = math.noise(now * Tuning.BobSpeed, 1.3) * Tuning.Bob * fraction
        local knockX, knockY = 0, 0
        if shake > 0 then
            local size = math.rad(Tuning.Shake) * shake
            knockX = math.noise(now * 22, 4.2) * size
            knockY = math.noise(now * 19, 8.6) * size
            shake = math.max(0, shake - dt * Tuning.ShakeFade)
        end

        camera.CFrame = view(fresh.Position + Vector3.new(0, bob, 0), shownYaw, shownPitch)
            * CFrame.Angles(nod + knockX, knockY, roll)
    end)
end

return FirstPerson
