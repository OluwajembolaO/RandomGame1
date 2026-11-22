--!strict
-- The run HUD, in the mine's rustic style (UI/Rustic, Shared/Theme): a hanging plank sign with the zone or
-- stop and a brass tag with the segment number, a parchment note for messages, a painted warning plank
-- (off the rails, tipping, a gap and the speed it needs, a sharp bend and which way to lean), the cart's
-- HP in an iron trough, a note on how you're driving, the rivet gun's ammo on a brass plate, and the depth
-- meter down the right (UI/DepthMeter).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Packages.React)

local Configs = require(ReplicatedStorage.Shared.Configs)
local RunInfo = require(ReplicatedStorage.Shared.RunInfo)
local Theme = require(ReplicatedStorage.Shared.Theme)
local DepthMeter = require(script.Parent.DepthMeter)
local Rustic = require(script.Parent.Rustic)
local useAttribute = require(script.Parent.useAttribute)

local e = React.createElement
local C = Theme.Color
local info = RunInfo.instance()
local me = Players.LocalPlayer

local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

-- Pops a UIScale up and back each time `key` changes (a new warning slams onto the screen).
local function usePop(key: string?)
    local scale = React.useRef(nil :: UIScale?)
    React.useEffect(function()
        local node = scale.current
        if node and key then
            node.Scale = 1.25
            TweenService:Create(node, POP, { Scale = 1 }):Play()
        end
    end, { key })
    return scale
end

-- The hanging sign: two chains down from the top of the screen, a plank with the title, and a brass tag.
local function Sign(props: { title: string, tag: string? })
    local chain = function(x: number)
        return e("Frame", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(x, 0),
            Size = UDim2.fromOffset(3, 40),
            BackgroundColor3 = C.IronLight,
            BorderSizePixel = 0,
        })
    end
    return Rustic.plank({
        size = UDim2.fromScale(0.32, 0.075),
        position = UDim2.new(0.5, 0, 0, 30),
        anchor = Vector2.new(0.5, 0),
        aspect = 5.6,
        seams = 1,
    }, {
        ChainL = chain(0.12),
        ChainR = chain(0.88),
        Title = Rustic.text({
            text = props.title,
            font = Theme.Font.Sign,
            color = C.Paper,
            size = UDim2.fromScale(0.86, 0.66),
            maxSize = 34,
            stroke = 2,
        }),
        Tag = if props.tag
            then Rustic.brass({
                size = UDim2.fromScale(0.7, 0.46),
                position = UDim2.new(0.5, 0, 1, 4),
                anchor = Vector2.new(0.5, 0),
                rotation = -1.5,
            }, {
                Text = Rustic.text({
                    text = props.tag,
                    font = Theme.Font.Stamp,
                    color = C.Ink,
                    maxSize = 18,
                }),
            })
            else nil,
    })
end

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
    local warning: string? = nil
    local warningColor = C.Danger
    local hint: string? = nil
    if riding and derailed then
        warning = "OFF THE RAILS!"
        hint = "HOLD [E] ON THE CART TO PUSH IT BACK ON — MORE HANDS, FASTER"
    elseif riding and tilt > 0.15 then
        warning = "TIPPING!  " .. leanText(leanSide)
    elseif riding and splitIn >= 0 and splitIn <= SPLIT_WARN then
        warning = "THREE-WAY SPLIT — TAKING " .. LANES[splitPick]
        warningColor = C.Lamp
        hint = "[Q] LEAN LEFT  ·  HOLD STEADY  ·  [E] LEAN RIGHT — TAKE THE GREEN LINE"
    elseif riding and gapIn >= 0 and gapIn <= Configs.Run.Cart.Jump.WarnDistance then
        local fastEnough = speed >= gapNeed
        warning = "GAP AHEAD — NEED " .. gapNeed .. "  ·  YOU " .. speed
        warningColor = if fastEnough then C.Safe else C.Danger
        hint = if fastEnough then "KEEP IT UP" else "HOLD [W] TO PUSH — DON'T BRAKE"
    elseif riding and sharpIn >= 0 and sharpIn <= Configs.Run.Cart.SharpWarnDistance then
        warning = "SHARP BEND — SLOW DOWN OR " .. leanText(sharpSide)
    end
    local popRef = usePop(if warning then string.match(warning, "^[^%d]+") else nil)

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
        Sign = e(Sign, { title = title, tag = tag }),
        Note = if note ~= ""
            then Rustic.paper({
                size = UDim2.fromScale(0.3, 0.05),
                position = UDim2.fromScale(0.5, 0.215),
                rotation = 1,
                aspect = 9,
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
            then Rustic.plank({
                size = UDim2.fromScale(0.52, 0.085),
                position = UDim2.fromScale(0.5, 0.34),
                rotation = -1.5,
                aspect = 8,
                seams = 1,
            }, {
                Pop = e("UIScale", { ref = popRef }),
                Text = Rustic.text({
                    text = warning,
                    font = Theme.Font.Sign,
                    color = warningColor,
                    size = UDim2.fromScale(0.92, 0.66),
                    maxSize = 40,
                    stroke = 2.5,
                }),
            })
            else nil,
        Hint = if hint
            then Rustic.paper({
                size = UDim2.fromScale(0.44, 0.042),
                position = UDim2.fromScale(0.5, 0.405),
                rotation = 0.8,
                aspect = 14,
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
                position = UDim2.fromScale(0.5, 0.46),
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
