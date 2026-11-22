--!strict
-- The depth meter down the right of the screen: a timber post running from the station (top) to the last
-- stop (bottom), with a brass tick at every segment, a plate at every stop, and a lamp marking the cart.
-- Under it, how far it is to the next stop. The route is laid out here from the run's seed (Rules/Layout is
-- pure, so it matches the server's), and only the cart's distance along the track is sent (RunInfo.Distance).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)
local Layout = require(Shared.Rules.Layout)
local Route = require(Shared.Rules.Route)
local RunInfo = require(Shared.RunInfo)
local Theme = require(Shared.Theme)
local Rustic = require(script.Parent.Rustic)
local useAttribute = require(script.Parent.useAttribute)

local e = React.createElement
local C = Theme.Color
local info = RunInfo.instance()

type Stop = { at: number, name: string }
-- A stretch between stops, labeled with its difficulty halfway along.
type Stretch = { at: number, difficulty: string }
type Plan = { start: number, finish: number, ticks: { number }, stops: { Stop }, stretches: { Stretch } }

local DIFFICULTY_COLOR = { Easy = Theme.Color.Safe, Medium = Theme.Color.Brass, Hard = Theme.Color.Danger }

local function plan(seed: number): Plan?
    if seed == 0 then
        return nil
    end
    local zone = Configs.Zones[1]
    local route = Route.generate(zone, seed)
    local layout = Layout.build(route, zone.Kit, Configs.Kit.Pieces, Layout.spec(Configs.Run))
    local ticks = {}
    for _, placement in layout.placements do
        if placement.number > 0 then
            table.insert(ticks, placement.from)
        end
    end
    local stops: { Stop } = {}
    local stretches: { Stretch } = {}
    local previous = layout.parked
    for index, leg in route.legs do
        local stage = leg.stop.stage
        local name = if stage then Configs.Stages[stage].Name else "Fork in the line"
        table.insert(stops, { at = layout.stops[index], name = name })
        table.insert(stretches, { at = (previous + layout.stops[index]) / 2, difficulty = leg.difficulty })
        previous = layout.stops[index]
    end
    return {
        start = layout.parked,
        finish = stops[#stops].at,
        ticks = ticks,
        stops = stops,
        stretches = stretches,
    }
end

local POST_X = 0.62 -- where the post stands across the meter's width

local function DepthMeter(): any
    local seed = useAttribute(info, "Seed", 0)
    local distance = useAttribute(info, "Distance", 0)
    local layoutPlan = React.useMemo(function()
        return plan(seed)
    end, { seed })
    if not layoutPlan then
        return nil
    end
    local route = layoutPlan :: Plan
    local span = math.max(1, route.finish - route.start)
    local function depth(at: number): number
        return math.clamp((at - route.start) / span, 0, 1)
    end

    local children: { [string]: any } = {
        Post = Rustic.plank({
            size = UDim2.new(0, 16, 1, 0),
            position = UDim2.fromScale(POST_X, 0.5),
            dark = true,
            rivets = false,
        }),
        -- The cart: a lamp on the right of the post, clear of the stop plates on the left.
        Lamp = e("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(POST_X, 12, depth(distance), 0),
            Size = UDim2.fromOffset(22, 22),
            BackgroundColor3 = C.Lamp,
            BorderSizePixel = 0,
            Rotation = 45,
            ZIndex = 6,
        }, {
            Glow = e("UIStroke", { Color = C.Ink, Thickness = 2 }),
            Shade = e("UIGradient", { Color = ColorSequence.new(C.Paper, C.Brass), Rotation = 90 }),
        }),
    }
    for index, at in route.ticks do
        children["Tick" .. index] = e("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(POST_X, depth(at)),
            Size = UDim2.fromOffset(if index % 5 == 0 then 26 else 18, 2),
            BackgroundColor3 = if at <= distance then C.Brass else C.BrassDark,
            BorderSizePixel = 0,
            ZIndex = 3,
        })
    end
    local nextStop: Stop? = nil
    for index, stop in route.stops do
        local passed = distance >= stop.at - 2
        if not passed and not nextStop then
            nextStop = stop
        end
        children["Stop" .. index] = Rustic.brass({
            size = UDim2.fromOffset(132, 24),
            position = UDim2.new(POST_X, -16, depth(stop.at), 0),
            anchor = Vector2.new(1, 0.5),
            zindex = 4,
        }, {
            Name = Rustic.text({
                text = string.upper(stop.name),
                font = Theme.Font.Stamp,
                color = if passed then C.BrassDark else C.Ink,
                maxSize = 13,
                zindex = 5,
            }),
        })
    end

    for index, stretch in route.stretches do
        children["Stretch" .. index] = Rustic.text({
            text = string.upper(stretch.difficulty),
            font = Theme.Font.Stamp,
            color = DIFFICULTY_COLOR[stretch.difficulty] or C.Paper,
            size = UDim2.fromOffset(70, 16),
            position = UDim2.new(POST_X, -16, depth(stretch.at), 0),
            anchor = Vector2.new(1, 0.5),
            align = Enum.TextXAlignment.Right,
            maxSize = 12,
            stroke = 1.5,
        })
    end

    local goal = nextStop
    local toGo = if goal then math.max(0, math.floor(goal.at - distance)) else 0
    return e("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.44, 0),
        Size = UDim2.new(0, 170, 0.5, 0),
        BackgroundTransparency = 1,
    }, {
        Track = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children),
        Gauge = Rustic.plank({
            size = UDim2.new(1, 0, 0, 74),
            position = UDim2.new(0.5, 0, 1, 28),
            anchor = Vector2.new(0.5, 0),
            seams = 1,
            worn = 11,
        }, {
            To = Rustic.text({
                text = if goal then "TO " .. string.upper(goal.name) else "JOURNEY'S END",
                font = Theme.Font.Stamp,
                color = C.PaperDark,
                size = UDim2.fromScale(0.9, 0.3),
                position = UDim2.fromScale(0.5, 0.2),
                maxSize = 12,
            }),
            Distance = Rustic.text({
                text = if goal then tostring(toGo) else "—",
                font = Theme.Font.Number,
                color = C.Lamp,
                size = UDim2.fromScale(0.9, 0.46),
                position = UDim2.fromScale(0.5, 0.56),
                maxSize = 30,
                stroke = 1.5,
            }),
            Unit = Rustic.text({
                text = "STUDS",
                font = Theme.Font.Stamp,
                color = C.PaperDark,
                size = UDim2.fromScale(0.9, 0.2),
                position = UDim2.fromScale(0.5, 0.88),
                maxSize = 10,
            }),
        }),
    })
end

return DepthMeter
