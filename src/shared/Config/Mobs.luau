--!strict
-- Monsters and bosses.

return {
    Crawler = {
        Health = 30,
        Speed = 24,
        LeapRange = 26, -- leaps onto the cart from this close
        ChewDps = 6, -- cart HP per second while it's on the cart
        BiteDamage = 10, -- crew damage when it bites a rider
        BiteCooldown = 1.5,
    },

    Bat = {
        Health = 12,
        Speed = 42,
        SwoopDamage = 8,
        SwoopCooldown = 3,
    },

    Foreman = {
        Health = 1200,
        AttackGap = 3, -- seconds between attacks
        SlamWarnSeconds = 1.5,
        SlamRadius = 14,
        SlamDamage = 35,
        RockfallCount = 5,
        RockfallRadius = 8,
        RockfallDamage = 25,
        SummonBelowFraction = 0.5,
        SummonCount = 3,
        GeneratorHoldSeconds = 1, -- both levers must be held this long before the shield drops
    },
}
