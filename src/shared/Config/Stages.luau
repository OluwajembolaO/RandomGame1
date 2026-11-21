-- Every stop the cart can pull into. Each stage is a different genre with its own camera and controls.
-- Every stage is played in the cave kit's stop chamber (Config/KitData StopChamber).
-- Not --!strict: stages have different fields (TRAPS #21). Tests check the data.

return {
    Obby = {
        Name = "The Collapsed Shaft",
        Genre = "Obby",
        Kind = "Minigame",
        Blurb = "Hold the plates for each other. Everyone reaches the exit.",
        TimeLimit = 240,
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
    },

    SupplyDepot = {
        Name = "Supply Depot",
        Genre = "Rest",
        Kind = "Rest",
        Blurb = "Patch up the crew and the cart.",
        Repair = 80,
        RestSeconds = 15,
    },

    ForemanBoss = {
        Name = "The Foreman",
        Genre = "FPS",
        Kind = "Boss",
        Blurb = "Hold both generators to drop its shield. Shoot.",
    },
}
