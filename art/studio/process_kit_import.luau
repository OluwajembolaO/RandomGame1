-- Run in Studio (command bar or the Studio MCP) right after importing a cave kit GLB from art/export with
-- the 3D Importer ("Set Pivot to Scene Origin" and "Anchored" ticked). It turns the import into one Model per
-- chunk in ServerStorage.Content.Kit, pivoted at the chunk's track start, colored and lit like the rest of
-- the kit. Only the chunks in the import are touched; it replaces any older copy of each.
--
-- After it runs, save the new chunks into the repo: right-click ServerStorage.Content.Kit > Save to File,
-- and split that file into assets/Content/Kit/<Chunk>.rbxm (or save each chunk on its own) (TRAPS #46).

local IMPORT = workspace:FindFirstChild("CaveKit") -- the importer names the model after the Blender scene
assert(IMPORT and IMPORT:IsA("Model"), "import the GLB first: there's no Workspace.CaveKit")

-- build_cave_kit.py's KIT order: piece i sits (i - 1) * SPACING studs along Blender X.
local ORDER = {
    "Station",
    "StopChamber",
    "Tunnel_Straight",
    "Tunnel_BendL",
    "Tunnel_BendR",
    "Tunnel_SharpL",
    "Tunnel_SharpR",
    "Cavern_Lake",
    "Cavern_Chasm",
    "Cavern_Garden",
    "EndCap",
    "Tunnel_Washout",
    "Cavern_Rift",
    "Tunnel_Crystal",
    "Tunnel_Fungus",
    "Tunnel_Steep",
    "Tunnel_Grotto",
    "Tunnel_GentleL",
    "Tunnel_GentleR",
    "Tunnel_LongBendL",
    "Tunnel_LongBendR",
    "Tunnel_HairpinL",
    "Tunnel_HairpinR",
    "Tunnel_WashoutWide",
    "Tunnel_Chute",
    "Cavern_Crystal",
    "Cavern_Pit",
    "Cavern_Pool",
    "Cavern_Glow",
    "Cavern_RiftWide",
}
local SPACING = 700

-- 1. Flatten the importer's _Node wrappers.
for _, node in IMPORT:GetChildren() do
    if node:IsA("Model") then
        for _, child in node:GetChildren() do
            child.Parent = IMPORT
        end
        node:Destroy()
    end
end

-- 2. Turn it around (TRAPS #39): Blender +Y becomes Roblox -Z, the chunks' forward.
local pivot = IMPORT:GetPivot()
IMPORT:PivotTo(pivot * CFrame.Angles(0, math.pi, 0))
IMPORT.WorldPivot = CFrame.new(pivot.Position)
local origin = pivot.Position

-- 3. The look of each mesh group (the importer drops plain material colors).
local CRYSTAL = {
    Blue = Color3.fromRGB(40, 110, 255),
    Green = Color3.fromRGB(30, 230, 110),
    Red = Color3.fromRGB(240, 40, 60),
    Yellow = Color3.fromRGB(255, 185, 40),
}
local function look(part: MeshPart, group: string): boolean
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    local color = CRYSTAL[group:match("^Crystals_(%a+)$") or group:match("^Mushrooms_(%a+)$") or ""]
    if color then
        part.Material = Enum.Material.Neon
        part.Color = color
    elseif group == "Rock" then
        part.Material = Enum.Material.Slate
        part.Color = Color3.fromRGB(92, 84, 80)
        part.CastShadow = true
    elseif group == "Timber" then
        part.Material = Enum.Material.Wood
        part.Color = Color3.fromRGB(110, 78, 48)
        part.CastShadow = true
    elseif group == "Lanterns" then
        part.Material = Enum.Material.Metal
        part.Color = Color3.fromRGB(150, 112, 56)
    elseif group == "LanternGlass" then
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 196, 120)
    elseif group == "Glowworms" then
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(150, 235, 255)
    elseif group == "Threads" then
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Color3.fromRGB(130, 140, 150)
        part.Transparency = 0.5
    elseif group == "Stems" then
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Color3.fromRGB(215, 205, 185)
    elseif group == "Water" then
        part.Material = Enum.Material.Glass
        part.Color = Color3.fromRGB(30, 95, 105)
        part.Transparency = 0.2
        part.Reflectance = 0.2
    else
        return false
    end
    return true
end

-- 4. One model per chunk in the import, pivoted at its track start.
local kit = game:GetService("ServerStorage").Content.Kit
local report, unknown = {}, {}
for index, name in ORDER do
    local parts = {}
    for _, part in IMPORT:GetChildren() do
        local pieceName = part.Name:match("^(.-)__.+$")
        if part:IsA("MeshPart") and pieceName == name then
            table.insert(parts, part)
        end
    end
    if #parts > 0 then
        local old = kit:FindFirstChild(name)
        if old then
            old:Destroy()
        end
        local piece = Instance.new("Model")
        piece.Name = name
        for _, part in parts do
            local group = part.Name:match("^.-__(.+)$") :: string
            part.Name = group
            if not look(part, group) then
                table.insert(unknown, name .. "." .. group)
            end
            part.Parent = piece
        end
        piece.WorldPivot = CFrame.new(origin + Vector3.new((index - 1) * SPACING, 0, 0))
        piece.Parent = kit
        report[name] = #parts
    end
end
local leftover = #IMPORT:GetChildren()
if leftover == 0 then
    IMPORT:Destroy()
end
game:GetService("ChangeHistoryService"):SetWaypoint("Process cave kit import")
return { chunks = report, unknownGroups = unknown, leftover = leftover }
