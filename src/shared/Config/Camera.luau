--!strict
-- How the first-person camera feels (client/FirstPerson), on foot and riding the cart. Angles are in
-- degrees; rates are "how quickly it catches up": higher is snappier, about 1/rate seconds to get most of
-- the way there.

return {
    -- Mouse / stick look speed, on foot and seated in the cart (1 = Roblox's speed at the player's own
    -- sensitivity setting).
    Sensitivity = 0.5,
    RideSensitivity = 0.45,
    -- Smooths mouse look so the view glides instead of snapping.
    LookRate = 20,
    -- The view turns with the cart through bends; this eases out the cart's small wobbles.
    FollowRate = 6,

    -- How much of the cart's lean the view rolls with, and how quickly.
    LeanFollow = 0.45,
    LeanRate = 4,
    -- Nodding forward under braking and back when picking up speed: degrees per stud/s^2, capped.
    NodPerAccel = 0.07,
    NodDown = 1.5,
    NodUp = 1,
    NodRate = 3,

    -- A soft up-and-down bob at speed, in studs.
    Bob = 0.035,
    BobSpeed = 6,

    -- Field of view, widening at speed.
    Fov = 70,
    FovAtSpeed = 12,
    TopSpeed = 55,

    -- The knock from scraping a sharp bend too fast: degrees at full strength, and how fast it fades.
    Shake = 0.8,
    ShakeFade = 2.5,
}
