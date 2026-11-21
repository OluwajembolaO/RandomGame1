--!strict
-- The run's phases and the moves allowed between them. The Director checks every phase change here.
-- Fork votes happen while Riding; Voting is the upgrade vote after a stop.

export type Transitions = { [string]: { string } }

local RunState = {}

RunState.Phases = { "Station", "Riding", "AtStop", "Voting", "Victory", "Wipe" }

RunState.Transitions = {
    Station = { "Riding" },
    Riding = { "AtStop", "Wipe" },
    AtStop = { "Voting", "Riding", "Victory", "Wipe" },
    Voting = { "Riding", "Wipe" },
    Victory = { "Station" },
    Wipe = { "Station" },
} :: Transitions

function RunState.canMove(from: string, to: string, transitions: Transitions?): boolean
    local targets = (transitions or RunState.Transitions)[from]
    return targets ~= nil and table.find(targets, to) ~= nil
end

local function reachable(start: string, transitions: Transitions): { [string]: boolean }
    local seen = { [start] = true }
    local queue = { start }
    while #queue > 0 do
        local phase = table.remove(queue, 1) :: string
        local targets: { string } = transitions[phase] or {}
        for _, nextPhase in targets do
            if not seen[nextPhase] then
                seen[nextPhase] = true
                table.insert(queue, nextPhase)
            end
        end
    end
    return seen
end

-- Every phase has moves to known phases, can be reached from Station, and can get back to Station.
function RunState.validate(phases: { string }, transitions: Transitions): (boolean, string?)
    for _, phase in phases do
        local targets = transitions[phase]
        if not targets or #targets == 0 then
            return false, phase .. " has no way out"
        end
        for _, target in targets do
            if not table.find(phases, target) then
                return false, phase .. " moves to unknown phase " .. target
            end
        end
    end
    local fromStation = reachable("Station", transitions)
    for _, phase in phases do
        if not fromStation[phase] then
            return false, phase .. " can't be reached from Station"
        end
        if not reachable(phase, transitions)["Station"] then
            return false, phase .. " never gets back to Station"
        end
    end
    return true, nil
end

return RunState
