-- The descent, top to bottom. Each zone gets weirder: its own palette, monsters, stop pool and boss genre.
-- Only zone 1 is built for the prototype; the rest are the roadmap.
-- Not --!strict: built and unbuilt zones have different fields (TRAPS #21). Tests check the data.

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
        -- like DOORS rooms (Rules/Kit): each segment is drawn by Weight from the chunks that fit there.
        Kit = {
            Station = "Station",
            Stop = "StopChamber",
            Cap = "EndCap",
            Straight = "Tunnel_Straight", -- run-ups, and the fallback when nothing else fits
            Chunks = {
                -- Straights: plain, crystal-studded, fungus-choked, a steep fast drop, a wide grotto.
                { Id = "Tunnel_Straight", Weight = 14 },
                { Id = "Tunnel_Crystal", Weight = 6 },
                { Id = "Tunnel_Fungus", Weight = 6 },
                { Id = "Tunnel_Steep", Weight = 4 },
                { Id = "Tunnel_Grotto", Weight = 5 },
                -- Bends: normal, gentle and long sweeping ones.
                { Id = "Tunnel_BendL", Weight = 10, Tag = "Bend" },
                { Id = "Tunnel_BendR", Weight = 10, Tag = "Bend" },
                { Id = "Tunnel_GentleL", Weight = 7, Tag = "Bend" },
                { Id = "Tunnel_GentleR", Weight = 7, Tag = "Bend" },
                { Id = "Tunnel_LongBendL", Weight = 6, Tag = "Bend" },
                { Id = "Tunnel_LongBendR", Weight = 6, Tag = "Bend" },
                -- Sharp bends and hairpins: brake, or lean hard.
                { Id = "Tunnel_SharpL", Weight = 6, Tag = "Sharp" },
                { Id = "Tunnel_SharpR", Weight = 6, Tag = "Sharp" },
                { Id = "Tunnel_HairpinL", Weight = 3, Tag = "Sharp" },
                { Id = "Tunnel_HairpinR", Weight = 3, Tag = "Sharp" },
                -- Broken track to jump (Rules/Jump), always straight after a straight run-up.
                {
                    Id = "Tunnel_Washout",
                    Weight = 5,
                    Tag = "Gap",
                    After = { "Tunnel_Straight", "Tunnel_Crystal", "Tunnel_Fungus", "Tunnel_Steep", "Tunnel_Grotto" },
                },
                {
                    Id = "Tunnel_WashoutWide",
                    Weight = 3,
                    Tag = "Gap",
                    After = { "Tunnel_Straight", "Tunnel_Crystal", "Tunnel_Fungus", "Tunnel_Steep", "Tunnel_Grotto" },
                },
                {
                    Id = "Tunnel_Chute",
                    Weight = 3,
                    Tag = "Gap",
                    After = { "Tunnel_Straight", "Tunnel_Crystal", "Tunnel_Fungus", "Tunnel_Steep", "Tunnel_Grotto" },
                },
                -- Caverns (the rifts are broken trestles to jump).
                { Id = "Cavern_Lake", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_Chasm", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_Garden", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_Crystal", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_Pit", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_Pool", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_Glow", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_Rift", Weight = 4, Tag = "Cavern" },
                { Id = "Cavern_RiftWide", Weight = 3, Tag = "Cavern" },
            },
            -- How far apart each kind turns up, in segments: never closer than Spacing[1], and forced once
            -- Spacing[2] have gone by. NoRepeat: never the same chunk twice running. NotAfter: never straight
            -- after one of these (no sharp bend right after landing a jump).
            Tags = {
                Sharp = { Spacing = { 3, 6 }, NotAfter = { "Gap" } },
                Gap = { Spacing = { 4, 9 } },
                Cavern = { Spacing = { 4, 8 }, NoRepeat = true },
            },
            EveryLeg = { "Cavern", "Sharp" }, -- every leg has at least one of each
            EdgeTunnels = 2, -- plain tunnel segments at each end of a leg, between caverns and stops
            -- The track never turns further than this from the zone's heading, so it can't loop over itself.
            MaxHeading = 1.4,
        },
        Mobs = { "Crawler", "Bat" },
        -- 30 segments in all: a stop after every 10.
        Legs = {
            { Ride = { Segments = 10, Ambushes = { 2, 3 } }, Stop = { Stage = "Obby" } },
            {
                Ride = { Segments = 10, Ambushes = { 3, 4 } },
                Stop = { Fork = { "SignalRoom", "SupplyDepot" }, Options = 2 },
            },
            { Ride = { Segments = 10, Ambushes = { 4, 5 } }, Stop = { Stage = "ForemanBoss" } },
        },
    },
    { Id = "CrystalHollows", Name = "Crystal Hollows", Built = false },
    { Id = "FungalDeep", Name = "Fungal Deep", Built = false },
    { Id = "DrownedWorks", Name = "The Drowned Works", Built = false },
    { Id = "BoneCatacombs", Name = "Bone Catacombs", Built = false },
    { Id = "Hell", Name = "Hell", Built = false },
}
