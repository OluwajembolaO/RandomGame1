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
        Speed = 28, -- studs per second
        Accel = 12, -- studs per second per second; brakes bite twice as hard
        BrakeFactor = 0.45, -- speed multiplier while braking
        BrakeSeconds = 6,
        BrakeCooldown = 1.5,
        SafeCurveSpeed = 16, -- faster than this through a sharp curve damages the cart
        SharpDamagePerSecond = 16, -- an unbraked sharp bend costs about 25 HP
        SharpWarnDistance = 90, -- studs before a sharp curve that the HUD warns the crew
        -- Momentum (Rules/Cart.targetSpeed): the tunnels' 6% grade makes the cart run ~20% faster, bends slow it.
        SlopeBoost = 3.2,
        CurveDrag = 12,
        CurveDragMax = 0.3,
        -- Lean (Rules/Cart.bank): degrees per stud/s^2 of sideways pull; a bend at full speed leans ~8 degrees.
        BankPerAccel = 1.1,
        MaxBank = 13,
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
    },
}
