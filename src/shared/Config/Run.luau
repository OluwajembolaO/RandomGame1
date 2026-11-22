--!strict
-- Run-wide numbers: the station, the cart and the crew.

return {
    -- 0 rolls a new route every run; any other number replays the same route.
    Seed = 0,

    -- The station sits high up so the whole descent stays above Workspace.FallenPartsDestroyHeight (-500).
    StationHeight = 1200,
    MaxCrew = 4,
    StartCountdown = 8, -- seconds after the lever is pulled
    AllAboardSeconds = 12, -- after a stop, seconds before everyone is pulled into the cart
    EndScreenSeconds = 10,

    Cart = {
        MaxHp = 200,
        Speed = 40, -- studs per second on the flat; ~48 down the tunnels' grade
        Accel = 17, -- studs per second per second; brakes bite twice as hard
        -- The crew holds the brake (S) or pushes (W); anyone braking wins.
        BrakeFactor = 0.45, -- speed multiplier while braking
        PushFactor = 1.35, -- pushing runs about 54 studs/s on the flat, 65 down a tunnel
        SharpWarnDistance = 150, -- studs before a sharp curve that the HUD warns the crew

        -- Tipping over (Rules/Cart): sideways pull is speed^2 x curvature. Past TipLimit the cart lifts onto
        -- its outer wheels and the tilt fills (TipRate per unit over the limit, per second); full tilt tips it.
        -- A normal bend at cruise pulls ~15, a sharp one ~22 (more coming in fast), pushing through a normal
        -- bend ~28. Everyone leaning in takes 80% more: even a pushed bend, if the whole crew commits.
        TipLimit = 18.5,
        LeanBonus = 0.8, -- the whole crew leaning into the bend takes 80% more pull
        LeanPenalty = 0.3, -- leaning out of it takes 30% less
        -- Per second, so they scale with speed: the faster the cart, the less time it spends in each bend.
        TipRate = 4.3,
        TipRecover = 2.1,
        LeanTilt = 14, -- degrees the cart tilts toward the side the crew leans
        LiftMax = 28, -- degrees it lifts onto its outer wheels just before going over
        -- How the cart body rocks toward that roll, like a heavy box on its wheels (Rules/Cart.rock): it swings
        -- RockFrequency times a second and RockDamping (0..1) takes the swing out. Lower damping rocks more:
        -- at 0.35, letting go of a 14 degree lean swings it about 4 degrees past upright, then 1 back, settled
        -- in about 1.5 s.
        RockFrequency = 1.3,
        RockDamping = 0.35,
        -- Pushing a tipped cart back onto the rails: one player takes RightSeconds, each helper adds 60%.
        RightSeconds = 6,
        HelperBoost = 0.6,
        CrashWalkway = 40, -- studs of invisible walkway either side of a crash, so nobody falls off a trestle

        -- Jumping gaps in broken track (Rules/Jump): the cart leaves a broken lip at Lip degrees and flies
        -- under Gravity (studs/s^2, floatier than Roblox's) onto the lower far side, with Clearance studs to
        -- spare. Too slow and it falls in: the crew finds it tipped over RunUp studs before the gap.
        -- Gravity scales with speed squared, so the same gaps ask the same of the crew at any cart speed.
        Jump = {
            Gravity = 80,
            Lip = 12,
            Clearance = 1.5,
            RunUp = 140,
            FallSeconds = 1.2,
            WarnDistance = 240,
            -- The landing bounce (Rules/Jump.landingKick), scaled by how hard the cart comes down: the first
            -- hop keeps Restitution of the landing speed, the nose slams down at PitchKick radians a second
            -- per stud a second (then rocks back like the lean, Rules/Cart.rock), and a random sideways jolt
            -- of up to RollKick.
            Restitution = 0.35,
            PitchKick = 0.03,
            RollKick = 0.012,
        },
        -- Momentum (Rules/Cart.targetSpeed): the tunnels' 6% grade makes the cart run ~20% faster, bends slow it.
        SlopeBoost = 3.2,
        CurveDrag = 12,
        CurveDragMax = 0.3,
        -- Lean (Rules/Cart.bank): degrees per stud/s^2 of sideways pull; a bend at full speed leans ~10 degrees.
        BankPerAccel = 0.6,
        MaxBank = 18,
        RepairPerSecond = 8,
        HeadlampRange = 60,
        Seats = 4,
    },

    Crew = {
        MaxHealth = 100,
        BleedOutSeconds = 30,
        ReviveSeconds = 3,
        ReviveHealthFraction = 0.3,
    },

    Track = {
        Step = 4, -- studs between sampled track points (the kit is modeled on the same steps)
        CartStopOffset = 14, -- studs into a stop's chamber where the cart halts
        RailGauge = 5,
        -- Walkable floors in the kit's station and stop chamber (art/blender/build_cave_kit.py): the floor's top
        -- sits FloorTop studs from the rails, Width wide, shifted Offset studs to the right of the track.
        FloorTop = -1.2,
        Floors = {
            Station = { Width = 84, Offset = 10 },
            Stop = { Width = 100, Offset = 8 },
        },
        -- The kit's rock doesn't collide (the cart rides its rails through it), so every chunk also gets an
        -- invisible floor along the track at FloorTop, this wide: the tunnel floor, a walkway along a cavern's
        -- trestle, all three lanes of a junction. Gaps stay open.
        TrackFloor = { Tunnel = 26, Cavern = 14, Split = 40, Station = 26, Stop = 26, Cap = 26 },
        -- Anyone who still ends up this far below the cart is put back beside it (server/Rescue).
        RescueDrop = 35,
    },
}
