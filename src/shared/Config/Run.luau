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
        SharpDamagePerSecond = 25,
        SharpWarnDistance = 90, -- studs before a sharp curve that the HUD warns the crew
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
        Step = 4, -- studs between sampled track points
        StationLength = 60,
        CartStopOffset = 14, -- studs into a stop's chamber where the cart halts
        RailGauge = 5,
        TunnelRadius = 14,
        SupportEvery = 40, -- studs between timber supports (each carries a lantern)
        ChamberWidth = 64,
        ChamberHeight = 36,
    },
}
