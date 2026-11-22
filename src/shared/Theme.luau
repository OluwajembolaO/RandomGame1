--!strict
-- The game's rustic look, shared by the HUD (client/UI) and the signs and number plates in the cave
-- (server/Placeholders): weathered planks, iron bands, brass fittings, and painted or stamped lettering.

local Theme = {}

Theme.Color = {
    WoodDark = Color3.fromRGB(38, 25, 16),
    Wood = Color3.fromRGB(86, 56, 32),
    WoodLight = Color3.fromRGB(124, 84, 48),
    Iron = Color3.fromRGB(46, 44, 42),
    IronLight = Color3.fromRGB(92, 88, 82),
    Brass = Color3.fromRGB(205, 164, 92),
    BrassDark = Color3.fromRGB(128, 94, 46),
    Paper = Color3.fromRGB(236, 218, 176),
    PaperDark = Color3.fromRGB(196, 170, 120),
    Ink = Color3.fromRGB(28, 18, 10),
    Rust = Color3.fromRGB(150, 64, 32),
    Danger = Color3.fromRGB(214, 64, 44),
    Safe = Color3.fromRGB(150, 196, 96),
    Lamp = Color3.fromRGB(255, 200, 122),
}

-- Painted sign lettering, stamped labels, and numbers.
Theme.Font = {
    Sign = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Heavy),
    Stamp = Font.new("rbxasset://fonts/families/SpecialElite.json"),
    Number = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Heavy),
}

-- A plank's grain: lighter in the middle, darker toward the edges.
function Theme.grain(light: Color3, dark: Color3): ColorSequence
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, dark),
        ColorSequenceKeypoint.new(0.18, light),
        ColorSequenceKeypoint.new(0.55, light:Lerp(dark, 0.25)),
        ColorSequenceKeypoint.new(0.82, light),
        ColorSequenceKeypoint.new(1, dark),
    })
end

return Theme
