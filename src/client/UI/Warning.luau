--!strict
-- The warning plank, made to make you jump. It slams onto the screen (thrown in big and crooked, landing
-- with a jolt), a mine lamp hangs off each end, and a clang rings out like someone hammering a pit prop.
-- Two kinds:
--   danger (off the rails, tipping, too slow for a gap): the lamps flash turn about like a crossing signal,
--     the plank shakes and throbs, its glow and lettering pulse, and the edges of the screen glow red.
--   caution (bends, splits, gaps you're fast enough for): the lamps blink together, a slower glow, a slight
--     tremble.
-- `kind` says which warning this is: it slams in again only when that changes, not each time the numbers in
-- the text do. React draws it; one RenderStepped loop animates it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local Theme = require(ReplicatedStorage.Shared.Theme)
local Audio = require(script.Parent.Parent.Audio)
local Rustic = require(script.Parent.Rustic)

local e = React.createElement
local C = Theme.Color

local SLAM_SECONDS = 0.42
local SLAM_FROM = { danger = 2.2, caution = 1.6 } -- how big it's thrown in
local LAND_AT = 0.14 -- seconds into the slam that it hits the screen
local REST = -1.5 -- degrees: it never hangs quite straight
local SOUND_AGAIN = 3 -- seconds before the same warning rings again (tipping can flicker on and off)

local lastRung: { [string]: number } = {}

export type Props = {
    kind: string,
    text: string,
    color: Color3,
    danger: boolean,
}

-- Back-out easing, with a harder overshoot than TweenService's: 0 .. 1, passing 1 on the way.
local function backOut(x: number): number
    local c1 = 2.6
    local c3 = c1 + 1
    return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- 0 .. 1 and back, `hz` times a second, sharpened toward the peak by `sharp`.
local function beat(now: number, hz: number, sharp: number): number
    return (0.5 + 0.5 * math.sin(now * 2 * math.pi * hz)) ^ sharp
end

-- A mine lamp bolted over one end of the plank: an iron housing, a glass lens, and a glow behind it.
local function lamp(side: number, lensRef: any, glowRef: any)
    return e("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(if side < 0 then 0 else 1, 0.5),
        Size = UDim2.fromScale(1, 0.85),
        BackgroundColor3 = C.Iron,
        BorderSizePixel = 0,
        ZIndex = 5,
    }, {
        Square = e("UIAspectRatioConstraint", { AspectRatio = 1 }),
        Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        Edge = e("UIStroke", { Color = C.WoodDark, Thickness = 2.5 }),
        Glow = e("Frame", {
            ref = glowRef,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(1.6, 1.6),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 1, -- behind the plank and the lamp (the HUD layers by ZIndex screen-wide)
        }, { Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
        Lens = e("Frame", {
            ref = lensRef,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(0.7, 0.7),
            BorderSizePixel = 0,
            ZIndex = 6,
        }, {
            Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
            Bezel = e("UIStroke", { Color = C.BrassDark, Thickness = 2 }),
            Glass = e("UIGradient", {
                Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.55, 0.55, 0.55)),
                Rotation = 60,
            }),
        }),
        -- The hood over the top of the lamp.
        Hood = e("Frame", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.fromScale(0.5, 0.16),
            Size = UDim2.fromScale(0.9, 0.16),
            BackgroundColor3 = C.WoodDark,
            BorderSizePixel = 0,
            ZIndex = 7,
        }, { Round = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }),
    })
end

-- A red glow along one edge of the screen, fading in from the edge (`rotation` points it inward).
local function edge(anchor: Vector2, size: UDim2, rotation: number, ref: any)
    return e("Frame", {
        ref = ref,
        AnchorPoint = anchor,
        Position = UDim2.fromScale(anchor.X, anchor.Y),
        Size = size,
        BackgroundColor3 = C.Danger,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
    }, {
        Fade = e("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.45, 0.6),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Rotation = rotation,
        }),
    })
end

local function Warning(props: Props)
    local live = React.useRef(props)
    live.current = props
    local holderRef = React.useRef(nil :: Frame?)
    local scaleRef = React.useRef(nil :: UIScale?)
    local textRef = React.useRef(nil :: TextLabel?)
    local haloRef = React.useRef(nil :: UIStroke?)
    local lensL, lensR = React.useRef(nil :: Frame?), React.useRef(nil :: Frame?)
    local glowL, glowR = React.useRef(nil :: Frame?), React.useRef(nil :: Frame?)
    local edges = {
        React.useRef(nil :: Frame?),
        React.useRef(nil :: Frame?),
        React.useRef(nil :: Frame?),
        React.useRef(nil :: Frame?),
    }
    local slamAt = React.useRef(os.clock())

    -- Slam in (and ring) each time the warning changes.
    React.useEffect(function()
        local now = os.clock()
        slamAt.current = now
        local kind = props.kind
        if now - (lastRung[kind] or -math.huge) >= SOUND_AGAIN then
            lastRung[kind] = now
            Audio.ui(if props.danger then "Alarm" else "Heads")
        end
        return nil
    end, { props.kind })

    React.useEffect(function()
        local seed = math.random() * 100
        local dangerSince: number? = nil
        local connection = RunService.RenderStepped:Connect(function()
            local holder, scale, text = holderRef.current, scaleRef.current, textRef.current
            if not (holder and scale and text) then
                return
            end
            local now = os.clock()
            local current = live.current
            local danger = current.danger
            local color = current.color

            -- The slam: thrown in big and turned, landing with an overshoot and a jolt.
            local since = now - slamAt.current
            local slam = backOut(math.clamp(since / SLAM_SECONDS, 0, 1))
            local thrownTurn = if danger then -11 else 7
            local jolt = if since > LAND_AT then math.exp(-(since - LAND_AT) * 7) else 0

            -- The tremble: always a little, a lot when it's dangerous, worst just after landing.
            local tremble = (if danger then 3.5 else 1) + jolt * (if danger then 14 else 7)
            local dx = math.noise(now * 17, seed) * 2 * tremble
            local dy = math.noise(seed, now * 17) * 2 * tremble
            local twist = math.noise(now * 9, seed, 5) * (if danger then 1.6 else 0.4) + jolt * 3
            holder.Position = UDim2.new(0.5, dx, 0.34, dy)
            holder.Rotation = thrownTurn + (REST - thrownTurn) * slam + twist

            -- The throb: a danger warning swells with each flash.
            local flash = beat(now, 1.25, 2)
            local throb = if danger then 1 + 0.05 * flash else 1
            local from = if danger then SLAM_FROM.danger else SLAM_FROM.caution
            scale.Scale = (from + (1 - from) * slam) * throb

            -- The lettering flares toward white-hot on each flash of a danger warning.
            text.TextColor3 = if danger then color:Lerp(C.Paper, 0.55 * flash) else color

            -- The glow around the plank.
            local halo = haloRef.current
            if halo then
                halo.Color = color
                halo.Transparency = if danger then 0.15 + 0.6 * (1 - flash) else 0.55 + 0.25 * (1 - beat(now, 0.6, 1))
            end

            -- The lamps: turn about like a crossing signal (danger), or blinking together (caution).
            local left = if danger then flash else beat(now, 0.8, 3)
            local right = if danger then beat(now + 0.4, 1.25, 2) else left
            for index = 1, 2 do
                local lit = if index == 1 then left else right
                local lens = (if index == 1 then lensL else lensR).current
                if lens then
                    lens.BackgroundColor3 = color:Lerp(C.Ink, 0.75 * (1 - lit))
                end
                local glow = (if index == 1 then glowL else glowR).current
                if glow then
                    glow.BackgroundColor3 = color
                    glow.BackgroundTransparency = 1 - 0.45 * lit
                end
            end

            -- The red edges of the screen, for danger: fade in, then pulse with the lamps.
            if danger and not dangerSince then
                dangerSince = now
            elseif not danger then
                dangerSince = nil
            end
            local edgeIn = if dangerSince then math.clamp((now - dangerSince) / 0.3, 0, 1) else 0
            for _, ref in edges do
                local frame = ref.current
                if frame then
                    frame.BackgroundTransparency = if danger then 1 - edgeIn * (0.3 + 0.3 * flash) else 1
                end
            end
        end)
        return function()
            connection:Disconnect()
        end
    end, {})

    return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0 }, {
        EdgeTop = edge(Vector2.new(0.5, 0), UDim2.fromScale(1, 0.22), 90, edges[1]),
        EdgeBottom = edge(Vector2.new(0.5, 1), UDim2.fromScale(1, 0.22), -90, edges[2]),
        EdgeLeft = edge(Vector2.new(0, 0.5), UDim2.fromScale(0.16, 1), 0, edges[3]),
        EdgeRight = edge(Vector2.new(1, 0.5), UDim2.fromScale(0.16, 1), 180, edges[4]),
        Holder = e("Frame", {
            ref = holderRef,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.34),
            Size = UDim2.fromScale(0.52, 0.085),
            Rotation = REST,
            BackgroundTransparency = 1,
            ZIndex = 2,
        }, {
            Aspect = e("UIAspectRatioConstraint", { AspectRatio = 8 }),
            Slam = e("UIScale", { ref = scaleRef, Scale = SLAM_FROM.caution }),
            Halo = e("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, 14, 1, 14),
                BackgroundTransparency = 1,
                ZIndex = 1,
            }, {
                Round = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
                Stroke = e("UIStroke", { ref = haloRef, Color = props.color, Thickness = 6, Transparency = 0.5 }),
            }),
            Plank = Rustic.plank({
                size = UDim2.fromScale(1, 1),
                position = UDim2.fromScale(0.5, 0.5),
                seams = 1,
                worn = 7,
                zindex = 2,
            }, {
                Text = Rustic.text({
                    text = props.text,
                    font = Theme.Font.Sign,
                    color = props.color,
                    size = UDim2.fromScale(0.8, 0.66),
                    maxSize = 40,
                    stroke = 2.5,
                    zindex = 4,
                    ref = textRef,
                }),
            }),
            LampL = lamp(-1, lensL, glowL),
            LampR = lamp(1, lensR, glowR),
        }),
    })
end

return Warning
