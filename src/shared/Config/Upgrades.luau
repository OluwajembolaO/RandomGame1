-- Upgrades the crew votes on after a stop. They stack for the rest of the run.
-- Each effect changes one stat from Rules/Upgrades.baseStats: Add first, then Mult (once per stack).
-- Not --!strict: effects have either Add or Mult (TRAPS #21). Upgrades.validate checks the data.

return {
    {
        Id = "SpikedBumpers",
        Name = "Spiked Bumpers",
        Description = "Crawlers on the cart take 6 damage a second.",
        Max = 3,
        Effects = { { Stat = "SpikeDps", Add = 6 } },
    },
    {
        Id = "ReinforcedFrame",
        Name = "Reinforced Frame",
        Description = "+60 cart max HP.",
        Max = 3,
        Effects = { { Stat = "CartMaxHp", Add = 60 } },
    },
    {
        Id = "RapidRivets",
        Name = "Rapid Rivets",
        Description = "The Rivet Gun fires 20% faster.",
        Max = 3,
        Effects = { { Stat = "RivetCooldown", Mult = 0.8 } },
    },
    {
        Id = "HeavyRivets",
        Name = "Heavy Rivets",
        Description = "+4 rivet damage.",
        Max = 3,
        Effects = { { Stat = "RivetDamage", Add = 4 } },
    },
    {
        Id = "BigHeadlamp",
        Name = "Big Headlamp",
        Description = "The cart's headlamp reaches 50% further.",
        Max = 2,
        Effects = { { Stat = "HeadlampRange", Mult = 1.5 } },
    },
    {
        Id = "SecondWind",
        Name = "Second Wind",
        Description = "Revives take 40% less time.",
        Max = 2,
        Effects = { { Stat = "ReviveSeconds", Mult = 0.6 } },
    },
    {
        Id = "WideAxles",
        Name = "Wide Axles",
        Description = "The cart takes bends 20% harder before it tips over.",
        Max = 2,
        Effects = { { Stat = "TipLimit", Mult = 1.2 } },
    },
    {
        Id = "Crowbars",
        Name = "Crowbars",
        Description = "Pushing a tipped cart back onto the rails is 40% faster.",
        Max = 2,
        Effects = { { Stat = "RightSeconds", Mult = 0.6 } },
    },
    {
        Id = "ChewGuard",
        Name = "Chew Guard",
        Description = "Crawlers chew the cart 30% slower.",
        Max = 2,
        Effects = { { Stat = "ChewArmor", Mult = 0.7 } },
    },
}
