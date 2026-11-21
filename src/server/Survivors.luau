--!strict
-- The crew's characters. Players.CharacterAutoLoads is off, so the Director decides who spawns where:
-- at the station, at a stop, or next to the cart. Anyone who dies waits for the next stop.

local Players = game:GetService("Players")

local Groups = require(script.Parent.Groups)
local Weapons = require(script.Parent.Weapons)

local Survivors = {}

local spawnAt = CFrame.new(0, 1300, 0)

function Survivors.setSpawn(at: CFrame)
    spawnAt = at
end

local function scatter(at: CFrame): CFrame
    return at * CFrame.new(math.random(-30, 30) / 10, 0, math.random(-30, 30) / 10)
end

function Survivors.alive(player: Player): boolean
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0 and character ~= nil and character.Parent ~= nil
end

-- (Re)loads a player's character at `at` (or the current spawn) and hands out their gear.
function Survivors.spawn(player: Player, at: CFrame?)
    if not player.Parent then
        return
    end
    player:LoadCharacter()
    local character = player.Character
    if character then
        character:PivotTo(scatter(at or spawnAt))
    end
    Weapons.give(player)
end

-- Spawns everyone who has no living character.
function Survivors.respawnDead(at: CFrame)
    for _, player in Players:GetPlayers() do
        if not Survivors.alive(player) then
            Survivors.spawn(player, at)
        end
    end
end

function Survivors.teleport(player: Player, at: CFrame)
    local character = player.Character
    if character and Survivors.alive(player) then
        character:PivotTo(scatter(at))
    end
end

-- Everyone with a living character.
function Survivors.crew(): { Player }
    local list = {}
    for _, player in Players:GetPlayers() do
        if Survivors.alive(player) then
            table.insert(list, player)
        end
    end
    return list
end

local function watch(player: Player)
    player.CharacterAdded:Connect(function(character)
        Groups.assign(character, Groups.Crew)
    end)
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
    watch(player)
end

return Survivors
