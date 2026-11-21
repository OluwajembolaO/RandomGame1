local T = require("./lib/T")
local RunState = require("../src/shared/Rules/RunState")

T.describe("RunState", function()
    T.it("has a valid phase graph", function()
        local ok, problem = RunState.validate(RunState.Phases, RunState.Transitions)
        T.truthy(ok, problem)
    end)

    T.it("allows the run's moves and blocks shortcuts", function()
        T.truthy(RunState.canMove("Station", "Riding"))
        T.truthy(RunState.canMove("Riding", "AtStop"))
        T.truthy(RunState.canMove("AtStop", "Victory"))
        T.falsy(RunState.canMove("Station", "Victory"), "can't win from the station")
        T.falsy(RunState.canMove("Riding", "Voting"), "upgrade votes happen at stops")
        T.falsy(RunState.canMove("Nowhere", "Riding"))
    end)

    T.it("catches a phase that never returns to the station", function()
        local broken = table.clone(RunState.Transitions)
        broken.Victory = { "Victory" }
        T.falsy((RunState.validate(RunState.Phases, broken)))
    end)

    T.it("catches a move to an unknown phase", function()
        local broken = table.clone(RunState.Transitions)
        broken.Riding = { "AtStop", "Lost" }
        T.falsy((RunState.validate(RunState.Phases, broken)))
    end)

    T.it("catches an unreachable phase", function()
        local broken = table.clone(RunState.Transitions)
        broken.AtStop = { "Riding", "Victory", "Wipe" }
        T.falsy((RunState.validate(RunState.Phases, broken)), "nothing leads to Voting")
    end)
end)
