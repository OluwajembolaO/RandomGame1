-- The descent, top to bottom. Each zone gets weirder: its own palette, monsters, stop pool and boss genre.
-- Only zone 1 is built for the prototype; the rest are the roadmap.
-- Not --!strict: built and unbuilt zones have different fields (TRAPS #21). Tests check the data.

return {
    {
        Id = "OldMine",
        Name = "The Old Mine",
        Built = true,
        -- Colors as {r, g, b} 0-255.
        Palette = {
            Rock = { 74, 64, 56 },
            RockDark = { 46, 40, 36 },
            Timber = { 110, 78, 48 },
            Rail = { 120, 116, 110 },
            Lamp = { 255, 176, 92 },
        },
        Mobs = { "Crawler", "Bat" },
        Legs = {
            { Ride = { Length = 1300, Ambushes = { 2, 3 } }, Stop = { Stage = "Obby" } },
            {
                Ride = { Length = 1300, Ambushes = { 3, 4 } },
                Stop = { Fork = { "SignalRoom", "SupplyDepot" }, Options = 2 },
            },
            { Ride = { Length = 1500, Ambushes = { 4, 5 } }, Stop = { Stage = "ForemanBoss" } },
        },
        -- Track shape. Lengths are horizontal studs, turns are radians, grade is drop per stud.
        Track = {
            Grade = { 0.04, 0.09 },
            StraightLength = { 80, 200 },
            CurveLength = { 80, 160 },
            CurveTurn = { 0.3, 0.7 },
            -- Every SharpEvery-th curve is a sharp one that needs the brake.
            SharpEvery = 3,
            SharpLength = { 40, 70 },
            SharpTurn = { 0.9, 1.3 },
            -- The track never turns further than this from the zone's heading, so it can't loop over itself.
            MaxHeading = 1.4,
        },
    },
    { Id = "CrystalHollows", Name = "Crystal Hollows", Built = false },
    { Id = "FungalDeep", Name = "Fungal Deep", Built = false },
    { Id = "DrownedWorks", Name = "The Drowned Works", Built = false },
    { Id = "BoneCatacombs", Name = "Bone Catacombs", Built = false },
    { Id = "Hell", Name = "Hell", Built = false },
}
