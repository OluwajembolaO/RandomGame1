--!strict
-- The run HUD: where you are, the cart's HP, the brake, sharp-curve warnings and ammo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Configs = require(ReplicatedStorage.Shared.Configs)
local RunInfo = require(ReplicatedStorage.Shared.RunInfo)
local useAttribute = require(script.Parent.useAttribute)

local e = React.createElement
local info = RunInfo.instance()
local me = Players.LocalPlayer

local AMBER = Color3.fromRGB(255, 196, 120)
local RED = Color3.fromRGB(235, 70, 55)
local INK = Color3.fromRGB(16, 13, 11)

local PHASE_TITLES = {
    Station = "THE STATION",
    Victory = "YOU MADE IT",
    Wipe = "WIPED OUT",
    Voting = "VOTE",
}

local function label(props: {
    text: string,
    size: number,
    position: UDim2,
    anchor: Vector2?,
    color: Color3?,
    width: number?,
})
    return e("TextLabel", {
        AnchorPoint = props.anchor or Vector2.new(0.5, 0),
        Position = props.position,
        Size = UDim2.fromOffset(props.width or 700, props.size + 8),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBlack,
        Text = props.text,
        TextSize = props.size,
        TextColor3 = props.color or AMBER,
    }, {
        Stroke = e("UIStroke", { Thickness = 2, Color = INK, Transparency = 0.2 }),
    })
end

local function bar(fraction: number, color: Color3, position: UDim2, caption: string)
    return e("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = position,
        Size = UDim2.fromOffset(340, 22),
        BackgroundColor3 = INK,
        BackgroundTransparency = 0.25,
    }, {
        Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
        Fill = e("Frame", {
            Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
            BackgroundColor3 = color,
        }, { Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }) }),
        Caption = e("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Color3.new(1, 1, 1),
            Text = caption,
        }, { Stroke = e("UIStroke", { Thickness = 1.5, Color = INK }) }),
    })
end

local function Hud()
    local phase = useAttribute(info, "Phase", "Station")
    local zone = useAttribute(info, "Zone", "")
    local leg = useAttribute(info, "Leg", 0)
    local legs = useAttribute(info, "Legs", 0)
    local stop = useAttribute(info, "Stop", "")
    local genre = useAttribute(info, "StopGenre", "")
    local message = useAttribute(info, "Message", "")
    local countdown = useAttribute(info, "Countdown", 0)
    local hp = useAttribute(info, "CartHp", 0)
    local maxHp = useAttribute(info, "CartMaxHp", 1)
    local braking = useAttribute(info, "Braking", false)
    local brakeReady = useAttribute(info, "BrakeReady", true)
    local sharpIn = useAttribute(info, "SharpIn", -1)
    local ammo = useAttribute(me, "Ammo", 0)
    local reloading = useAttribute(me, "Reloading", false)

    local riding = phase == "Riding"
    local title = PHASE_TITLES[phase] or ""
    if riding then
        title = string.upper(zone) .. "   ·   LEG " .. leg .. " / " .. legs
    elseif phase == "AtStop" and stop ~= "" then
        title = string.upper(stop)
    end
    local subtitle = message
    if countdown > 0 then
        subtitle = (if message ~= "" then message .. "  " else "") .. countdown
    end
    local warning = riding and sharpIn >= 0 and sharpIn <= Configs.Run.Cart.SharpWarnDistance

    local brakeText = if braking then "BRAKING" elseif brakeReady then "[F] BRAKE" else "BRAKE COOLING"
    return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
        Title = label({ text = title, size = 30, position = UDim2.new(0.5, 0, 0, 12) }),
        Genre = if phase == "AtStop" and genre ~= ""
            then label({ text = string.upper(genre), size = 16, position = UDim2.new(0.5, 0, 0, 50) })
            else nil,
        Subtitle = if subtitle ~= ""
            then label({
                text = subtitle,
                size = 20,
                position = UDim2.new(0.5, 0, 0, 74),
                color = Color3.new(1, 1, 1),
            })
            else nil,
        Warning = if warning
            then label({
                text = "SHARP CURVE AHEAD — BRAKE!",
                size = 34,
                position = UDim2.fromScale(0.5, 0.3),
                color = RED,
            })
            else nil,
        CartHp = if phase ~= "Station"
            then bar(hp / math.max(1, maxHp), RED, UDim2.new(0.5, 0, 1, -40), "CART  " .. hp .. " / " .. maxHp)
            else nil,
        Brake = if riding
            then label({
                text = brakeText,
                size = 18,
                position = UDim2.new(0.5, 0, 1, -92),
                color = if braking then RED else AMBER,
            })
            else nil,
        Ammo = label({
            text = if reloading then "RELOADING" else "RIVETS  " .. ammo,
            size = 20,
            position = UDim2.new(1, -24, 1, -40),
            anchor = Vector2.new(1, 1),
            width = 260,
        }),
    })
end

return Hud
