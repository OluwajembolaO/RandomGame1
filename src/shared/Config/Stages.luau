-- Every stop the cart can pull into. Each stage is a different genre with its own camera and controls.
-- Length and Drop are how far the placeholder arena runs along the track (TrackIn to TrackOut);
-- an authored arena's TrackIn/TrackOut markers win over these.
-- Not --!strict: stages have different fields (TRAPS #21). Tests check the data.

return {
    Obby = {
        Name = "The Collapsed Shaft",
        Genre = "Obby",
        Kind = "Minigame",
        Blurb = "Hold the plates for each other. Everyone reaches the exit.",
        TimeLimit = 240,
        Length = 180,
        Drop = 12,
    },

    SignalRoom = {
        Name = "The Signal Room",
        Genre = "PointAndClick",
        Kind = "Minigame",
        Blurb = "One of you has the keypad. The rest have the clues. Talk.",
        TimeLimit = 240,
        CodeLength = 4,
        Symbols = { "Gear", "Skull", "Gem", "Lamp", "Pick", "Bat", "Flame", "Key" },
        WrongCodeDamage = 30, -- cart HP
        WrongCodeCrawlers = 2,
        Length = 90,
        Drop = 0,
    },

    SupplyDepot = {
        Name = "Supply Depot",
        Genre = "Rest",
        Kind = "Rest",
        Blurb = "Patch up the crew and the cart.",
        Repair = 80,
        RestSeconds = 15,
        Length = 70,
        Drop = 0,
    },

    ForemanBoss = {
        Name = "The Foreman",
        Genre = "FPS",
        Kind = "Boss",
        Blurb = "Hold both generators to drop its shield. Shoot.",
        Length = 160,
        Drop = 0,
    },
}
