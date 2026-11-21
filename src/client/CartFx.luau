--!strict
-- The cart on each client: its headlamp beam and lantern light (made here, since lights the server made
-- rendered nothing on clients; TRAPS #42), wheels that turn with its speed, sparks off the wheels when braking
-- or scraping through a sharp bend, and the brake lever swinging back while braking. Drives the Motor6D joints CartService rigs on the Blender cart. Local only; nothing here
-- affects physics.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Configs = require(ReplicatedStorage.Shared.Configs)
local RunInfo = require(ReplicatedStorage.Shared.RunInfo)

local WHEEL_RADIUS = 0.98 -- art/blender/build_cart.py WHEEL_R
-- Where the front wheels meet the rails, in the cart root's space (rails at x = +/-2.5, front axle at z = -3).
local SPARK_SPOTS = { Vector3.new(-2.5, 0.1, -3), Vector3.new(2.5, 0.1, -3) }
local LEVER_PULL = math.rad(26) -- how far back the lever swings when the brake is on

local CartFx = {}

-- The face of `part` that points most nearly along `direction`.
local function faceToward(part: BasePart, direction: Vector3): Enum.NormalId
    local best, bestDot = Enum.NormalId.Front, -math.huge
    for _, face in Enum.NormalId:GetEnumItems() do
        local dot = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face)):Dot(direction)
        if dot > bestDot then
            best, bestDot = face, dot
        end
    end
    return best
end

local function lightCart(cart: Instance, root: BasePart)
    local lamp = Configs.Zones[1].Palette.Lamp
    local color = Color3.fromRGB(lamp[1], lamp[2], lamp[3])
    local lens = cart:FindFirstChild("HeadlampLens")
    if lens and lens:IsA("BasePart") and not lens:FindFirstChild("Beam") then
        local beam = Instance.new("SpotLight")
        beam.Name = "Beam"
        beam.Face = faceToward(lens, root.CFrame.LookVector)
        beam.Angle = 70
        beam.Brightness = 5
        beam.Range = Configs.Run.Cart.HeadlampRange
        beam.Color = color
        beam.Shadows = true
        beam.Enabled = false -- Fx turns it on once the camera is near (TRAPS #42)
        beam.Parent = lens
        CollectionService:AddTag(beam, "KitLight")
    end
    local glass = cart:FindFirstChild("LanternGlass")
    if glass and glass:IsA("BasePart") and not glass:FindFirstChild("Glow") then
        local glow = Instance.new("PointLight")
        glow.Name = "Glow"
        glow.Range = 16
        glow.Brightness = 1.4
        glow.Color = color
        glow:SetAttribute("Base", glow.Brightness)
        glow:SetAttribute("Flicker", 0.2)
        glow.Enabled = false
        glow.Parent = glass
        CollectionService:AddTag(glow, "Flicker")
        CollectionService:AddTag(glow, "KitLight")
    end
end

export type Sparks = { emitters: { ParticleEmitter }, flash: PointLight }

-- Sparks off the front wheels and an orange flash, for braking and for scraping through sharp bends.
local function addSparks(root: BasePart): Sparks
    local emitters: { ParticleEmitter } = {}
    for _, spot in SPARK_SPOTS do
        local attachment = Instance.new("Attachment")
        attachment.Name = "Sparks"
        attachment.Position = spot
        attachment.Parent = root
        local particles = Instance.new("ParticleEmitter")
        particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        particles.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 30))
        particles.LightEmission = 1
        particles.LightInfluence = 0
        particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
        particles.Lifetime = NumberRange.new(0.2, 0.45)
        particles.Speed = NumberRange.new(16, 30)
        particles.SpreadAngle = Vector2.new(25, 25)
        particles.EmissionDirection = Enum.NormalId.Back
        particles.Acceleration = Vector3.new(0, -70, 0)
        particles.Rate = 160
        particles.Enabled = false
        particles.Parent = attachment
        table.insert(emitters, particles)
    end
    local glow = Instance.new("Attachment")
    glow.Name = "SparkGlow"
    glow.Position = Vector3.new(0, 0.5, -3)
    glow.Parent = root
    local flash = Instance.new("PointLight")
    flash.Range = 12
    flash.Brightness = 2
    flash.Color = Color3.fromRGB(255, 140, 50)
    flash.Enabled = false
    flash.Parent = glow
    return { emitters = emitters, flash = flash }
end

function CartFx.start()
    local spin = 0
    local lever = 0
    local litCart: Instance? = nil
    local sparks: Sparks? = nil
    RunService.PreSimulation:Connect(function(dt: number)
        local run = workspace:FindFirstChild("Run")
        local cart = run and run:FindFirstChild("Cart")
        local root = cart and cart:FindFirstChild("Root")
        if not cart or not root or not root:IsA("BasePart") then
            return
        end
        if cart ~= litCart then
            litCart = cart
            lightCart(cart, root)
            sparks = addSparks(root)
        end
        local speed = RunInfo.get("Speed")
        local rolling = if type(speed) == "number" then speed else 0
        local braking = RunInfo.get("Braking") == true
        local scraping = RunInfo.get("SharpIn") == 0 and rolling > Configs.Run.Cart.SafeCurveSpeed
        local sparking = rolling > 4 and (braking or scraping)
        if sparks and sparks.flash.Enabled ~= sparking then
            sparks.flash.Enabled = sparking
            for _, particles in sparks.emitters do
                particles.Enabled = sparking
            end
        end
        -- Rolling toward -Z turns the wheels about -X.
        spin = (spin + rolling / WHEEL_RADIUS * dt) % (2 * math.pi)
        local pull = if braking then LEVER_PULL else 0
        lever += (pull - lever) * math.min(1, dt * 10)
        for _, joint in root:GetChildren() do
            if joint:IsA("Motor6D") then
                if joint.Name:match("^Wheel_") then
                    joint.Transform = CFrame.Angles(-spin, 0, 0)
                elseif joint.Name == "BrakeLeverMotor" then
                    joint.Transform = CFrame.Angles(lever, 0, 0)
                end
            end
        end
    end)
end

return CartFx
