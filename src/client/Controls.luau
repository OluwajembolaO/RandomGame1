--!strict
-- The camera and riding controls. The game is played in first person, and the camera always follows
-- your own character. While the server marks you as Riding, jumping is off (so you can't hop out of the
-- cart) and the brake is bound to F / gamepad X / an on-screen button.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local BRAKE = "Brake"

local Controls = {}

local function onBrake(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
    if inputState == Enum.UserInputState.Begin then
        Remotes.Brake:FireServer()
    end
    return Enum.ContextActionResult.Sink
end

local function apply()
    local riding = player:GetAttribute("Riding") == true
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not riding)
    end
    if riding then
        ContextActionService:BindAction(BRAKE, onBrake, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
        ContextActionService:SetTitle(BRAKE, "BRAKE")
        ContextActionService:SetPosition(BRAKE, UDim2.new(1, -180, 1, -150))
    else
        ContextActionService:UnbindAction(BRAKE)
    end
end

-- First person, following this character. StarterPlayer.CameraMode is set in default.project.json too;
-- setting it here also covers a camera something else left detached (Scriptable, or aimed at nothing).
local function followCharacter()
    player.CameraMode = Enum.CameraMode.LockFirstPerson
    local camera = workspace.CurrentCamera
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
    end
end

function Controls.start()
    player:GetAttributeChangedSignal("Riding"):Connect(apply)
    player.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid")
        followCharacter()
        apply()
    end)
    followCharacter()
    apply()
end

return Controls
