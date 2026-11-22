--!strict
-- Makes the cave sound like a cave. Every sound group (client/Audio's, and the one for footsteps and other
-- character sounds) gets a reverb, an echo and a little high-end muffle, set from Config/Sounds Acoustics by
-- the kind of space the cart is in: tight in the tunnels, a long rolling echo in the caverns, in between in
-- the station and stop chambers. As the cart rides from one to the next, the sound eases over.
-- The space comes from the route laid out from the run's seed (Rules/Layout, the same on every client) and
-- the cart's distance along it (RunInfo.Distance).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local Route = require(Shared.Rules.Route)
local RunInfo = require(Shared.RunInfo)
local Sounds = require(Shared.Config.Sounds)

local Acoustics = {}

local SETTINGS = Sounds.Acoustics
local CHECK_EVERY = 0.25

type Chain = { reverb: ReverbSoundEffect, echo: EchoSoundEffect, eq: EqualizerSoundEffect }

local chains: { Chain } = {}
local space = "Chamber" -- the station, where every run starts
local lake = false

-- The kind of space a kit piece is: its own big room, a cavern, or a tunnel.
local function spaceOf(kind: string): string
    if kind == "Cavern" then
        return "Cavern"
    elseif kind == "Tunnel" then
        return "Tunnel"
    end
    return "Chamber"
end

local function targets(name: string): ({ [string]: number }, { [string]: number }, { [string]: number })
    local preset = SETTINGS[name]
    return {
        DecayTime = preset.DecayTime,
        Density = preset.Density,
        Diffusion = preset.Diffusion,
        WetLevel = preset.Wet,
        DryLevel = preset.Dry,
    }, { Delay = preset.EchoDelay, Feedback = preset.EchoFeedback, WetLevel = preset.EchoWet, DryLevel = 0 }, {
        HighGain = preset.HighGain,
        MidGain = 0,
        LowGain = 0,
    }
end

-- Puts a reverb, echo and EQ on a sound group, set to the current space.
function Acoustics.dress(group: SoundGroup)
    local reverb = Instance.new("ReverbSoundEffect")
    reverb.Priority = 3
    local echo = Instance.new("EchoSoundEffect")
    echo.Priority = 2
    local eq = Instance.new("EqualizerSoundEffect")
    eq.Priority = 1
    local reverbProps, echoProps, eqProps = targets(space)
    for key, value in reverbProps do
        (reverb :: any)[key] = value
    end
    for key, value in echoProps do
        (echo :: any)[key] = value
    end
    for key, value in eqProps do
        (eq :: any)[key] = value
    end
    reverb.Parent, echo.Parent, eq.Parent = group, group, group
    table.insert(chains, { reverb = reverb, echo = echo, eq = eq })
end

-- The kind of space the cart is in ("Tunnel", "Cavern" or "Chamber"), and whether it has a lake.
function Acoustics.current(): (string, boolean)
    return space, lake
end

local function blendTo(name: string)
    local info = TweenInfo.new(SETTINGS.Blend, Enum.EasingStyle.Sine)
    local reverbProps, echoProps, eqProps = targets(name)
    for _, chain in chains do
        TweenService:Create(chain.reverb, info, reverbProps):Play()
        TweenService:Create(chain.echo, info, echoProps):Play()
        TweenService:Create(chain.eq, info, eqProps):Play()
    end
end

function Acoustics.start()
    -- These effects replace Roblox's one-size-fits-all reverb preset.
    SoundService.AmbientReverb = Enum.ReverbType.NoReverb
    local layout: Layout.Layout? = nil
    local seedSeen = 0
    task.spawn(function()
        while true do
            local seed = RunInfo.get("Seed")
            if type(seed) == "number" and seed ~= seedSeen then
                seedSeen = seed
                local zone = Configs.Zones[1]
                layout = if seed ~= 0
                    then Layout.build(
                        Route.generate(zone, seed),
                        zone.Kit,
                        Configs.Kit.Pieces,
                        Layout.spec(Configs.Run)
                    )
                    else nil
            end
            local route = layout
            local distance = RunInfo.get("Distance")
            if route and type(distance) == "number" then
                local placement = route.placements[Layout.placementAt(route, distance)]
                local def = Configs.Kit.Pieces[placement.piece]
                local now = spaceOf(def.Kind)
                lake = def.Lake ~= nil
                if now ~= space then
                    space = now
                    blendTo(now)
                end
            end
            task.wait(CHECK_EVERY)
        end
    end)
end

return Acoustics
