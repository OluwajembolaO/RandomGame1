--!strict
-- The HUD's rustic building blocks (colors and fonts from Shared/Theme): grained planks bound with iron
-- and studded with brass rivets (and, if `worn`, knotted, dented, scratched and cracked), parchment notes
-- (stained, if `stained`), brass plates, painted and stamped lettering, and an iron trough of a bar. Sizes
-- are Scale (with aspect and text-size caps), so the HUD reads on phones and monitors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Theme = require(ReplicatedStorage.Shared.Theme)

local e = React.createElement
local C = Theme.Color

local Rustic = {}

export type Box = {
    size: UDim2,
    position: UDim2,
    anchor: Vector2?,
    rotation: number?,
    aspect: number?, -- width / height, kept whatever the screen
    zindex: number?,
    ref: any?, -- a React ref to the frame, for animating it
}

local function merge(a: { [string]: any }, b: { [string]: any }?): { [string]: any }
    local out = table.clone(a)
    if b then
        for key, value in b do
            out[key] = value
        end
    end
    return out
end

local function frameProps(box: Box, extra: { [string]: any }): { [string]: any }
    return merge({
        AnchorPoint = box.anchor or Vector2.new(0.5, 0.5),
        Position = box.position,
        Size = box.size,
        Rotation = box.rotation or 0,
        ZIndex = box.zindex or 1,
        BorderSizePixel = 0,
        ref = box.ref,
    }, extra)
end

local function aspect(box: Box): any
    return if box.aspect then e("UIAspectRatioConstraint", { AspectRatio = box.aspect }) else nil
end

-- Text that scales with its box but stays between minSize and maxSize points.
function Rustic.text(props: {
    text: string,
    font: Font?,
    color: Color3?,
    size: UDim2?,
    position: UDim2?,
    anchor: Vector2?,
    maxSize: number?,
    minSize: number?,
    align: Enum.TextXAlignment?,
    stroke: number?,
    zindex: number?,
    ref: any?,
})
    return e("TextLabel", {
        ref = props.ref,
        AnchorPoint = props.anchor or Vector2.new(0.5, 0.5),
        Position = props.position or UDim2.fromScale(0.5, 0.5),
        Size = props.size or UDim2.fromScale(0.9, 0.8),
        BackgroundTransparency = 1,
        FontFace = props.font or Theme.Font.Sign,
        Text = props.text,
        TextColor3 = props.color or C.Paper,
        TextScaled = true,
        TextXAlignment = props.align or Enum.TextXAlignment.Center,
        ZIndex = props.zindex or 2,
    }, {
        Cap = e("UITextSizeConstraint", { MaxTextSize = props.maxSize or 40, MinTextSize = props.minSize or 8 }),
        Stroke = if (props.stroke or 0) > 0
            then e("UIStroke", { Thickness = props.stroke, Color = C.Ink, Transparency = 0.1 })
            else nil,
    })
end

-- A brass rivet head in one corner (x, y are 0 or 1), drawn over a plank at `z`. The HUD's ScreenGui
-- layers by ZIndex across the whole screen (Global), so everything drawn on a plank sits at or above it.
local function rivet(x: number, y: number, z: number?)
    return e("Frame", {
        AnchorPoint = Vector2.new(x, y),
        Position = UDim2.new(x, if x == 0 then 5 else -5, y, if y == 0 then 5 elseif y == 1 then -5 else 0),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = C.Brass,
        BorderSizePixel = 0,
        ZIndex = (z or 1) + 2,
    }, {
        Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        Shade = e("UIGradient", {
            Color = ColorSequence.new(C.Paper, C.BrassDark),
            Rotation = 45,
        }),
    })
end

-- A small random stream from a seed, so a plank's wear is the same every time it's drawn.
local function stream(seed: number): () -> number
    local state = (seed * 7919 + 13) % 2147483646 + 1
    return function(): number
        state = state * 48271 % 2147483647
        return state / 2147483647
    end
end

-- Years of knocks on a plank: knots in the grain, dents, scratches, and a crack running in from an edge.
-- The same `seed` always wears the same way; `z` is the plank's ZIndex.
local function wear(seed: number, z: number): { [string]: any }
    local rand = stream(seed)
    local parts: { [string]: any } = {}
    for index = 1, 2 do
        local width = 0.03 + rand() * 0.02
        parts["Knot" .. index] = e("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.08 + rand() * 0.84, 0.22 + rand() * 0.56),
            Size = UDim2.fromScale(width, width * (2.5 + rand() * 1.5)),
            Rotation = rand() * 30 - 15,
            BackgroundColor3 = C.WoodDark,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            ZIndex = z,
        }, {
            Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
            Ring = e("UIStroke", { Color = C.WoodDark, Thickness = 1.5, Transparency = 0.5 }),
        })
    end
    for index = 1, 3 do
        parts["Dent" .. index] = e("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.06 + rand() * 0.88, 0.15 + rand() * 0.7),
            Size = UDim2.fromScale(0.03 + rand() * 0.06, 0.14 + rand() * 0.18),
            Rotation = rand() * 60 - 30,
            BackgroundColor3 = C.WoodDark,
            BackgroundTransparency = 0.68,
            BorderSizePixel = 0,
            ZIndex = z,
        }, { Round = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
    end
    for index = 1, 5 do
        parts["Scratch" .. index] = e("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.08 + rand() * 0.84, 0.12 + rand() * 0.76),
            Size = UDim2.new(0.05 + rand() * 0.13, 0, 0, 1),
            Rotation = rand() * 36 - 18,
            BackgroundColor3 = C.WoodLight:Lerp(C.Paper, 0.35),
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            ZIndex = z,
        })
    end
    local fromLeft = rand() < 0.5
    parts.Crack = e("Frame", {
        AnchorPoint = Vector2.new(if fromLeft then 0 else 1, 0.5),
        Position = UDim2.fromScale(if fromLeft then 0 else 1, 0.25 + rand() * 0.5),
        Size = UDim2.new(0.1 + rand() * 0.12, 0, 0, 2),
        Rotation = (rand() * 10 - 5) * (if fromLeft then 1 else -1),
        BackgroundColor3 = C.Ink,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        ZIndex = z,
    })
    return parts
end

-- A wooden plank (or a few, `seams` lines across it), bound with an iron band and brass rivets; `worn` is a
-- seed for its knots, dents, scratches and crack.
function Rustic.plank(
    box: Box & { seams: number?, dark: boolean?, rivets: boolean?, worn: number? },
    children: { [string]: any }?
)
    local light = if box.dark then C.Wood else C.WoodLight
    local z = box.zindex or 1
    local parts: { [string]: any } = {
        Aspect = aspect(box),
        Grain = e("UIGradient", { Color = Theme.grain(light, C.WoodDark), Rotation = 90 }),
        Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
        Band = e("UIStroke", {
            Color = C.Iron,
            Thickness = 3,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
    }
    for index = 1, box.seams or 0 do
        parts["Seam" .. index] = e("Frame", {
            Position = UDim2.fromScale(0, index / ((box.seams :: number) + 1)),
            Size = UDim2.new(1, 0, 0, 2),
            BackgroundColor3 = C.WoodDark,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = z,
        })
    end
    if box.rivets ~= false then
        parts.RivetTL, parts.RivetTR = rivet(0, 0, z), rivet(1, 0, z)
        parts.RivetBL, parts.RivetBR = rivet(0, 1, z), rivet(1, 1, z)
    end
    if box.worn then
        parts = merge(parts, wear(box.worn, z))
    end
    return e("Frame", frameProps(box, { BackgroundColor3 = Color3.new(1, 1, 1) }), merge(parts, children))
end

-- A scrap of parchment: aged paper, darker at the edges, inked text on it; `stained` is a seed for a ring or
-- two of old coffee and grime.
function Rustic.paper(box: Box & { stained: number? }, children: { [string]: any }?)
    local parts: { [string]: any } = {
        Aspect = aspect(box),
        Age = e("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, C.PaperDark),
                ColorSequenceKeypoint.new(0.15, C.Paper),
                ColorSequenceKeypoint.new(0.85, C.Paper),
                ColorSequenceKeypoint.new(1, C.PaperDark),
            }),
        }),
        Edge = e("UIStroke", { Color = C.WoodDark, Thickness = 1.5, Transparency = 0.3 }),
    }
    if box.stained then
        local rand = stream(box.stained)
        for index = 1, 2 do
            local size = 0.12 + rand() * 0.1
            parts["Stain" .. index] = e("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.05 + rand() * 0.9, 0.2 + rand() * 0.6),
                Size = UDim2.fromScale(size, 1),
                BackgroundColor3 = C.PaperDark:Lerp(C.Rust, 0.25),
                BackgroundTransparency = 0.8,
                BorderSizePixel = 0,
                ZIndex = box.zindex or 1,
            }, {
                Square = e("UIAspectRatioConstraint", { AspectRatio = 1 }),
                Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
                Ring = e("UIStroke", { Color = C.Rust, Thickness = 1.5, Transparency = 0.7 }),
            })
        end
    end
    return e("Frame", frameProps(box, { BackgroundColor3 = Color3.new(1, 1, 1) }), merge(parts, children))
end

-- A brass plate with engraved (dark) lettering.
function Rustic.brass(box: Box, children: { [string]: any }?)
    return e(
        "Frame",
        frameProps(box, { BackgroundColor3 = Color3.new(1, 1, 1) }),
        merge({
            Aspect = aspect(box),
            Shine = e("UIGradient", {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, C.BrassDark),
                    ColorSequenceKeypoint.new(0.35, C.Brass),
                    ColorSequenceKeypoint.new(0.6, C.Paper:Lerp(C.Brass, 0.5)),
                    ColorSequenceKeypoint.new(1, C.BrassDark),
                }),
                Rotation = 90,
            }),
            Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
            Edge = e("UIStroke", {
                Color = C.WoodDark,
                Thickness = 2,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            }),
        }, children)
    )
end

-- A bar in an iron trough: `fraction` filled with `color`, a stamped caption on top.
function Rustic.bar(box: Box & { fraction: number, color: Color3, caption: string })
    return e("Frame", frameProps(box, { BackgroundColor3 = C.Iron }), {
        Aspect = aspect(box),
        Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
        Edge = e("UIStroke", { Color = C.WoodDark, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
        Fill = e("Frame", {
            Position = UDim2.fromOffset(3, 3),
            Size = UDim2.new(math.clamp(box.fraction, 0, 1), -6, 1, -6),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
        }, {
            Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
            Shade = e("UIGradient", {
                Color = ColorSequence.new(box.color:Lerp(C.Paper, 0.25), box.color:Lerp(C.Ink, 0.35)),
                Rotation = 90,
            }),
        }),
        Caption = Rustic.text({
            text = box.caption,
            font = Theme.Font.Stamp,
            color = C.Paper,
            size = UDim2.fromScale(0.94, 0.8),
            maxSize = 18,
            stroke = 1.5,
            zindex = 3,
        }),
        RivetL = rivet(0, 0.5),
        RivetR = rivet(1, 0.5),
    })
end

return Rustic
