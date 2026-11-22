--!strict
-- The game's sound, made on each client from Config/Sounds. The cart's sounds ride on the cart and follow
-- its speed, brake, sparks and the crew's lean (read from RunInfo, like CartFx); the cave hums, drips,
-- rumbles and trickles around you; one-off sounds (lever, rivets, impacts) play at a point in the world.
-- Every sound group, footsteps included, echoes like the part of the cave the cart is in (client/Acoustics).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Acoustics = require(script.Parent.Acoustics)

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
    Acoustics.dress(created)
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

-- A one-off sound at a point in the world (it cleans itself up), at `loudness` times its usual volume.
function Audio.at(name: string, position: Vector3, pitch: number?, loudness: number?)
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
    sound.Volume *= loudness or 1
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
    local leanWas = 0
    local untilStrain = 0
    local lastShift = -math.huge
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

        -- The crew throwing their weight over: the cart shifts with a creak and a clunk, and keeps straining
        -- (louder the harder they lean) while they hold it.
        local reportedLean = RunInfo.get("Lean")
        local lean = if type(reportedLean) == "number" then reportedLean else 0
        local leaning = math.abs(lean) >= 0.3
        local started = leaning and (math.abs(leanWas) < 0.3 or math.sign(lean) ~= math.sign(leanWas))
        if started and os.clock() - lastShift >= spec.LeanShift.Cooldown then
            lastShift = os.clock()
            local side = root.CFrame.RightVector * math.sign(lean) * 2
            Audio.at("LeanShift", root.Position + side, 0.9 + math.random() * 0.2)
            untilStrain = 0.8
        elseif leaning then
            untilStrain -= dt
            if untilStrain <= 0 then
                Audio.at("LeanStrain", root.Position, 0.8 + math.random() * 0.35, 0.6 + 0.4 * math.abs(lean))
                local every = spec.LeanStrain.Every
                untilStrain = every[1] + math.random() * (every[2] - every[1])
            end
        end
        leanWas = lean

        -- Timber and iron groan now and then, much more often while leaning into a bend.
        if speed > 2 then
            untilCreak -= dt
            if untilCreak <= 0 then
                Audio.at("Creak", root.Position, 0.85 + math.random() * 0.3)
                local banked = math.abs(root.CFrame.RightVector.Y) > 0.05
                local every = if banked then spec.Creak.BendEvery else spec.Creak.Every
                untilCreak = every[1] + math.random() * (every[2] - every[1])
            end
        end
    end)
end

-- Somewhere off in the dark, out of sight: a boom far below, timbers cracking, rocks falling, bat wings.
local function distant(around: Vector3)
    local spec = Sounds.Cave.Distant
    local pick = spec.Sounds[math.random(#spec.Sounds)]
    local angle = math.random() * 2 * math.pi
    local reach = spec.Range[1] + math.random() * (spec.Range[2] - spec.Range[1])
    local at = around + Vector3.new(math.cos(angle) * reach, -10 + math.random() * 30, math.sin(angle) * reach)
    local anchor = Instance.new("Attachment")
    anchor.WorldPosition = at
    anchor.Parent = workspace.Terrain
    local sound = make(pick, anchor, group("Effects", 1), false)
    sound.RollOffMinDistance = 30
    sound.RollOffMaxDistance = 260
    sound.PlaybackSpeed = 0.8 + math.random() * 0.3
    sound:Play()
    Debris:AddItem(anchor, 12)
end

-- The cave around you: a low drone and ambience bed, water running in the caverns with a lake, dripping
-- somewhere close every few seconds, and now and then something off in the dark (more often in caverns).
local function startCave()
    local ambience = group("Ambience", 0.9)
    for _, spec in { Sounds.Cave.Drone, Sounds.Cave.Ambience } do
        local bed = make(spec, SoundService, ambience, true)
        bed:Play()
    end
    local water = make(Sounds.Cave.Water, SoundService, ambience, true)
    water.Volume = 0
    local untilDistant = 3
    RunService.Heartbeat:Connect(function(dt: number)
        local space, lake = Acoustics.current()
        fade(water, if lake and space == "Cavern" then Sounds.Cave.Water.Volume else 0, dt * 0.4)
        untilDistant -= dt
        local character = Players.LocalPlayer.Character
        if untilDistant <= 0 and character then
            distant(character:GetPivot().Position)
            local every = if space == "Cavern" then Sounds.Cave.Distant.CavernEvery else Sounds.Cave.Distant.Every
            untilDistant = every[1] + math.random() * (every[2] - every[1])
        end
    end)
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

-- Footsteps, jumps and landings (Roblox's character sounds) echo through the cave too.
local function echoCharacterSounds()
    local steps = group("Steps", 1)
    local function claim(instance: Instance)
        if instance:IsA("Sound") and instance.SoundGroup == nil then
            instance.SoundGroup = steps
        end
    end
    local function watch(character: Model)
        for _, descendant in character:GetDescendants() do
            claim(descendant)
        end
        character.DescendantAdded:Connect(claim)
    end
    local function follow(player: Player)
        if player.Character then
            watch(player.Character)
        end
        player.CharacterAdded:Connect(watch)
    end
    for _, player in Players:GetPlayers() do
        follow(player)
    end
    Players.PlayerAdded:Connect(follow)
end

function Audio.start()
    Acoustics.start()
    echoCharacterSounds()
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
