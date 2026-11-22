--!strict
-- The run's route through a zone: ride legs, each ending in a stop. A stop is either a fixed stage or a
-- fork whose branches the crew votes on. Rolled from a seed, so a run can be replayed.

local Rng = require("./Rng")

export type Stop = {
    -- Exactly one of these is set.
    stage: string?,
    options: { string }?,
}

export type Leg = {
    index: number,
    segments: number, -- how many cave segments (one kit chunk each) the ride is
    ambushes: number,
    stop: Stop,
}

export type Route = { zone: string, seed: number, legs: { Leg } }

-- Fields read from Config/Zones and Config/Stages.
type LegSpec = {
    Ride: { Segments: number, Ambushes: { number } },
    Stop: { Stage: string?, Fork: { string }?, Options: number? },
}
type ZoneSpec = { Id: string, Legs: { LegSpec } }
type StageSpec = { Kind: string }

local Route = {}

function Route.generate(zone: ZoneSpec, seed: number): Route
    local rng = Rng.new(seed)
    local legs: { Leg } = {}
    for index, spec in zone.Legs do
        local stop: Stop
        local fork = spec.Stop.Fork
        if fork then
            local count = math.min(spec.Stop.Options or 2, #fork)
            local shuffled = Rng.shuffle(rng, fork)
            stop = { options = table.move(shuffled, 1, count, 1, {}) }
        else
            stop = { stage = spec.Stop.Stage }
        end
        table.insert(legs, {
            index = index,
            segments = spec.Ride.Segments,
            ambushes = Rng.int(rng, spec.Ride.Ambushes[1], spec.Ride.Ambushes[2]),
            stop = stop,
        })
    end
    return { zone = zone.Id, seed = seed, legs = legs }
end

-- Every stage a stop could lead to.
function Route.stagesOf(stop: Stop): { string }
    if stop.options then
        return stop.options
    end
    return if stop.stage then { stop.stage } else {}
end

-- A route is playable when every stage exists, forks offer at least two different non-boss branches,
-- and the last stop (and only the last) is a boss.
function Route.validate(route: Route, stages: { [string]: StageSpec }): (boolean, string?)
    if #route.legs == 0 then
        return false, "route has no legs"
    end
    for index, leg in route.legs do
        local where = "leg " .. index
        if leg.segments <= 0 then
            return false, where .. " has no ride"
        end
        if leg.ambushes < 0 then
            return false, where .. " has negative ambushes"
        end
        local stop = leg.stop
        if (stop.stage == nil) == (stop.options == nil) then
            return false, where .. " must have exactly one of stage or options"
        end
        local isLast = index == #route.legs
        if stop.options then
            if #stop.options < 2 then
                return false, where .. " fork offers fewer than two branches"
            end
            local seen = {}
            for _, id in stop.options do
                if seen[id] then
                    return false, where .. " fork offers " .. id .. " twice"
                end
                seen[id] = true
                local stage = stages[id]
                if not stage then
                    return false, where .. " fork offers unknown stage " .. id
                end
                if stage.Kind == "Boss" then
                    return false, where .. " fork offers a boss"
                end
            end
            if isLast then
                return false, "the last stop is a fork, not a boss"
            end
        else
            local id = stop.stage :: string
            local stage = stages[id]
            if not stage then
                return false, where .. " has unknown stage " .. id
            end
            if isLast and stage.Kind ~= "Boss" then
                return false, "the last stop (" .. id .. ") is not a boss"
            end
            if not isLast and stage.Kind == "Boss" then
                return false, where .. " has a boss before the end"
            end
        end
    end
    return true, nil
end

return Route
