--!strict
-- Every config module in one table. Works the same in Roblox and Lune.
-- Entries are typed `any`: each Rules module declares the fields it reads, and tests check the data (TRAPS #21).

return table.freeze({
    Assets = require("./Config/Assets") :: any,
    Camera = require("./Config/Camera") :: any,
    Kit = require("./Config/KitData") :: any,
    Mobs = require("./Config/Mobs") :: any,
    Run = require("./Config/Run") :: any,
    Stages = require("./Config/Stages") :: any,
    Upgrades = require("./Config/Upgrades") :: any,
    Weapons = require("./Config/Weapons") :: any,
    Zones = require("./Config/Zones") :: any,
})
