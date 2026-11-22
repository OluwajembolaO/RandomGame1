--!strict
-- Every sound in the game, all free Creator Store audio (most from the Pro Sound Effects library Roblox
-- licenses for every experience). Ids were checked to load in Studio. Volume is Roblox Sound volume (0-10,
-- 0.5 is the default); client/Audio scales the cart's sounds by speed on top of these.

return {
    -- How the cave sounds (client/Acoustics): reverb, echo and a little muffle on every sound, set by the kind
    -- of space the cart is in and eased from one to the next over Blend seconds. DecayTime and echo Delay are
    -- seconds; Wet, Dry, EchoWet and HighGain are dB; Density, Diffusion and EchoFeedback 0-1.
    Acoustics = {
        Blend = 1.5,
        -- The tunnels: close rock walls, a short bright slap-back.
        Tunnel = {
            DecayTime = 1.6,
            Density = 0.9,
            Diffusion = 0.7,
            Wet = -8,
            Dry = 0,
            EchoDelay = 0.12,
            EchoFeedback = 0.22,
            EchoWet = -13,
            HighGain = -3,
        },
        -- The caverns: huge and hollow, every sound rolling away and coming back.
        Cavern = {
            DecayTime = 6,
            Density = 0.7,
            Diffusion = 0.85,
            Wet = -4,
            Dry = -1,
            EchoDelay = 0.45,
            EchoFeedback = 0.4,
            EchoWet = -8,
            HighGain = -6,
        },
        -- The station and stop chambers: big rooms of timber and rock.
        Chamber = {
            DecayTime = 3,
            Density = 0.85,
            Diffusion = 0.8,
            Wet = -6,
            Dry = 0,
            EchoDelay = 0.24,
            EchoFeedback = 0.3,
            EchoWet = -11,
            HighGain = -4,
        },
    },

    Cart = {
        -- Rail clatter, louder and higher-pitched the faster the cart goes.
        Rolling = { Id = 9113120822, Volume = 0.7, SlowPitch = 0.55, FastPitch = 1.15 },
        -- Air rushing past at speed.
        Wind = { Id = 9125742262, Volume = 0.45 },
        -- Wheels screeching on the rails while braking: loudest and highest at speed, dropping in pitch as
        -- the cart slows (BrakeQuiet of the volume at a crawl). Higher still scraping a sharp bend too fast.
        Squeal = {
            Id = 3277777247,
            Volume = 1.1,
            BrakeQuiet = 0.45,
            BrakeSlowPitch = 0.8,
            BrakeFastPitch = 1.15,
            ScrapePitch = 1.3,
            ScrapeVolume = 0.9,
        },
        -- Crackle of the sparks flying off the wheels.
        Sparks = { Id = 9112780743, Volume = 0.6 },
        -- The brake clamping on.
        BrakeClunk = { Id = 9125626484, Volume = 0.6 },
        -- Timber and iron groaning; more often in bends.
        Creak = { Id = 9126282474, Volume = 0.45, Every = { 5, 11 }, BendEvery = { 1.5, 3.5 } },
        -- The crew throwing their weight over: the whole cart shifts and creaks when they lean, and keeps
        -- straining (Strain, every Every seconds, louder the harder they lean) while they hold it.
        LeanShift = { Id = 9120829478, Volume = 0.6, Cooldown = 2.5 }, -- no more than one every Cooldown s
        LeanStrain = { Id = 9120831000, Volume = 0.55, Every = { 0.7, 1.4 } },
        -- A hard knock while the cart rattles up on two wheels.
        Impact = { Id = 9116699196, Volume = 0.8 },
        -- The cart going over on its side: wood and iron crashing down.
        Crash = { Id = 9120188618, Volume = 1.2 },
        -- Slamming back down on the far side of a gap.
        Land = { Id = 9113525643, Volume = 1.1 },
    },

    Station = {
        Lever = { Id = 9125626478, Volume = 0.9 },
    },

    Cave = {
        Drone = { Id = 9112795571, Volume = 0.35 },
        Ambience = { Id = 273398061, Volume = 0.3 },
        -- Water dripping somewhere near you, every few seconds.
        Drip = { Id = 9114176498, Volume = 0.5, Every = { 1.2, 4.5 }, Spread = 30 },
        -- Somewhere off in the dark: one of these every so often (more often in caverns), Range studs away.
        Distant = {
            Every = { 5, 12 },
            CavernEvery = { 2.5, 7 },
            Range = { 40, 110 },
            Sounds = {
                { Id = 9119387133, Volume = 0.9 }, -- a deep boom somewhere far below
                { Id = 9119388187, Volume = 0.8 },
                { Id = 9126239755, Volume = 0.7 }, -- old timbers groaning and cracking
                { Id = 9118588970, Volume = 0.8 }, -- rocks dropping and rolling
                { Id = 9118770617, Volume = 0.6 }, -- grit trickling down the walls
                { Id = 9118689176, Volume = 0.6 }, -- stones knocking together
                { Id = 9125386815, Volume = 0.7 }, -- a burst of bat wings
            },
        },
        -- Running water, in the caverns with a lake.
        Water = { Id = 9119647414, Volume = 0.55 },
    },

    Weapons = {
        Rivet = { Id = 9117052716, Volume = 0.5 },
    },
}
