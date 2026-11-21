--!strict
-- The cart. It's an unanchored, server-owned model: AlignPosition and AlignOrientation (rigid) pull it to
-- a target the server moves along the track every frame, so clients see it interpolated like any
-- physics object. Riders sit in welded seats and travel with it. The numbers live in Rules/Cart.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Groups = require(script.Parent.Groups)
local World = require(script.Parent.World)

local Shared = ReplicatedStorage.Shared
local Cart = require(Shared.Rules.Cart)
local Configs = require(Shared.Configs)
local Remotes = require(Shared.Remotes)
local RunInfo = require(Shared.RunInfo)
local Track = require(Shared.Rules.Track)
local TrackFrames = require(Shared.TrackFrames)

local REPLICATE_EVERY = 0.1
local RESEAT_EVERY = 0.5
local SHAKE_EVERY = 0.35
local ARRIVE_WITHIN = 0.3

local CartService = {}

local model: Model? = nil
local root: BasePart? = nil
local alignPosition: AlignPosition? = nil
local alignOrientation: AlignOrientation? = nil
local seats: { Seat } = {}
local track: Track.Track? = nil
local stats: Cart.Stats = Cart.stats(Configs.Run.Cart, {
    CartMaxHp = Configs.Run.Cart.MaxHp,
    BrakeSeconds = Configs.Run.Cart.BrakeSeconds,
    ChewArmor = 1,
})
local state: Cart.Cart = Cart.new(stats)
local distance = 0
local target = 0
local rolling = false
local locked = false
local chewers = 0
local chewDps = 0
local arrived = Instance.new("BindableEvent")
local sinceReplicate = 0
local sinceReseat = 0
local sinceShake = 0
local bank = 0 -- the cart body's current lean (radians), eased toward Cart.bank

local function claimOwnership()
    local part = root
    if part and part:IsDescendantOf(workspace) then
        pcall(function()
            part:SetNetworkOwner(nil)
        end)
    end
end

local function riderOf(seat: Seat): Player?
    local occupant = seat.Occupant
    return if occupant and occupant.Parent then Players:GetPlayerFromCharacter(occupant.Parent) else nil
end

-- Where the Blender cart's riders sit, in its root's space: two benches (front at -Z), two riders each.
-- Bench tops are 3.36 studs above the rails (art/blender/build_cart.py SEAT_TOP and BENCH_Y).
local MESH_SEATS = {
    Vector3.new(-1.3, 3.26, -2.2),
    Vector3.new(1.3, 3.26, -2.2),
    Vector3.new(-1.3, 3.26, 2.3),
    Vector3.new(1.3, 3.26, 2.3),
}
-- The brake lever swings about this point (build_cart.py PIVOT, in Roblox axes).
local LEVER_PIVOT = Vector3.new(3.42, 2.75, 0.6)

-- A joint the client can animate (Motor6D.Transform) that turns `part` about the root's X axis through `pivot`.
local function motor(base: BasePart, part: BasePart, pivot: Vector3)
    local joint = CFrame.new(pivot) * base.CFrame.Rotation
    local motor6d = Instance.new("Motor6D")
    motor6d.Name = part.Name .. "Motor"
    motor6d.Part0 = base
    motor6d.Part1 = part
    motor6d.C0 = base.CFrame:ToObjectSpace(joint)
    motor6d.C1 = part.CFrame:ToObjectSpace(joint)
    motor6d.Parent = base
end

local function attach(base: BasePart, part: BasePart)
    local joint = Instance.new("WeldConstraint")
    joint.Part0 = base
    joint.Part1 = part
    joint.Parent = part
end

-- The Blender-made cart from ServerStorage.Content.Cart (assets/Content/Cart.rbxm), if it's there.
local function contentCart(): Model?
    local content = ServerStorage:FindFirstChild("Content")
    local cart = content and content:FindFirstChild("Cart")
    if cart and cart:IsA("Model") and cart.PrimaryPart then
        return cart
    end
    return nil
end

-- Rigs a copy of the Blender cart: wheels and brake lever on motors the client animates, everything else
-- welded to the root, seats on the benches, the headlamp beam and a flickering lantern.
local function buildFromContent(template: Model): (Model, BasePart, { Seat })
    local cart = template:Clone()
    cart.Name = "Cart"
    local base = cart.PrimaryPart :: BasePart
    base.Anchored = false
    base.RootPriority = 127
    local rootFrame = base.CFrame

    for _, part in cart:GetDescendants() do
        if part:IsA("BasePart") and part ~= base then
            part.Anchored = false
            part.Massless = true
            if part.Name:match("^Wheel_") then
                motor(base, part, part.Position)
            elseif part.Name == "BrakeLever" then
                motor(base, part, rootFrame:PointToWorldSpace(LEVER_PIVOT))
            elseif part.Name ~= "BrakeGrip" then
                attach(base, part)
            end
        end
    end
    local lever, grip = cart:FindFirstChild("BrakeLever"), cart:FindFirstChild("BrakeGrip")
    if lever and grip and lever:IsA("BasePart") and grip:IsA("BasePart") then
        attach(lever, grip)
    elseif grip and grip:IsA("BasePart") then
        attach(base, grip)
    end

    -- The headlamp beam and the lantern's light are made by each client (client/CartFx; TRAPS #42).

    local list: { Seat } = {}
    for index = 1, Configs.Run.Cart.Seats do
        local seat = Instance.new("Seat")
        seat.Name = "Seat" .. index
        seat.Size = Vector3.new(1.8, 0.2, 1.2)
        seat.CFrame = rootFrame * CFrame.new(MESH_SEATS[(index - 1) % #MESH_SEATS + 1])
        seat.Transparency = 1
        seat.CanCollide = false
        seat.Massless = true
        seat.Parent = cart
        attach(base, seat)
        table.insert(list, seat)
    end

    Groups.assign(cart, Groups.Cart)
    return cart, base, list
end

-- Builds the part-built stand-in cart around a root at rail height. Forward is -Z (the root's LookVector).
local function buildPlaceholder(palette: any): (Model, BasePart, { Seat })
    local cart = Instance.new("Model")
    cart.Name = "Cart"
    local base = Instance.new("Part")
    base.Name = "Root"
    base.Size = Vector3.new(1, 1, 1)
    base.Transparency = 1
    base.CanCollide = false
    base.CanQuery = false
    base.CanTouch = false
    base.RootPriority = 127
    base.Parent = cart
    cart.PrimaryPart = base

    local iron = World.color(palette.Rail)
    local wood = World.color(palette.Timber)
    local function add(
        name: string,
        size: Vector3,
        offset: CFrame,
        color: Color3,
        material: Enum.Material,
        solid: boolean
    )
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.CFrame = offset
        part.Color = color
        part.Material = material
        part.CanCollide = solid
        part.CanTouch = false
        part.Massless = true
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Parent = cart
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = base
        weld.Part1 = part
        weld.Parent = part
        return part
    end

    add("Floor", Vector3.new(7, 0.6, 10), CFrame.new(0, 1.5, 0), wood, Enum.Material.WoodPlanks, true)
    add("WallLeft", Vector3.new(0.5, 2.6, 10), CFrame.new(-3.25, 3.1, 0), iron, Enum.Material.CorrodedMetal, true)
    add("WallRight", Vector3.new(0.5, 2.6, 10), CFrame.new(3.25, 3.1, 0), iron, Enum.Material.CorrodedMetal, true)
    add("WallFront", Vector3.new(7, 2.6, 0.5), CFrame.new(0, 3.1, -4.75), iron, Enum.Material.CorrodedMetal, true)
    add("WallBack", Vector3.new(7, 2.6, 0.5), CFrame.new(0, 3.1, 4.75), iron, Enum.Material.CorrodedMetal, true)
    for _, x in { -3.6, 3.6 } do
        for _, z in { -3.4, 3.4 } do
            local wheel =
                add("Wheel", Vector3.new(0.8, 2.2, 2.2), CFrame.new(x, 1.1, z), iron, Enum.Material.Metal, false)
            wheel.Shape = Enum.PartType.Cylinder
        end
    end

    local lamp = add(
        "Headlamp",
        Vector3.new(1.4, 1, 0.6),
        CFrame.new(0, 4.6, -5.1),
        World.color(palette.Lamp),
        Enum.Material.Neon,
        false
    )
    local beam = Instance.new("SpotLight")
    beam.Name = "Beam"
    beam.Face = Enum.NormalId.Front
    beam.Angle = 70
    beam.Brightness = 5
    beam.Range = Configs.Run.Cart.HeadlampRange
    beam.Color = World.color(palette.Lamp)
    beam.Shadows = true
    beam.Parent = lamp
    World.light(base, 16, 1.2, World.color(palette.Lamp), false)

    local list: { Seat } = {}
    local spots = {
        Vector3.new(-1.6, 2.2, -2.3),
        Vector3.new(1.6, 2.2, -2.3),
        Vector3.new(-1.6, 2.2, 2.3),
        Vector3.new(1.6, 2.2, 2.3),
    }
    for index = 1, Configs.Run.Cart.Seats do
        local spot = spots[(index - 1) % #spots + 1]
        local seat = Instance.new("Seat")
        seat.Name = "Seat" .. index
        seat.Size = Vector3.new(2, 0.8, 2)
        seat.CFrame = CFrame.new(spot)
        seat.Color = wood
        seat.Material = Enum.Material.Wood
        seat.Massless = true
        seat.TopSurface = Enum.SurfaceType.Smooth
        seat.Parent = cart
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = base
        weld.Part1 = seat
        weld.Parent = seat
        table.insert(list, seat)
    end

    Groups.assign(cart, Groups.Cart)
    return cart, base, list
end

local function build(palette: any): (Model, BasePart, { Seat })
    local template = contentCart()
    if template then
        return buildFromContent(template)
    end
    return buildPlaceholder(palette)
end

local function pose()
    local current = track
    if not current or not alignPosition or not alignOrientation then
        return
    end
    local frame = TrackFrames.frame(current, distance)
    alignPosition.Position = frame.Position
    -- Lean about the rails' line, so the cart tips onto its outer wheels in a bend.
    alignOrientation.CFrame = frame.Rotation * CFrame.Angles(0, 0, bank)
end

local function setRiding(player: Player, riding: boolean)
    if player:GetAttribute("Riding") ~= riding then
        player:SetAttribute("Riding", riding)
    end
end

function CartService.spawn(
    parent: Instance,
    newTrack: Track.Track,
    at: number,
    palette: any,
    newStats: Cart.Stats
): Model
    CartService.destroy()
    track = newTrack
    stats = newStats
    state = Cart.new(stats)
    distance = at
    target = at
    rolling = false
    locked = false
    chewers = 0
    bank = 0

    -- Pivot onto the track before parenting, so the unanchored parts never fall from the origin.
    local cart, base, list = build(palette)
    model, root, seats = cart, base, list
    cart:PivotTo(TrackFrames.frame(newTrack, at))

    local attachment = Instance.new("Attachment")
    attachment.Parent = base
    local position = Instance.new("AlignPosition")
    position.Mode = Enum.PositionAlignmentMode.OneAttachment
    position.Attachment0 = attachment
    position.RigidityEnabled = true
    position.Parent = base
    local orientation = Instance.new("AlignOrientation")
    orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    orientation.Attachment0 = attachment
    orientation.RigidityEnabled = true
    orientation.Parent = base
    alignPosition, alignOrientation = position, orientation
    pose()
    cart.Parent = parent
    claimOwnership()

    for _, seat in list do
        seat:GetPropertyChangedSignal("Occupant"):Connect(function()
            -- A player sitting down would otherwise take network ownership of the whole cart.
            claimOwnership()
            local rider = riderOf(seat)
            if rider then
                setRiding(rider, locked)
            end
        end)
    end
    return cart
end

function CartService.destroy()
    for _, player in Players:GetPlayers() do
        setRiding(player, false)
    end
    if model then
        model:Destroy()
    end
    model, root, alignPosition, alignOrientation, track = nil, nil, nil, nil, nil
    seats = {}
    rolling = false
end

function CartService.model(): Model?
    return model
end

function CartService.frame(): CFrame
    return if track then TrackFrames.frame(track, distance) else CFrame.new()
end

function CartService.distance(): number
    return distance
end

-- Starts rolling toward `stopAt` (a distance along the track). Use waitForArrival to wait for it.
function CartService.rideTo(stopAt: number)
    target = stopAt
    rolling = true
end

-- Yields until the cart reaches its stop (true) or is wrecked on the way (false).
function CartService.waitForArrival(): boolean
    if not rolling then
        return not Cart.wrecked(state)
    end
    return arrived.Event:Wait()
end

function CartService.halt()
    rolling = false
end

function CartService.riders(): { Player }
    local list = {}
    for _, seat in seats do
        local rider = riderOf(seat)
        if rider then
            table.insert(list, rider)
        end
    end
    return list
end

function CartService.isRiding(player: Player): boolean
    return table.find(CartService.riders(), player) ~= nil
end

-- Sits a player in the first free seat. Returns false if they're dead, already seated, or it's full.
function CartService.seat(player: Player): boolean
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or CartService.isRiding(player) then
        return false
    end
    for _, seat in seats do
        if not seat.Occupant then
            seat:Sit(humanoid)
            return true
        end
    end
    return false
end

function CartService.unseatAll()
    for _, seat in seats do
        local occupant = seat.Occupant
        if occupant then
            occupant.Sit = false
        end
        local weld = seat:FindFirstChild("SeatWeld")
        if weld then
            weld:Destroy()
        end
    end
end

-- While locked, riders can't jump out (the client disables jumping) and anyone who falls off is put back.
function CartService.setLocked(value: boolean)
    locked = value
    for _, player in Players:GetPlayers() do
        setRiding(player, value and CartService.isRiding(player))
    end
end

function CartService.stats(): Cart.Stats
    return stats
end

-- New stats mid-run (after an upgrade). Extra max HP is added to current HP too.
function CartService.setStats(newStats: Cart.Stats)
    state.hp = math.max(0, state.hp + newStats.MaxHp - stats.MaxHp)
    stats = newStats
end

function CartService.hp(): number
    return state.hp
end

function CartService.damage(amount: number)
    Cart.damage(state, amount)
end

function CartService.repair(amount: number)
    Cart.repair(state, stats, amount)
end

function CartService.setChewers(count: number, dps: number)
    chewers, chewDps = count, dps
end

function CartService.sharpAhead(): number
    local current = track
    if not current then
        return -1
    end
    local span = Track.nextSharp(current, distance)
    if not span then
        return -1
    end
    return math.max(0, span.from - distance)
end

-- Who belongs in the cart during a locked ride (Survivors supplies the crew that's still standing).
local crewSource: () -> { Player } = function()
    return Players:GetPlayers()
end

function CartService.setCrewSource(source: () -> { Player })
    crewSource = source
end

-- Puts anyone who fell out during a locked ride back in a seat.
local function reseat()
    for _, player in crewSource() do
        if not CartService.isRiding(player) then
            CartService.seat(player)
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    local current = track
    if not current then
        return
    end
    local remaining = target - distance
    local moving = rolling and remaining > 0
    local grade, curvature = Track.shapeAt(current, distance)
    local damage = Cart.step(state, stats, dt, {
        moving = moving,
        sharp = Track.sharpAt(current, distance),
        chewers = chewers,
        chewDps = chewDps,
        grade = grade,
        curvature = curvature,
    })
    bank += (Cart.bank(stats, state.speed, curvature) - bank) * math.min(1, dt * 4)
    sinceShake += dt
    if damage > 0 and sinceShake >= SHAKE_EVERY and Track.sharpAt(current, distance) then
        sinceShake = 0
        Remotes.Effect:FireAllClients("Shake", 0.5)
    end
    -- Ease into the stop: never faster than the brakes could halt in the distance left.
    state.speed = math.min(state.speed, math.sqrt(2 * stats.Accel * 2 * math.max(remaining, 0)) + 0.5)
    distance = math.min(target, distance + state.speed * dt)
    pose()

    if rolling then
        if Cart.wrecked(state) then
            rolling = false
            arrived:Fire(false)
        elseif target - distance <= ARRIVE_WITHIN then
            distance = target
            rolling = false
            state.speed = 0
            pose()
            arrived:Fire(true)
        end
    end

    if locked then
        sinceReseat += dt
        if sinceReseat >= RESEAT_EVERY then
            sinceReseat = 0
            reseat()
        end
    end

    sinceReplicate += dt
    if sinceReplicate >= REPLICATE_EVERY then
        sinceReplicate = 0
        RunInfo.set("CartHp", math.ceil(state.hp))
        RunInfo.set("CartMaxHp", math.ceil(stats.MaxHp))
        RunInfo.set("Braking", Cart.braking(state))
        RunInfo.set("BrakeReady", state.brakeLeft <= 0 and state.brakeCooldown <= 0)
        RunInfo.set("SharpIn", math.floor(CartService.sharpAhead()))
        RunInfo.set("Speed", math.round(state.speed))
    end
end)

Remotes.Brake.OnServerEvent:Connect(function(player)
    if CartService.isRiding(player) then
        Cart.pullBrake(state, stats)
    end
end)

return CartService
