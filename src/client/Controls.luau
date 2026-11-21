--!strict
-- The camera and riding controls. The game is played in first person, and the camera always follows
-- your own character. While the server marks you as Riding, jumping is off (so you can't hop out of the
-- cart), and you drive the cart:
--   push faster  W / Up / gamepad R2          brake  S / Down / F / gamepad L2 or X
--   lean left    Q / A                        lean right  E / D          (gamepad: left stick)
-- with on-screen buttons on touch. The server combines the whole crew's input: anyone braking wins, and
-- the lean is everyone's average, so a bend taken hard needs the whole crew leaning into it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local BRAKE = "Brake"
local PUSH = "Push"
local LEAN_LEFT = "LeanLeft"
local LEAN_RIGHT = "LeanRight"
local LEAN_STICK = "LeanStick"
local ACTIONS = { BRAKE, PUSH, LEAN_LEFT, LEAN_RIGHT, LEAN_STICK }
-- Above the character controls, so W, A, S and D drive the cart instead of trying to walk.
local PRIORITY = Enum.ContextActionPriority.High.Value
local STICK_DEADZONE = 0.25

local Controls = {}

local held = { [BRAKE] = false, [PUSH] = false, [LEAN_LEFT] = false, [LEAN_RIGHT] = false }
local stick = 0
local sentThrottle, sentLean = 0, 0

local function send()
    local throttle = if held[BRAKE] then -1 elseif held[PUSH] then 1 else 0
    local keys = (if held[LEAN_RIGHT] then 1 else 0) - (if held[LEAN_LEFT] then 1 else 0)
    local lean = if keys ~= 0 then keys else stick
    if throttle ~= sentThrottle or lean ~= sentLean then
        sentThrottle, sentLean = throttle, lean
        Remotes.Drive:FireServer(throttle, lean)
    end
end

local function onHold(action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
    if inputState == Enum.UserInputState.Begin then
        held[action] = true
    elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
        held[action] = false
    end
    send()
    return Enum.ContextActionResult.Sink
end

local function onStick(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
    local x = if inputState == Enum.UserInputState.Cancel then 0 else input.Position.X
    local size = math.max(0, math.abs(x) - STICK_DEADZONE) / (1 - STICK_DEADZONE)
    -- Rounded so a wobbling thumb doesn't flood the server.
    stick = math.round(math.sign(x) * size * 4) / 4
    send()
    return Enum.ContextActionResult.Pass
end

local function bindHold(action: string, title: string, position: UDim2, ...: Enum.KeyCode)
    ContextActionService:BindActionAtPriority(action, onHold, true, PRIORITY, ...)
    ContextActionService:SetTitle(action, title)
    ContextActionService:SetPosition(action, position)
end

local function apply()
    local riding = player:GetAttribute("Riding") == true
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not riding)
    end
    for action in held do
        held[action] = false
    end
    stick = 0
    if riding then
        bindHold(
            BRAKE,
            "BRAKE",
            UDim2.new(1, -180, 1, -150),
            Enum.KeyCode.S,
            Enum.KeyCode.Down,
            Enum.KeyCode.F,
            Enum.KeyCode.ButtonL2,
            Enum.KeyCode.ButtonX
        )
        bindHold(PUSH, "PUSH", UDim2.new(1, -180, 1, -240), Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.ButtonR2)
        bindHold(LEAN_LEFT, "◀ LEAN", UDim2.new(0, 40, 1, -150), Enum.KeyCode.Q, Enum.KeyCode.A)
        bindHold(LEAN_RIGHT, "LEAN ▶", UDim2.new(0, 140, 1, -150), Enum.KeyCode.E, Enum.KeyCode.D)
        ContextActionService:BindActionAtPriority(LEAN_STICK, onStick, false, PRIORITY, Enum.KeyCode.Thumbstick1)
    else
        for _, action in ACTIONS do
            ContextActionService:UnbindAction(action)
        end
    end
    send()
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

-- The server putting this character somewhere (out beside a tipped cart). Done here because this client
-- owns the character's physics: let go of any seat, move, and stop dead (TRAPS #44).
local function place(at: CFrame)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then
        return
    end
    humanoid.Sit = false
    local seat = humanoid.SeatPart
    local weld = seat and seat:FindFirstChild("SeatWeld")
    if weld then
        weld:Destroy()
    end
    character:PivotTo(at)
    for _, part in character:GetDescendants() do
        if part:IsA("BasePart") then
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

function Controls.start()
    Remotes.Effect.OnClientEvent:Connect(function(kind: string, at: any)
        if kind == "Place" and typeof(at) == "CFrame" then
            place(at)
        end
    end)
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
