--!strict
-- The cart. It's an unanchored, server-owned model: AlignPosition and AlignOrientation (rigid) pull it to
-- a target the server moves every frame, so clients see it interpolated like any physics object. Riders
-- sit in welded seats and travel with it. The numbers live in Rules/Cart and Rules/Jump.
--
-- The crew drives it (W/S throttle, Q/E lean; anyone braking wins, the lean is everyone's average). It's
-- always in one of four modes:
--   Track     on the rails, following the track.
--   Flying    jumping a gap fast enough: it flies the arc and lands on the far side.
--   Falling   too slow for a gap: it drops in; the screen fades and it's hauled back for a run-up.
--   Derailed  tipped over (or hauled back): lying beside the rails with the crew out, until they push it
--             back on together.

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
local Jump = require(Shared.Rules.Jump)
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
    TipLimit = Configs.Run.Cart.TipLimit,
    RightSeconds = Configs.Run.Cart.RightSeconds,
    ChewArmor = 1,
})
local state: Cart.Cart = Cart.new(stats)
-- What each rider is holding: throttle -1 brake, 0 nothing, 1 push; lean -1 left .. 1 right.
type Drive = { throttle: number, lean: number }
local drives: { [Player]: Drive } = {}
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
local roll = 0 -- the cart body's current roll (radians), eased toward Cart.roll

type Mode = "Track" | "Flying" | "Falling" | "Derailed"
local mode: Mode = "Track"
-- Where the cart is posed when it isn't following the rails (Flying, Falling, Derailed).
local free: CFrame? = nil

-- A jump in progress: leaving `gap`'s lip at `speed`, `elapsed` seconds ago.
type Flight = {
    gap: Track.Gap,
    speed: number,
    elapsed: number,
    landing: number?, -- horizontal studs past the lip where it comes down (nil: it falls in)
    lipY: number,
    lipRotation: CFrame,
    faded: boolean,
}
local flight: Flight? = nil

-- A tipped cart: easing over from `from` to `resting`, then pushed back on by whoever holds the prompt.
type Crash = {
    from: CFrame,
    resting: CFrame,
    t: number,
    progress: number,
    righting: boolean,
    holders: { [Player]: boolean },
    walkway: Instance,
}
local crash: Crash? = nil

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

local JUMP = Configs.Run.Cart.Jump
local TIP_ANGLE = math.rad(84) -- lying on its side
local TIP_SECONDS = 0.45 -- falling over
local RIGHTING_SECONDS = 0.7 -- swinging back up onto the rails
local FADE_HOLD = 0.45 -- after the fade starts, seconds until the screen is black and the cart can move
local RIDER_SPACING = 3

-- On the rails at the current distance, with the body's roll.
local function onRails(withRoll: number): CFrame
    local current = track :: Track.Track
    return TrackFrames.frame(current, distance) * CFrame.Angles(0, 0, withRoll)
end

local function pose()
    if not track or not alignPosition or not alignOrientation then
        return
    end
    -- Lean about the rails' line, so the cart tips onto its outer wheels in a bend.
    local frame = free or onRails(roll)
    alignPosition.Position = frame.Position
    alignOrientation.CFrame = frame.Rotation
end

local function setRiding(player: Player, riding: boolean)
    if player:GetAttribute("Riding") ~= riding then
        player:SetAttribute("Riding", riding)
    end
end

local function setSeatsDisabled(disabled: boolean)
    for _, seat in seats do
        seat.Disabled = disabled
    end
end

local function endCrash()
    local current = crash
    if current then
        current.walkway:Destroy()
    end
    crash = nil
    local base = root
    if base then
        base.Anchored = false
    end
end

-- The push-back prompt, on its own anchored marker where the cart lies (TRAPS #45: clients can go on
-- treating a prompt on the cart itself as wherever the cart was before a long move). Whoever holds it
-- pushes; more of the crew pushes it back faster.
local function makePrompt(at: Vector3, parent: Instance): ProximityPrompt
    local marker = Instance.new("Part")
    marker.Name = "PushPoint"
    marker.Anchored = true
    marker.CanCollide = false
    marker.CanQuery = false
    marker.CanTouch = false
    marker.Transparency = 1
    marker.Size = Vector3.new(1, 1, 1)
    marker.Position = at
    marker.Parent = parent
    local made = Instance.new("ProximityPrompt")
    made.Name = "PushBack"
    made.ActionText = "Push the cart back on"
    made.ObjectText = "Cart"
    made.HoldDuration = Cart.rightSeconds(stats, 1)
    made.MaxActivationDistance = 14
    made.RequiresLineOfSight = false
    made.Parent = marker
    made.PromptButtonHoldBegan:Connect(function(player)
        local current = crash
        if current then
            current.holders[player] = true
        end
    end)
    made.PromptButtonHoldEnded:Connect(function(player)
        local current = crash
        if current then
            current.holders[player] = nil
        end
    end)
    -- A whole hold is a full solo push: the prompt's own timer can finish a moment before ours does.
    made.Triggered:Connect(function()
        local current = crash
        if current then
            current.progress = math.max(current.progress, 1)
        end
    end)
    return made
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
    roll = 0
    mode, free, flight = "Track", nil, nil

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
    endCrash()
    if model then
        model:Destroy()
    end
    model, root, alignPosition, alignOrientation, track = nil, nil, nil, nil, nil
    seats = {}
    rolling = false
    mode, free, flight = "Track", nil, nil
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

-- Sits a player in the first free seat. Returns false if they're dead, already seated, it's full, or the
-- cart isn't on the rails.
function CartService.seat(player: Player): boolean
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 or CartService.isRiding(player) or mode ~= "Track" then
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

-- The crew's throttle and lean, from everyone riding.
local function crewInput(): (number, number)
    local throttles, leans = {}, {}
    for _, rider in CartService.riders() do
        local drive = drives[rider]
        table.insert(throttles, if drive then drive.throttle else 0)
        table.insert(leans, if drive then drive.lean else 0)
    end
    return Cart.crewThrottle(throttles), Cart.crewLean(leans)
end

-- An invisible floor along the rails around the crash, so the crew can stand beside the cart anywhere
-- (even out on a trestle over a chasm).
local function walkway(around: number): Instance
    local current = track :: Track.Track
    local folder = Instance.new("Folder")
    folder.Name = "CrashWalkway"
    local reach = Configs.Run.Cart.CrashWalkway
    local floorTop = Configs.Run.Track.FloorTop
    local from, to = math.max(0, around - reach), math.min(current.length, around + reach)
    local d = from
    while d < to do
        local length = math.min(8, to - d)
        local frame = TrackFrames.flat(current, d + length / 2)
        local part = Instance.new("Part")
        part.Name = "Walkway"
        part.Anchored = true
        part.Transparency = 1
        part.CastShadow = false
        part.CanQuery = false
        part.CanTouch = false
        -- Thick, so someone landing on it fast can't pass straight through between physics steps.
        part.Size = Vector3.new(18, 6, length + 0.5)
        part.CFrame = frame * CFrame.new(0, floorTop - 3, 0)
        part.Parent = folder
        d += length
    end
    folder.Parent = if model then model.Parent else workspace
    return folder
end

-- Tips the cart over beside the rails: everyone's put out on the other side and has to push it back on.
-- `side` is 1 to fall to the left (the outside of a right bend), -1 to the right.
local function tipOver(side: number, immediate: boolean)
    local current = track :: Track.Track
    local flat = TrackFrames.flat(current, distance)
    local resting = flat * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, side * TIP_ANGLE)

    local riders = CartService.riders()
    for _, rider in riders do
        setRiding(rider, false)
    end
    CartService.unseatAll()
    setSeatsDisabled(true)
    -- Out on the side it didn't fall to. Each rider's own client moves them (TRAPS #44): it owns their
    -- physics, so a server move the same frame they're unseated is overwritten by the seat's position, and
    -- a server move keeps whatever speed they had (falling into a gap, that's straight through the floor).
    -- The server moves them too, in case the message is late.
    for index, rider in riders do
        local spread = (index - (#riders + 1) / 2) * RIDER_SPACING
        local spot = flat * CFrame.new(side * 6, 3, spread)
        Remotes.Effect:FireClient(rider, "Place", spot)
        task.delay(0.3, function()
            local character = rider.Character
            if
                character
                and not CartService.isRiding(rider)
                and (character:GetPivot().Position - spot.Position).Magnitude > 8
            then
                character:PivotTo(spot)
            end
        end)
    end

    Cart.setThrottle(state, 0)
    state.speed = 0
    mode, flight = "Derailed", nil
    crash = {
        from = free or onRails(roll),
        resting = resting,
        t = if immediate then TIP_SECONDS else 0,
        progress = 0,
        righting = false,
        holders = {},
        walkway = walkway(distance),
    }
    free = if immediate then resting else onRails(roll)
    roll = 0
    makePrompt(resting.Position, (crash :: Crash).walkway)
    -- A long jump (hauled back up the line) is set directly on an anchored cart: clients can take seconds
    -- to see a physics assembly that moved that far.
    local base = root
    if immediate and base then
        base.Anchored = true
        base.CFrame = resting
    end
    if not immediate then
        Remotes.Effect:FireAllClients("Sound", "Crash", flat.Position)
        Remotes.Effect:FireAllClients("Shake", 0.9)
    end
end

local function derailedStep(current: Crash, dt: number)
    current.t += dt
    if current.righting then
        local a = math.min(1, current.t / RIGHTING_SECONDS)
        free = current.resting:Lerp(onRails(0), a * a * (3 - 2 * a))
        if a >= 1 then
            endCrash()
            mode, free = "Track", nil
            Cart.righted(state)
            setSeatsDisabled(false)
            if locked then
                reseat()
            end
        end
        return
    end

    local a = math.min(1, current.t / TIP_SECONDS)
    free = current.from:Lerp(current.resting, a * a)
    local pushers = 0
    for player in current.holders do
        if player.Parent then
            pushers += 1
        else
            current.holders[player] = nil
        end
    end
    if pushers > 0 then
        current.progress += dt / Cart.rightSeconds(stats, pushers)
    end
    if current.progress >= 1 then
        current.righting, current.t, current.holders = true, 0, {}
        local marker = current.walkway:FindFirstChild("PushPoint")
        if marker then
            marker:Destroy()
        end
        local base = root
        if base then
            base.Anchored = false
        end
        Remotes.Effect:FireAllClients("Sound", "Creak", current.resting.Position)
    end
end

-- Track distance `along` horizontal studs past a gap's lip.
local function alongToDistance(gap: Track.Gap, along: number): number
    if along <= gap.length then
        return gap.from + along * (gap.to - gap.from) / gap.length
    end
    return gap.to + (along - gap.length) * math.sqrt(1 + gap.grade * gap.grade)
end

local function takeOff(gap: Track.Gap)
    local current = track :: Track.Track
    local speed = math.max(state.speed, 0.5)
    local clears = Jump.clears(JUMP, gap, speed)
    flight = {
        gap = gap,
        speed = speed,
        elapsed = 0,
        landing = if clears then Jump.landing(JUMP, gap, speed) else nil,
        lipY = TrackFrames.position(current, gap.from).Y,
        lipRotation = TrackFrames.frame(current, gap.from - 2).Rotation,
        faded = false,
    }
    distance = gap.from
    mode = if clears then "Flying" else "Falling"
end

-- Where the cart is `along` horizontal studs past the lip, `elapsed` seconds into the jump.
local function arcPoint(current: Flight, along: number, elapsed: number): Vector3
    local lip = math.rad(JUMP.Lip)
    local onTrack = TrackFrames.position(track :: Track.Track, alongToDistance(current.gap, along))
    local rise = current.speed * math.sin(lip) * elapsed - JUMP.Gravity * elapsed * elapsed / 2
    return Vector3.new(onTrack.X, current.lipY - current.gap.grade * along + rise, onTrack.Z)
end

local function flyStep(current: Flight, dt: number)
    current.elapsed += dt
    roll += (0 - roll) * math.min(1, dt * 4)
    local across = current.speed * math.cos(math.rad(JUMP.Lip))
    local along = across * current.elapsed
    local landing = current.landing
    if landing then
        if along >= landing then
            distance = alongToDistance(current.gap, landing)
            mode, flight, free = "Track", nil, nil
            local at = TrackFrames.position(track :: Track.Track, distance)
            Remotes.Effect:FireAllClients("Shake", 0.6)
            Remotes.Effect:FireAllClients("Sound", "Land", at)
            return
        end
        distance = alongToDistance(current.gap, along)
        local here = arcPoint(current, along, current.elapsed)
        local ahead = arcPoint(current, along + across * 0.05, current.elapsed + 0.05)
        free = CFrame.lookAt(here, ahead) * CFrame.Angles(0, 0, roll)
        return
    end

    -- Too slow: it hits the far side and drops into the gap, nose first.
    local short = math.min(along, current.gap.length - 3)
    distance = alongToDistance(current.gap, short)
    local here = arcPoint(current, short, current.elapsed)
    free = CFrame.new(here) * current.lipRotation * CFrame.Angles(-math.min(current.elapsed * 1.2, 1.3), 0, roll)
    if current.elapsed >= JUMP.FallSeconds and not current.faded then
        current.faded = true
        Remotes.Effect:FireAllClients("Fade", 1.2)
    end
    if current.elapsed >= JUMP.FallSeconds + FADE_HOLD then
        -- Hauled back up the line for a run-up, lying on its side, and the crew beside it.
        distance = math.max(0, current.gap.from - JUMP.RunUp)
        free, flight = nil, nil
        tipOver(1, true)
    end
end

local function trackStep(current: Track.Track, dt: number)
    local remaining = target - distance
    local moving = rolling and remaining > 0
    local throttle, lean = crewInput()
    Cart.setThrottle(state, if moving then throttle else 0)
    Cart.setLean(state, if rolling then lean else 0)
    local grade, curvature = Track.shapeAt(current, distance)
    Cart.step(state, stats, dt, {
        moving = moving,
        chewers = chewers,
        chewDps = chewDps,
        grade = grade,
        curvature = curvature,
    })
    roll += (Cart.roll(state, stats, curvature) - roll) * math.min(1, dt * 6)
    if Cart.tipped(state) then
        tipOver(if curvature >= 0 then 1 else -1, false)
        return
    end
    -- Rattling up on two wheels.
    sinceShake += dt
    if state.tilt > 0.35 and sinceShake >= SHAKE_EVERY then
        sinceShake = 0
        Remotes.Effect:FireAllClients("Shake", 0.25 + state.tilt * 0.35)
    end

    -- Ease into the stop: never faster than the brakes could halt in the distance left.
    state.speed = math.min(state.speed, math.sqrt(2 * stats.Accel * 2 * math.max(remaining, 0)) + 0.5)
    local nextDistance = math.min(target, distance + state.speed * dt)
    local gap = Track.nextGap(current, distance)
    if gap and distance <= gap.from and nextDistance >= gap.from and gap.from < target then
        takeOff(gap)
        return
    end
    distance = nextDistance

    if rolling and target - distance <= ARRIVE_WITHIN then
        distance = target
        rolling = false
        state.speed = 0
        arrived:Fire(true)
    end
end

local function replicate(current: Track.Track)
    RunInfo.set("CartHp", math.ceil(state.hp))
    RunInfo.set("CartMaxHp", math.ceil(stats.MaxHp))
    local onTrack = mode == "Track"
    RunInfo.set("Braking", onTrack and Cart.braking(state) and state.speed > 3)
    RunInfo.set("Pushing", onTrack and Cart.pushing(state))
    RunInfo.set("Tilt", if onTrack then math.round(state.tilt * 20) / 20 else 0)
    RunInfo.set("Lean", math.round(state.lean * 10) / 10)
    local _, curvature = Track.shapeAt(current, distance)
    RunInfo.set("LeanSide", if curvature > 0.002 then 1 elseif curvature < -0.002 then -1 else 0)
    RunInfo.set("Derailed", mode == "Derailed")
    RunInfo.set("Airborne", mode == "Flying" or mode == "Falling")
    local wreck = crash
    local pushers = 0
    if wreck then
        for _ in wreck.holders do
            pushers += 1
        end
    end
    RunInfo.set("PushBack", if wreck then math.round(math.min(1, wreck.progress) * 20) / 20 else 0)
    RunInfo.set("Pushers", pushers)

    RunInfo.set("SharpIn", math.floor(CartService.sharpAhead()))
    local sharp = Track.nextSharp(current, distance)
    local sharpCurve = 0
    if sharp then
        local _, middle = Track.shapeAt(current, (sharp.from + sharp.to) / 2)
        sharpCurve = middle
    end
    RunInfo.set("SharpSide", if sharpCurve > 0 then 1 elseif sharpCurve < 0 then -1 else 0)
    local gap = Track.nextGap(current, distance)
    RunInfo.set("GapIn", if gap and onTrack then math.floor(math.max(0, gap.from - distance)) else -1)
    RunInfo.set("GapNeed", if gap then math.ceil(Jump.minSpeed(JUMP, gap)) else 0)
    local speed = if flight then flight.speed elseif onTrack then state.speed else 0
    RunInfo.set("Speed", math.round(speed))
    RunInfo.set("Distance", math.floor(distance)) -- along the track, for the HUD's depth meter
end

RunService.Heartbeat:Connect(function(dt)
    local current = track
    if not current then
        return
    end
    local wreck, jump = crash, flight
    if mode == "Track" then
        trackStep(current, dt)
    elseif jump then
        flyStep(jump, dt)
    elseif wreck then
        derailedStep(wreck, dt)
        -- Crawlers keep chewing a cart that's lying on its side.
        Cart.damage(state, chewers * chewDps * stats.ChewArmor * dt)
    end
    pose()

    if rolling and Cart.wrecked(state) then
        rolling = false
        arrived:Fire(false)
    end

    if locked and mode == "Track" then
        sinceReseat += dt
        if sinceReseat >= RESEAT_EVERY then
            sinceReseat = 0
            reseat()
        end
    end

    sinceReplicate += dt
    if sinceReplicate >= REPLICATE_EVERY then
        sinceReplicate = 0
        replicate(current)
    end
end)

Remotes.Drive.OnServerEvent:Connect(function(player, throttle, lean)
    local drive: Drive = drives[player] or { throttle = 0, lean = 0 }
    if type(throttle) == "number" and throttle == throttle then
        drive.throttle = math.clamp(math.round(throttle), -1, 1)
    end
    if type(lean) == "number" and lean == lean then
        drive.lean = math.clamp(lean, -1, 1)
    end
    drives[player] = drive
end)

Players.PlayerRemoving:Connect(function(player)
    drives[player] = nil
    local wreck = crash
    if wreck then
        wreck.holders[player] = nil
    end
end)

return CartService
