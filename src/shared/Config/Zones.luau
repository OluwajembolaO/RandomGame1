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
        -- Which Blender kit pieces (Config/KitData) this zone's cave is snapped together from (Rules/Kit).
        Kit = {
            Station = "Station",
            Stop = "StopChamber",
            Cap = "EndCap",
            Straight = "Tunnel_Straight",
            Bends = { "Tunnel_BendL", "Tunnel_BendR" },
            Sharps = { "Tunnel_SharpL", "Tunnel_SharpR" },
            Caverns = { "Cavern_Lake", "Cavern_Chasm", "Cavern_Garden", "Cavern_Rift" },
            CavernGap = { 192, 384 }, -- studs of tunnel between caverns
            -- Washed-out tunnels with a gap to jump (Rules/Jump), every few tunnel pieces.
            Washouts = { "Tunnel_Washout" },
            WashoutEvery = { 6, 10 },
            EdgeTunnels = 2, -- tunnel pieces kept at each end of a leg, between caverns and stops
            SharpEvery = { 4, 7 }, -- tunnel pieces between sharp bends
            StraightChance = 0.45,
            -- The track never turns further than this from the zone's heading, so it can't loop over itself.
            MaxHeading = 1.4,
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
    },
    { Id = "CrystalHollows", Name = "Crystal Hollows", Built = false },
    { Id = "FungalDeep", Name = "Fungal Deep", Built = false },
    { Id = "DrownedWorks", Name = "The Drowned Works", Built = false },
    { Id = "BoneCatacombs", Name = "Bone Catacombs", Built = false },
    { Id = "Hell", Name = "Hell", Built = false },
}
