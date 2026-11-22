-- The descent, top to bottom. Each zone gets weirder: its own palette, monsters, stop pool and boss genre.
-- Only zone 1 is built for the prototype; the rest are the roadmap.
-- Not --!strict: built and unbuilt zones have different fields (TRAPS #21). Tests check the data.

-- Straight chunks a jump can take its run-up from.
local RUN_UPS =
    { "Tunnel_Straight", "Tunnel_Crystal", "Tunnel_Fungus", "Tunnel_Grotto", "Tunnel_Steep", "Tunnel_Plunge" }

return {
    {
        Id = "OldMine",
        Name = "The Old Mine",
        Built = true,
        -- Colors as {r, g, b} 0-255. Kit lights name these (Lamp, Blue, Green, Red, Yellow).
        Palette = {
            RockDark = { 46, 40, 36 },
            Timber = { 110, 78, 48 },
            Rail = { 120, 116, 110 },
            Lamp = { 255, 176, 92 },
            Shaft = { 170, 200, 255 }, -- light falling through cracks in a cavern ceiling
            Mist = { 150, 190, 195 },
            Blue = { 50, 130, 255 },
            Green = { 50, 255, 130 },
            Red = { 255, 50, 70 },
            Yellow = { 255, 200, 50 },
        },
        -- The zone's lighting. Deeper zones swap these for stranger moods.
        Mood = {
            -- Base light everywhere the lamps don't reach: dim and cool, so the rock always has a shape.
            Ambient = { 46, 44, 56 },
            -- Thin haze only. There's no sun in a cave, so the haze is near black: thick haze (0.4) swallowed
            -- everything past ~20 studs and the cave read as pitch black.
            Atmosphere = { Density = 0.14, Offset = 0, Color = { 46, 52, 64 }, Decay = { 24, 26, 34 }, Haze = 0.4 },
            Exposure = 0.3, -- Lighting.ExposureCompensation
            Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.2 },
            Grade = { Brightness = 0.02, Contrast = 0.14, Saturation = 0, Tint = { 255, 244, 232 } },
            Flicker = 0.18, -- how much lantern flames waver
            Pulse = 0.3, -- how much crystal light breathes
            -- Kit crystal and mushroom lights are scaled by these: at full strength they flooded whole caverns
            -- with color, so the glow should come from the crystals with the rock staying mostly dark.
            CrystalLight = { Brightness = 0.55, Range = 0.75 },
            ShaftOpacity = 0.35, -- 1 = the original strength of the light-shaft beams
        },
        -- The cave, snapped together from the Blender kit's chunks (Config/KitData) one segment at a time,
        -- like DOORS rooms (Rules/Kit): each segment is drawn by Weight from the chunks that fit there. Tier
        -- is how hard a chunk is (1 easy, 2 medium, 3 hard); each leg's Difficulty scales the weights by tier.
        Kit = {
            Station = "Station",
            Stop = "StopChamber",
            Cap = "EndCap",
            Straight = "Tunnel_Straight", -- run-ups, and the fallback when nothing else fits
            Chunks = {
                -- Straights: plain, crystal-studded, fungus-choked, a wide grotto; a steep drop and a plunge.
                { Id = "Tunnel_Straight", Weight = 14, Tier = 1 },
                { Id = "Tunnel_Crystal", Weight = 6, Tier = 1 },
                { Id = "Tunnel_Fungus", Weight = 6, Tier = 1 },
                { Id = "Tunnel_Grotto", Weight = 5, Tier = 1 },
                { Id = "Tunnel_Steep", Weight = 4, Tier = 2, Tag = "Steep" },
                { Id = "Tunnel_Plunge", Weight = 4, Tier = 3, Tag = "Steep" },
                -- Bends: normal, gentle and long sweeping ones.
                { Id = "Tunnel_BendL", Weight = 10, Tier = 1, Tag = "Bend" },
                { Id = "Tunnel_BendR", Weight = 10, Tier = 1, Tag = "Bend" },
                { Id = "Tunnel_GentleL", Weight = 7, Tier = 1, Tag = "Bend" },
                { Id = "Tunnel_GentleR", Weight = 7, Tier = 1, Tag = "Bend" },
                { Id = "Tunnel_LongBendL", Weight = 6, Tier = 1, Tag = "Bend" },
                { Id = "Tunnel_LongBendR", Weight = 6, Tier = 1, Tag = "Bend" },
                -- Sharp bends and hairpins: brake, or lean hard.
                { Id = "Tunnel_SharpL", Weight = 6, Tier = 2, Tag = "Sharp" },
                { Id = "Tunnel_SharpR", Weight = 6, Tier = 2, Tag = "Sharp" },
                { Id = "Tunnel_HairpinL", Weight = 3, Tier = 3, Tag = "Sharp" },
                { Id = "Tunnel_HairpinR", Weight = 3, Tier = 3, Tag = "Sharp" },
                { Id = "Tunnel_HairpinSteepL", Weight = 3, Tier = 3, Tag = "Sharp" },
                { Id = "Tunnel_HairpinSteepR", Weight = 3, Tier = 3, Tag = "Sharp" },
                -- Broken track to jump (Rules/Jump), always straight after a straight run-up.
                { Id = "Tunnel_Washout", Weight = 5, Tier = 1, Tag = "Gap", After = RUN_UPS },
                { Id = "Tunnel_Chute", Weight = 3, Tier = 1, Tag = "Gap", After = RUN_UPS },
                { Id = "Tunnel_WashoutWide", Weight = 3, Tier = 2, Tag = "Gap", After = RUN_UPS },
                { Id = "Tunnel_WashoutHuge", Weight = 3, Tier = 3, Tag = "Gap", After = RUN_UPS },
                -- Three-way splits (Rules/Split): lean onto the open line; the other two end at buffer stops.
                { Id = "Tunnel_Junction", Weight = 5, Tier = 2, Tag = "Split" },
                { Id = "Tunnel_JunctionTight", Weight = 4, Tier = 3, Tag = "Split" },
                -- Caverns (the rifts and the abyss are broken trestles to jump).
                { Id = "Cavern_Lake", Weight = 4, Tier = 1, Tag = "Cavern" },
                { Id = "Cavern_Garden", Weight = 4, Tier = 1, Tag = "Cavern" },
                { Id = "Cavern_Crystal", Weight = 4, Tier = 1, Tag = "Cavern" },
                { Id = "Cavern_Pool", Weight = 4, Tier = 1, Tag = "Cavern" },
                { Id = "Cavern_Glow", Weight = 4, Tier = 1, Tag = "Cavern" },
                { Id = "Cavern_Chasm", Weight = 4, Tier = 2, Tag = "Cavern" },
                { Id = "Cavern_Pit", Weight = 4, Tier = 2, Tag = "Cavern" },
                { Id = "Cavern_Rift", Weight = 4, Tier = 2, Tag = "Cavern" },
                { Id = "Cavern_RiftWide", Weight = 3, Tier = 3, Tag = "Cavern" },
                { Id = "Cavern_Abyss", Weight = 3, Tier = 3, Tag = "Cavern" },
            },
            -- How far apart each kind turns up, in segments: never closer than Spacing[1], and forced once
            -- Spacing[2] have gone by. NoRepeat: never the same chunk twice running. NotAfter: never straight
            -- after one of these (no sharp bend right after landing a jump or a split, no bend straight after a
            -- steep drop: room to slow down).
            Tags = {
                Sharp = { Spacing = { 3, 6 }, NotAfter = { "Gap", "Steep", "Split" } },
                Bend = { Spacing = { 0, 99 }, NotAfter = { "Steep" } },
                Gap = { Spacing = { 4, 9 } },
                Split = { Spacing = { 6, 14 } },
                Steep = { Spacing = { 2, 99 } },
                Cavern = { Spacing = { 4, 8 }, NoRepeat = true },
            },
            EveryLeg = { "Cavern", "Sharp" }, -- every leg has at least one of each (unless its Difficulty says)
            -- Leg difficulties: Tiers scales chunk weights by tier (easy, medium, hard), Spacing tightens tag
            -- spacing, EveryLeg adds tags the leg must have.
            Difficulty = {
                Easy = { Tiers = { 1, 0.35, 0 }, EveryLeg = { "Cavern", "Sharp" } },
                Medium = { Tiers = { 0.7, 1, 0.3 }, EveryLeg = { "Cavern", "Split", "Sharp" } },
                Hard = {
                    Tiers = { 0.35, 0.9, 1.5 },
                    Spacing = { Sharp = { 2, 5 }, Gap = { 3, 7 }, Split = { 5, 10 } },
                    EveryLeg = { "Cavern", "Gap", "Split", "Sharp" },
                },
            },
            EdgeTunnels = 2, -- plain tunnel segments at each end of a leg, between caverns and stops
            -- The track never turns further than this from the zone's heading, so it can't loop over itself.
            MaxHeading = 1.4,
        },
        Mobs = { "Crawler", "Bat" },
        -- 125 segments in all: 30 easy, 45 medium and 50 hard, a stop after each stretch, getting
        -- harder toward the end.
        Legs = {
            { Ride = { Segments = 30, Difficulty = "Easy", Ambushes = { 2, 3 } }, Stop = { Stage = "Obby" } },
            {
                Ride = { Segments = 45, Difficulty = "Medium", Ambushes = { 3, 4 } },
                Stop = { Fork = { "SignalRoom", "SupplyDepot" }, Options = 2 },
            },
            {
                Ride = { Segments = 50, Difficulty = "Hard", Ambushes = { 4, 5 } },
                Stop = { Stage = "ForemanBoss" },
            },
        },
    },
    { Id = "CrystalHollows", Name = "Crystal Hollows", Built = false },
    { Id = "FungalDeep", Name = "Fungal Deep", Built = false },
    { Id = "DrownedWorks", Name = "The Drowned Works", Built = false },
    { Id = "BoneCatacombs", Name = "Bone Catacombs", Built = false },
    { Id = "Hell", Name = "Hell", Built = false },
}
