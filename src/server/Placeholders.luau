--!strict
-- Part-built stand-ins for content that hasn't been built in Studio yet, so every stop is playable
-- before any MCP content exists. Floors sit just under the rails (rail tops are at the floor CFrame).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Configs = require(Shared.Configs)

local Placeholders = {}

export type Station = { model: Model, spawn: CFrame, lever: ProximityPrompt }
export type Arena = { model: Model, spawn: CFrame }

local function floorSlab(model: Model, floor: CFrame, size: Vector3, palette: any): Part
    local slab = World.part(
        model,
        "Floor",
        Vector3.new(size.X, 1, size.Z),
        floor * CFrame.new(0, -0.7, 0),
        World.color(palette.RockDark),
        Enum.Material.Slate
    )
    slab.CanCollide = true
    slab.CanQuery = true
    return slab
end

local function sign(model: Model, at: CFrame, title: string, subtitle: string)
    local anchor = World.part(model, "Sign", Vector3.new(1, 1, 1), at, Color3.new(), Enum.Material.SmoothPlastic)
    anchor.Transparency = 1
    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromScale(18, 5) -- studs, so it shrinks with distance (TRAPS #15)
    gui.LightInfluence = 0
    gui.Parent = anchor
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 0.65)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 214, 150)
    label.Text = title
    label.Parent = gui
    local small = Instance.new("TextLabel")
    small.Position = UDim2.fromScale(0, 0.65)
    small.Size = UDim2.fromScale(1, 0.35)
    small.BackgroundTransparency = 1
    small.Font = Enum.Font.GothamMedium
    small.TextScaled = true
    small.TextColor3 = Color3.fromRGB(220, 210, 200)
    small.Text = subtitle
    small.Parent = gui
end

local function lights(model: Model, floor: CFrame, size: Vector3, palette: any)
    local lamp = World.color(palette.Lamp)
    for _, x in { -0.35, 0.35 } do
        for _, z in { -0.3, 0.3 } do
            local bulb = World.part(
                model,
                "Lamp",
                Vector3.new(1, 1, 1),
                floor * CFrame.new(size.X * x, 14, size.Z * z),
                lamp,
                Enum.Material.Neon
            )
            World.light(bulb, 40, 1.6, lamp, true)
        end
    end
end

-- The station: a lit platform around the parked cart, with the lever that starts the run.
function Placeholders.station(parent: Instance, floor: CFrame, size: Vector3, palette: any): Station
    local model = Instance.new("Model")
    model.Name = "Station"
    floorSlab(model, floor, size, palette)
    lights(model, floor, size, palette)

    local post = World.part(
        model,
        "LeverPost",
        Vector3.new(1, 4, 1),
        floor * CFrame.new(7, 2, -2),
        World.color(palette.Timber),
        Enum.Material.Wood
    )
    post.CanQuery = true
    local handle = World.part(
        model,
        "LeverHandle",
        Vector3.new(0.4, 2.5, 0.4),
        floor * CFrame.new(7, 4.6, -2) * CFrame.Angles(0, 0, math.rad(25)),
        Color3.fromRGB(190, 40, 40),
        Enum.Material.Metal
    )
    handle.CanQuery = true
    local lever = Instance.new("ProximityPrompt")
    lever.ActionText = "Start the descent"
    lever.ObjectText = "Lever"
    lever.HoldDuration = 0.5
    lever.MaxActivationDistance = 12
    lever.RequiresLineOfSight = false
    lever.Parent = post

    sign(model, floor * CFrame.new(0, 16, -size.Z / 2 + 6), "LAST CART DOWN", "Pull the lever when the crew is ready")
    model.Parent = parent
    return { model = model, spawn = floor * CFrame.new(14, 4, 6), lever = lever }
end

-- A stop that hasn't been built yet: a lit, empty chamber with the stage's name on a sign.
function Placeholders.arena(parent: Instance, floor: CFrame, size: Vector3, stageId: string, palette: any): Arena
    local stage = Configs.Stages[stageId]
    local model = Instance.new("Model")
    model.Name = stageId
    floorSlab(model, floor, size, palette)
    lights(model, floor, size, palette)
    sign(model, floor * CFrame.new(0, 16, 0), stage.Name, stage.Genre .. " stage (placeholder)")
    model.Parent = parent
    return { model = model, spawn = floor * CFrame.new(12, 4, 0) }
end

return Placeholders
