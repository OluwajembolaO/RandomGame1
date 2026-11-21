--!strict
-- Every sound in the game, all free Creator Store audio (most from the Pro Sound Effects library Roblox
-- licenses for every experience). Ids were checked to load in Studio. Volume is Roblox Sound volume (0-10,
-- 0.5 is the default); client/Audio scales the cart's sounds by speed on top of these.

return {
    -- Roblox's built-in reverb preset: everything sounds like it's in a cave.
    Reverb = "Cave",

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
    },

    Weapons = {
        Rivet = { Id = 9117052716, Volume = 0.5 },
    },
}
