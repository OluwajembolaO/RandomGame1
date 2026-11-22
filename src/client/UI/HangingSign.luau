--!strict
-- The old sign hanging at the top of the screen: a worn plank on two lines running up off the top edge, the
-- left line longer than the right so it hangs crooked, and a brass tag hung from a nail under it. It swings
-- on its lines like it's really hanging: it drifts in the draught down the shaft, sways toward the ground as
-- the cart banks (it hangs from the cart, so it hangs toward wherever down is on your screen), rattles as the
-- cart picks up speed and shudders as it starts to tip, and is knocked swinging when the cart jolts (the
-- "Shake" effect). When the crew leans it lurches the way they threw their weight, swings past and rocks
-- back. Off a jump it goes weightless and floats up on slack lines, tumbling, then drops when the cart
-- lands, snaps the lines taut and bounces on them. The tag swings on its nail a beat behind the plank.
-- All of that only while you're riding the cart: off it (at the station, at a stop, pushing a tipped cart
-- back on) the sign settles and hangs still, crooked on its uneven lines.
--
-- React draws it; one RenderStepped loop moves it. The lines, plank and tag are posed by hand each frame,
-- so the lines always meet the plank's corners however it swings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local Configs = require(ReplicatedStorage.Shared.Configs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RunInfo = require(ReplicatedStorage.Shared.RunInfo)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Rustic = require(script.Parent.Rustic)

local e = React.createElement
local C = Theme.Color
local info = RunInfo.instance()
local me = Players.LocalPlayer

local ASPECT = 5.6 -- the plank, width / height
local HANG = 0.85 -- how far below the hooks the plank hangs on average, in plank heights
local UNEVEN = 0.13 -- half the difference between the lines, in plank heights (the left is the longer)
local HOOK_X = 0.38 -- each line this far either side of the middle, in plank widths
local TOP = -12 -- pixels from the top of the screen to where the lines hang from (just off screen)

-- The rig: an invisible box centred on the hook line, with room for the plank and tag below it.
local RIG = 2 + 2 * HANG -- rig height, in plank heights
local RIG_ASPECT = ASPECT / RIG

local SWING = { hz = 0.55, damping = 0.1 } -- the plank swinging on its lines (radians of line)
local ROCK = { hz = 1.3, damping = 0.16 } -- the plank rocking about its middle (radians)
local TAG = { hz = 0.9, damping = 0.1 } -- the tag on its nail (radians)
-- Off the cart nothing moves it, and it comes to rest within a second or so.
local STILL = {
    swing = { hz = SWING.hz, damping = 0.6 },
    rock = { hz = ROCK.hz, damping = 0.7 },
    tag = { hz = TAG.hz, damping = 0.6 },
}
local TAG_SWING = math.rad(10) -- the furthest the tag turns from the plank before it knocks against it
local DRAUGHT = math.rad(10) -- the idle drift on the lines
local IDLE_ROCK = math.rad(1.8) -- and the plank's idle rock
local LEAN_FOLLOW = 0.55 -- how much of the screen's roll the lines hang toward
local MAX_HANG = math.rad(16)
local RATTLE = 2.2 -- rock kicks a second at top speed
local TOP_SPEED = Configs.Run.Cart.Speed * 1.3

-- Leaning: where the sign hangs with the whole crew leaning one way, and the lurch when they throw their
-- weight over (per unit of lean, which runs -1 .. 1).
local LEAN_SWAY = math.rad(12)
local LEAN_LURCH = 0.75 -- radians a second of swing
local LEAN_TWIST = 0.55 -- radians a second of rock, the side they lean to dipping
-- Tipping: the sign swings out of the bend as the cart lifts, and shudders.
local TIP_SWAY = math.rad(10)
local TIP_SHUDDER = 4

-- In the air. Lift is how far the plank has risen on slack lines, in plank heights (0 hanging taut).
local GRAVITY = 40 -- plank heights / s^2 pulling it back down on the ground
local FLOAT = 7 -- plank heights / s^2 drifting it up while weightless in the air
local FLOAT_MAX = 0.3 -- the highest it floats
local TOSS = 1.6 -- plank heights / s it's tossed up as the cart leaves the lip
local SLAM = 3 -- plank heights / s it's thrown down as the cart lands
local SNAP = 0.4 -- how much of its fall it bounces back up when the lines snap taut
local SNAP_MIN = 1.5 -- plank heights / s: anything slower than this and the lines just catch it
local TUMBLE = { swing = math.rad(14), rock = math.rad(6) } -- how far it turns about while weightless

-- `value` while you're riding the cart, nothing when you're not.
local function onCart(riding: boolean, value: number): number
    return if riding then value else 0
end

-- Moves a damped spring toward `target`: returns the new angle and speed.
local function spring(
    shape: { hz: number, damping: number },
    angle: number,
    speed: number,
    target: number,
    dt: number
): (number, number)
    local omega = 2 * math.pi * shape.hz
    local slices = math.max(1, math.ceil(dt * 240))
    local h = dt / slices
    for _ = 1, slices do
        speed += (omega * omega * (target - angle) - 2 * shape.damping * omega * speed) * h
        angle += speed * h
    end
    return angle, speed
end

-- Which way down is on screen, as an angle from straight down (positive toward the right).
local function screenDown(): number
    local camera = workspace.CurrentCamera
    if not camera then
        return 0
    end
    local frame = camera.CFrame
    return math.atan2(-frame.RightVector.Y, frame.UpVector.Y)
end

-- Poses a line from `top` to `bottom` (pixels from the rig's middle): the frame is centred between them
-- and turned to point from one to the other.
local function pose(line: GuiObject, top: Vector2, bottom: Vector2)
    local span = bottom - top
    local middle = (top + bottom) / 2
    line.Position = UDim2.new(0.5, middle.X, 0.5, middle.Y)
    line.Size = UDim2.fromOffset(line.Size.X.Offset, span.Magnitude)
    line.Rotation = -math.deg(math.atan2(span.X, span.Y))
end

-- A line the sign hangs from, `length` (rig heights) long at first; the loop poses it from then on.
local function line(x: number, length: number, ref: any)
    return e("Frame", {
        ref = ref,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(x, 0.5 + length / 2),
        Size = UDim2.fromOffset(3, 40),
        BackgroundColor3 = C.IronLight,
        BorderSizePixel = 0,
        ZIndex = 1,
    })
end

local function HangingSign(props: { title: string, tag: string? })
    local rigRef = React.useRef(nil :: Frame?)
    local plankRef = React.useRef(nil :: Frame?)
    local tagRef = React.useRef(nil :: Frame?)
    local leftRef = React.useRef(nil :: Frame?)
    local rightRef = React.useRef(nil :: Frame?)

    React.useEffect(function()
        local swing, swingSpeed = 0, 0
        local rock, rockSpeed = 0, 0
        local tagAngle, tagSpeed = 0, 0
        local lift, liftSpeed = 0, 0
        local lastLean = 0
        local wasAirborne = false
        local seed = math.random() * 100
        local function side(): number
            return if math.random() < 0.5 then -1 else 1
        end
        local kicked = Remotes.Effect.OnClientEvent:Connect(function(kind: string, amount: any)
            if kind == "Shake" and me:GetAttribute("Riding") == true then
                local size = math.clamp(tonumber(amount) or 0.3, 0, 1.5)
                local way = side()
                swingSpeed += way * size * 1.1
                rockSpeed -= way * size * 0.7
                tagSpeed += way * size * 1.6
            end
        end)
        local moving = RunService.RenderStepped:Connect(function(dt: number)
            local rig, plank, tag = rigRef.current, plankRef.current, tagRef.current
            local left, right = leftRef.current, rightRef.current
            if not (rig and plank and left and right) then
                return
            end
            dt = math.min(dt, 0.1)
            local now = os.clock()
            -- Only the cart moves it: off the cart all of this is still, and it settles.
            local riding = me:GetAttribute("Riding") == true
            local lean = onCart(riding, tonumber(info:GetAttribute("Lean")) or 0)
            local tilt = onCart(riding, tonumber(info:GetAttribute("Tilt")) or 0)
            local leanSide = onCart(riding, tonumber(info:GetAttribute("LeanSide")) or 0)
            local airborne = riding and info:GetAttribute("Airborne") == true
            local still = not riding

            -- The crew throwing their weight over: the sign lurches that way and the side they lean to dips.
            local thrown = lean - lastLean
            lastLean = lean
            if thrown ~= 0 and riding then
                swingSpeed += thrown * LEAN_LURCH
                rockSpeed += thrown * LEAN_TWIST
                tagSpeed += thrown * LEAN_LURCH * 1.5
            end

            -- Leaving the lip it's tossed up; landing, it's thrown down onto its lines.
            if airborne and not wasAirborne then
                liftSpeed -= TOSS
            elseif wasAirborne and not airborne then
                liftSpeed += SLAM
            end
            wasAirborne = airborne

            -- Where the lines are swinging toward: down on screen, the way the crew leans, out of a bend the
            -- cart's tipping in, plus the draught; and in the air, wherever it tumbles.
            local draught = DRAUGHT * (0.6 * math.sin(now * 2 * math.pi / 4.3 + seed) + math.noise(now * 0.4, seed))
            local target = onCart(riding, screenDown() * LEAN_FOLLOW + draught)
                + lean * LEAN_SWAY
                - leanSide * tilt * TIP_SWAY
            if airborne then
                target += TUMBLE.swing * 2 * math.noise(now * 1.3, seed, 7)
            end
            local swingShape = if still then STILL.swing else SWING
            swing, swingSpeed = spring(swingShape, swing, swingSpeed, math.clamp(target, -MAX_HANG, MAX_HANG), dt)

            -- The faster the cart, the more the plank rattles on its lines, and it shudders as the cart tips.
            local speed = onCart(riding, math.abs(tonumber(info:GetAttribute("Speed")) or 0))
            local rattle = if airborne then 0 else math.clamp(speed / TOP_SPEED, 0, 1)
            rockSpeed += math.noise(now * 7, seed, 3) * (RATTLE * rattle + TIP_SHUDDER * tilt) * dt * 8
            local idle = onCart(riding, IDLE_ROCK * math.sin(now * 2 * math.pi / 3.1 + seed))
            if airborne then
                idle += TUMBLE.rock * 2 * math.noise(now * 1.1, seed, 11)
            end
            rock, rockSpeed = spring(if still then STILL.rock else ROCK, rock, rockSpeed, idle, dt)

            -- Weightless in the air it floats up on slack lines; back down, it falls until the lines snap
            -- taut, and bounces on them.
            if airborne then
                liftSpeed = (liftSpeed - FLOAT * dt) * math.exp(-1.5 * dt)
                lift += liftSpeed * dt
                if lift < -FLOAT_MAX then
                    lift, liftSpeed = -FLOAT_MAX, math.max(0, liftSpeed)
                end
            else
                -- Gravity only pulls while the lines are slack; hanging taut, they hold it still.
                if lift < 0 then
                    liftSpeed += GRAVITY * dt
                end
                lift += liftSpeed * dt
                if lift >= 0 then
                    local impact = liftSpeed
                    lift, liftSpeed = 0, 0
                    if impact > SNAP_MIN then
                        liftSpeed = -impact * SNAP
                        swingSpeed += side() * impact * 0.12
                        rockSpeed += side() * impact * 0.12
                        tagSpeed += side() * impact * 0.4
                    end
                end
            end

            -- Pose it: each line's end swung out by `swing` from the top, the plank turned to meet both.
            local size = rig.AbsoluteSize
            local height = size.Y / RIG
            local hookGap = HOOK_X * size.X
            local slack = lift * height
            local longer, shorter = (HANG + UNEVEN) * height + slack, (HANG - UNEVEN) * height + slack
            local hookL, hookR = Vector2.new(-hookGap, 0), Vector2.new(hookGap, 0)
            local down = Vector2.new(math.sin(swing), math.cos(swing))
            local endL, endR = hookL + down * longer, hookR + down * shorter
            local across = endR - endL
            local turn = math.atan2(across.Y, across.X) + rock
            local along = Vector2.new(math.cos(turn), math.sin(turn))
            local normal = Vector2.new(-along.Y, along.X) -- pointing down out of the plank's top edge
            local topMiddle = (endL + endR) / 2
            local middle = topMiddle + normal * (height / 2)
            plank.Position = UDim2.new(0.5, middle.X, 0.5, middle.Y)
            plank.Rotation = math.deg(turn)
            pose(left, hookL, topMiddle - along * hookGap)
            pose(right, hookR, topMiddle + along * hookGap)

            -- The tag hangs from a nail under the plank's middle and swings a beat behind it.
            if tag then
                tagAngle, tagSpeed = spring(if still then STILL.tag else TAG, tagAngle, tagSpeed, swing, dt)
                -- It knocks against the plank's underside if it swings too far, and bounces back off it.
                local fromPlank = tagAngle + turn
                if math.abs(fromPlank) > TAG_SWING then
                    tagAngle = math.sign(fromPlank) * TAG_SWING - turn
                    tagSpeed = -tagSpeed * 0.3
                end
                local nail = topMiddle + normal * (height + 3)
                local tagSize = tag.AbsoluteSize
                local hangs = Vector2.new(math.sin(tagAngle), math.cos(tagAngle))
                local centre = nail + hangs * (tagSize.Y / 2 + 2)
                tag.Position = UDim2.new(0.5, centre.X, 0.5, centre.Y)
                tag.Rotation = -math.deg(math.atan2(hangs.X, hangs.Y))
            end
        end)
        return function()
            kicked:Disconnect()
            moving:Disconnect()
        end
    end, {})

    local plankHeight = 1 / RIG
    return e("Frame", {
        ref = rigRef,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, TOP),
        Size = UDim2.fromScale(0.32, 0.075 * RIG),
        BackgroundTransparency = 1,
    }, {
        Aspect = e("UIAspectRatioConstraint", { AspectRatio = RIG_ASPECT }),
        LineL = line(0.5 - HOOK_X, (HANG + UNEVEN) / RIG, leftRef),
        LineR = line(0.5 + HOOK_X, (HANG - UNEVEN) / RIG, rightRef),
        Plank = Rustic.plank({
            size = UDim2.fromScale(1, plankHeight),
            position = UDim2.fromScale(0.5, 0.5 + HANG / RIG + plankHeight / 2),
            seams = 1,
            worn = 3,
            zindex = 3, -- in front of the lines and the tag (the HUD layers by ZIndex screen-wide)
            ref = plankRef,
        }, {
            Title = Rustic.text({
                text = props.title,
                font = Theme.Font.Sign,
                color = C.Paper,
                size = UDim2.fromScale(0.86, 0.66),
                maxSize = 34,
                stroke = 2,
                zindex = 5,
            }),
            Nail = if props.tag
                then e("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 1, 3),
                    Size = UDim2.fromOffset(6, 6),
                    BackgroundColor3 = C.IronLight,
                    BorderSizePixel = 0,
                    ZIndex = 6,
                }, {
                    Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
                    Edge = e("UIStroke", { Color = C.Ink, Thickness = 1 }),
                })
                else nil,
        }),
        Tag = if props.tag
            then Rustic.brass({
                size = UDim2.fromScale(0.7, plankHeight * 0.46),
                position = UDim2.fromScale(0.5, 0.5 + HANG / RIG + plankHeight * 1.25),
                zindex = 1, -- behind the plank, so it tucks under it as it swings
                ref = tagRef,
            }, {
                Text = Rustic.text({
                    text = props.tag,
                    font = Theme.Font.Stamp,
                    color = C.Ink,
                    maxSize = 18,
                    zindex = 2,
                }),
            })
            else nil,
    })
end

return HangingSign
