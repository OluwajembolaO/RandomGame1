--!strict
-- The run HUD, in the mine's rustic style (UI/Rustic, Shared/Theme): an old sign swinging on its chains
-- with the zone or stop and a brass tag with the segment number (UI/HangingSign), a parchment note for
-- messages, a warning plank that slams in with its lamps flashing (UI/Warning: off the rails, tipping, a
-- split, a gap and the speed it needs, a sharp bend and which way to lean), the cart's HP in an iron trough,
-- a note on how you're driving, the rivet gun's ammo on a brass plate, and the depth meter down the right
-- (UI/DepthMeter).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Configs = require(ReplicatedStorage.Shared.Configs)
local RunInfo = require(ReplicatedStorage.Shared.RunInfo)
local Theme = require(ReplicatedStorage.Shared.Theme)
local DepthMeter = require(script.Parent.DepthMeter)
local HangingSign = require(script.Parent.HangingSign)
local Rustic = require(script.Parent.Rustic)
local Warning = require(script.Parent.Warning)
local useAttribute = require(script.Parent.useAttribute)

local e = React.createElement
local C = Theme.Color
local info = RunInfo.instance()
local me = Players.LocalPlayer

-- Which way to lean into a bend: 1 for a right-hand bend, -1 for a left.
local function leanText(side: number): string
    return if side > 0 then "LEAN RIGHT ▶ [E]" elseif side < 0 then "[Q] ◀ LEAN LEFT" else "LEAN INTO IT"
end

-- The lane the crew's lean takes at a three-way split (Rules/Split).
local LANES = { [-1] = "◀ LEFT", [0] = "▲ MIDDLE", [1] = "RIGHT ▶" }
local SPLIT_WARN = 220 -- studs before a split's switch that the HUD calls it

local PHASE_TITLES = {
    Station = "THE STATION",
    Victory = "YOU MADE IT",
    Wipe = "WIPED OUT",
    Voting = "VOTE",
}

local function Hud()
    local phase = useAttribute(info, "Phase", "Station")
    local zone = useAttribute(info, "Zone", "")
    local stop = useAttribute(info, "Stop", "")
    local genre = useAttribute(info, "StopGenre", "")
    local segment = useAttribute(info, "Segment", 0)
    local segments = useAttribute(info, "Segments", 0)
    local message = useAttribute(info, "Message", "")
    local countdown = useAttribute(info, "Countdown", 0)
    local hp = useAttribute(info, "CartHp", 0)
    local maxHp = useAttribute(info, "CartMaxHp", 1)
    local braking = useAttribute(info, "Braking", false)
    local pushing = useAttribute(info, "Pushing", false)
    local lean = useAttribute(info, "Lean", 0)
    local tilt = useAttribute(info, "Tilt", 0)
    local leanSide = useAttribute(info, "LeanSide", 0)
    local derailed = useAttribute(info, "Derailed", false)
    local pushBack = useAttribute(info, "PushBack", 0)
    local pushers = useAttribute(info, "Pushers", 0)
    local sharpIn = useAttribute(info, "SharpIn", -1)
    local sharpSide = useAttribute(info, "SharpSide", 0)
    local gapIn = useAttribute(info, "GapIn", -1)
    local gapNeed = useAttribute(info, "GapNeed", 0)
    local splitIn = useAttribute(info, "SplitIn", -1)
    local splitPick = useAttribute(info, "SplitPick", 0)
    local difficulty = useAttribute(info, "Difficulty", "")
    local speed = useAttribute(info, "Speed", 0)
    local ammo = useAttribute(me, "Ammo", 0)
    local reloading = useAttribute(me, "Reloading", false)

    local riding = phase == "Riding"
    local title = PHASE_TITLES[phase] or string.upper(zone)
    if phase == "AtStop" and stop ~= "" then
        title = string.upper(stop)
    end
    local tag: string? = nil
    if phase == "AtStop" and genre ~= "" then
        tag = string.upper(genre)
    elseif segments > 0 and phase ~= "Station" then
        tag = string.format("SEGMENT %02d / %02d", segment, segments)
            .. (if difficulty ~= "" then "  ·  " .. string.upper(difficulty) else "")
    end
    local note = message
    if countdown > 0 then
        note = (if message ~= "" then message .. "   " else "") .. countdown
    end

    -- The one warning that matters most right now: off the rails, tipping, a split, a gap, then a sharp bend.
    -- Danger is for the ones that need doing something about this second.
    local warning: string? = nil
    local warningKind = ""
    local warningColor = C.Danger
    local danger = false
    local hint: string? = nil
    if riding and derailed then
        warning, warningKind, danger = "OFF THE RAILS!", "Derailed", true
        hint = "HOLD [E] ON THE CART TO PUSH IT BACK ON — MORE HANDS, FASTER"
    elseif riding and tilt > 0.15 then
        warning, warningKind, danger = "TIPPING!  " .. leanText(leanSide), "Tipping", true
    elseif riding and splitIn >= 0 and splitIn <= SPLIT_WARN then
        warning, warningKind = "THREE-WAY SPLIT — TAKING " .. LANES[splitPick], "Split"
        warningColor = C.Lamp
        hint = "[Q] LEFT  ·  HOLD STEADY  ·  [E] RIGHT — TAKE THE GREEN LINE"
    elseif riding and gapIn >= 0 and gapIn <= Configs.Run.Cart.Jump.WarnDistance then
        local fastEnough = speed >= gapNeed
        warning, warningKind = "GAP AHEAD — NEED " .. gapNeed .. "  ·  YOU " .. speed, "Gap"
        warningColor = if fastEnough then C.Safe else C.Danger
        danger = not fastEnough
        hint = if fastEnough then "KEEP IT UP" else "HOLD [W] TO PUSH — DON'T BRAKE"
    elseif riding and sharpIn >= 0 and sharpIn <= Configs.Run.Cart.SharpWarnDistance then
        warning, warningKind = "SHARP BEND — SLOW DOWN OR " .. leanText(sharpSide), "Sharp"
    end

    local driveText = if braking
        then "BRAKING"
        elseif pushing then "PUSHING"
        else "[W] PUSH   ·   [S] BRAKE   ·   [Q] / [E] LEAN"
    if lean <= -0.3 then
        driveText ..= "   ·   ◀ LEANING"
    elseif lean >= 0.3 then
        driveText ..= "   ·   LEANING ▶"
    end

    return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
        Sign = e(HangingSign, { title = title, tag = tag }),
        Note = if note ~= ""
            then Rustic.paper({
                size = UDim2.fromScale(0.3, 0.05),
                position = UDim2.fromScale(0.5, 0.215),
                rotation = 1,
                aspect = 9,
                stained = 2,
            }, {
                Text = Rustic.text({
                    text = note,
                    font = Theme.Font.Stamp,
                    color = C.Ink,
                    size = UDim2.fromScale(0.92, 0.7),
                    maxSize = 24,
                }),
            })
            else nil,
        Warning = if warning
            then e(Warning, { kind = warningKind, text = warning, color = warningColor, danger = danger })
            else nil,
        Hint = if hint
            then Rustic.paper({
                size = UDim2.fromScale(0.44, 0.042),
                position = UDim2.fromScale(0.5, 0.435),
                rotation = 0.8,
                aspect = 14,
                stained = 9,
            }, {
                Text = Rustic.text({
                    text = hint,
                    font = Theme.Font.Stamp,
                    color = C.Ink,
                    size = UDim2.fromScale(0.94, 0.7),
                    maxSize = 20,
                }),
            })
            else nil,
        PushBack = if riding and derailed
            then Rustic.bar({
                size = UDim2.fromScale(0.28, 0.038),
                position = UDim2.fromScale(0.5, 0.49),
                aspect = 10,
                fraction = pushBack,
                color = C.Brass,
                caption = if pushers > 0 then "PUSHING  ·  " .. pushers .. " ON IT" else "NOBODY'S PUSHING",
            })
            else nil,
        Drive = if riding and not derailed
            then Rustic.paper({
                size = UDim2.fromScale(0.42, 0.036),
                position = UDim2.new(0.5, 0, 1, -66),
                anchor = Vector2.new(0.5, 1),
                aspect = 16,
                stained = 4,
            }, {
                Text = Rustic.text({
                    text = driveText,
                    font = Theme.Font.Stamp,
                    color = if braking then C.Danger else C.Ink,
                    size = UDim2.fromScale(0.94, 0.72),
                    maxSize = 18,
                }),
            })
            else nil,
        CartHp = if phase ~= "Station"
            then Rustic.bar({
                size = UDim2.fromScale(0.3, 0.045),
                position = UDim2.new(0.5, 0, 1, -16),
                anchor = Vector2.new(0.5, 1),
                aspect = 10,
                fraction = hp / math.max(1, maxHp),
                color = C.Rust,
                caption = "CART   " .. hp .. " / " .. maxHp,
            })
            else nil,
        Ammo = Rustic.brass({
            size = UDim2.fromScale(0.13, 0.05),
            position = UDim2.new(1, -18, 1, -16),
            anchor = Vector2.new(1, 1),
            aspect = 3.6,
            rotation = 1,
        }, {
            Text = Rustic.text({
                text = if reloading then "RELOADING" else "RIVETS  " .. ammo,
                font = Theme.Font.Sign,
                color = C.Ink,
                size = UDim2.fromScale(0.86, 0.6),
                maxSize = 22,
            }),
        }),
        Depth = e(DepthMeter),
    })
end

return Hud
