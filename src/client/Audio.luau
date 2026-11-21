--!strict
-- The game's sound, made on each client from Config/Sounds. The cart's sounds ride on the cart and follow
-- its speed, brake and sparks (read from RunInfo, like CartFx); the cave hums and drips around you; one-off
-- sounds (lever, rivets, impacts) play at a point in the world. Everything gets Roblox's cave reverb.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Remotes = require(Shared.Remotes)
local RunInfo = require(Shared.RunInfo)

local Sounds = require(Shared.Config.Sounds)

local TOP_SPEED = Configs.Run.Cart.Speed * 1.3 -- the rattle tops out around a pushed run downhill
local CART_HEARING = 220 -- studs: how far away other players hear a passing cart

local Audio = {}

local groups: { [string]: SoundGroup } = {}

local function group(name: string, volume: number): SoundGroup
    local existing = groups[name]
    if existing then
        return existing
    end
    local created = Instance.new("SoundGroup")
    created.Name = name
    created.Volume = volume
    created.Parent = SoundService
    groups[name] = created
    return created
end

local function make(
    spec: { Id: number, Volume: number },
    parent: Instance,
    soundGroup: SoundGroup,
    looped: boolean
): Sound
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. spec.Id
    sound.Volume = spec.Volume
    sound.Looped = looped
    sound.SoundGroup = soundGroup
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.RollOffMinDistance = 10
    sound.RollOffMaxDistance = CART_HEARING
    sound.Parent = parent
    return sound
end

-- A one-off sound at a point in the world (it cleans itself up).
function Audio.at(name: string, position: Vector3, pitch: number?)
    local sections: { any } = { Sounds.Cart, Sounds.Station, Sounds.Weapons, Sounds.Cave }
    local spec = nil
    for _, section in sections do
        spec = spec or section[name]
    end
    if not spec then
        return
    end
    local anchor = Instance.new("Attachment")
    anchor.WorldPosition = position
    anchor.Parent = workspace.Terrain
    local sound = make(spec, anchor, group("Effects", 1), false)
    sound.PlaybackSpeed = pitch or (0.92 + math.random() * 0.16)
    sound:Play()
    Debris:AddItem(anchor, math.max(2, sound.TimeLength + 0.5) + 6)
end

type CartSounds = {
    rolling: Sound,
    wind: Sound,
    squeal: Sound,
    sparks: Sound,
    root: BasePart,
}

local function cartSounds(root: BasePart): CartSounds
    local cart = group("Cart", 1)
    local spec = Sounds.Cart
    return {
        rolling = make(spec.Rolling, root, cart, true),
        wind = make(spec.Wind, root, cart, true),
        squeal = make(spec.Squeal, root, cart, true),
        sparks = make(spec.Sparks, root, cart, true),
        root = root,
    }
end

-- Turns a looping sound up or down toward `volume`, starting and stopping it as needed.
local function fade(sound: Sound, volume: number, dt: number)
    sound.Volume += (volume - sound.Volume) * math.min(1, dt * 6)
    if volume > 0.01 and not sound.IsPlaying then
        sound:Play()
    elseif volume <= 0.01 and sound.Volume < 0.01 and sound.IsPlaying then
        sound:Stop()
    end
end

local function startCart()
    local current: CartSounds? = nil
    local wasBraking = false
    local untilCreak = 4
    RunService.Heartbeat:Connect(function(dt: number)
        local run = workspace:FindFirstChild("Run")
        local cart = run and run:FindFirstChild("Cart")
        local root = cart and cart:FindFirstChild("Root")
        if not root or not root:IsA("BasePart") then
            current = nil
            return
        end
        if not current or current.root ~= root then
            current = cartSounds(root)
        end
        local sounds = current :: CartSounds
        local spec = Sounds.Cart

        local reported = RunInfo.get("Speed")
        local speed = if type(reported) == "number" then reported else 0
        local fraction = math.clamp(speed / TOP_SPEED, 0, 1.2)
        local braking = RunInfo.get("Braking") == true and speed > 3
        -- Lifting onto two wheels in a bend screams; in the air the wheels go quiet and the wind roars.
        local tilt = RunInfo.get("Tilt")
        local lift = if type(tilt) == "number" then tilt else 0
        local scraping = lift > 0.15
        local airborne = RunInfo.get("Airborne") == true

        local rollingVolume = spec.Rolling.Volume * (0.35 + 0.65 * fraction)
        fade(sounds.rolling, if speed > 0.5 and not airborne then rollingVolume else 0, dt)
        sounds.rolling.PlaybackSpeed = spec.Rolling.SlowPitch
            + (spec.Rolling.FastPitch - spec.Rolling.SlowPitch) * fraction
        fade(sounds.wind, spec.Wind.Volume * (if airborne then 1.6 else fraction * fraction), dt)

        -- The brake screams at speed and winds down in pitch as the cart slows.
        local squealSpec = spec.Squeal
        local slowing = math.clamp(speed / Configs.Run.Cart.Speed, 0, 1)
        local brakeVolume = squealSpec.Volume * (squealSpec.BrakeQuiet + (1 - squealSpec.BrakeQuiet) * slowing)
        local scrapeVolume = squealSpec.ScrapeVolume * (0.5 + 0.5 * lift)
        local squeal = if airborne then 0 elseif scraping then scrapeVolume elseif braking then brakeVolume else 0
        fade(sounds.squeal, squeal, dt)
        sounds.squeal.PlaybackSpeed = if scraping
            then squealSpec.ScrapePitch
            else squealSpec.BrakeSlowPitch + (squealSpec.BrakeFastPitch - squealSpec.BrakeSlowPitch) * slowing
        fade(sounds.sparks, if (scraping or braking) and not airborne then spec.Sparks.Volume else 0, dt)

        if braking and not wasBraking then
            Audio.at("BrakeClunk", root.Position)
        end
        wasBraking = braking

        -- Timber and iron groan now and then, much more often while leaning into a bend.
        if speed > 2 then
            untilCreak -= dt
            if untilCreak <= 0 then
                Audio.at("Creak", root.Position, 0.85 + math.random() * 0.3)
                local leaning = math.abs(root.CFrame.RightVector.Y) > 0.05
                local every = if leaning then spec.Creak.BendEvery else spec.Creak.Every
                untilCreak = every[1] + math.random() * (every[2] - every[1])
            end
        end
    end)
end

-- The cave around you: a low drone and ambience bed, and water dripping somewhere close every few seconds.
local function startCave()
    local ambience = group("Ambience", 0.9)
    for _, spec in { Sounds.Cave.Drone, Sounds.Cave.Ambience } do
        local bed = make(spec, SoundService, ambience, true)
        bed:Play()
    end
    local drip = Sounds.Cave.Drip
    local untilDrip = 2
    RunService.Heartbeat:Connect(function(dt: number)
        untilDrip -= dt
        if untilDrip > 0 then
            return
        end
        untilDrip = drip.Every[1] + math.random() * (drip.Every[2] - drip.Every[1])
        local character = Players.LocalPlayer.Character
        if not character then
            return
        end
        local spread = drip.Spread
        local around = character:GetPivot().Position
            + Vector3.new((math.random() - 0.5) * spread, 6 + math.random() * 12, (math.random() - 0.5) * spread)
        Audio.at("Drip", around, 0.8 + math.random() * 0.5)
    end)
end

local IMPACT_EVERY = 1.2 -- the server shakes every 0.35 s up on two wheels; one knock per this long is plenty

function Audio.start()
    SoundService.AmbientReverb = (Enum.ReverbType :: any)[Sounds.Reverb] or Enum.ReverbType.Cave
    startCave()
    startCart()
    local lastImpact = 0
    Remotes.Effect.OnClientEvent:Connect(function(kind: string, ...)
        local args = { ... }
        if kind == "Sound" and type(args[1]) == "string" and typeof(args[2]) == "Vector3" then
            Audio.at(args[1], args[2])
        elseif kind == "Shake" and os.clock() - lastImpact >= IMPACT_EVERY then
            lastImpact = os.clock()
            local root = workspace:FindFirstChild("Run") and workspace.Run:FindFirstChild("Cart")
            local at = root and root:FindFirstChild("Root")
            if at and at:IsA("BasePart") then
                Audio.at("Impact", at.Position)
            end
        end
    end)
end

return Audio
