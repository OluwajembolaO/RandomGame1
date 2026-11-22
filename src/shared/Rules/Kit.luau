--!strict
-- The cave kit: Blender-made chunks (Config/KitData, from art/blender/build_cave_kit.py) snapped end to end.
-- A run is a set number of segments, one chunk each, rolled like DOORS rooms: each next segment is drawn by
-- weight from the zone's chunk pool, out of the chunks that fit there:
--   * it keeps the track within MaxHeading of the zone's heading (so the route can't cross itself),
--   * each Tag (Cavern, Sharp, Gap, Split...) keeps its Spacing: never sooner than Spacing[1] segments after
--     the last one, and forced once Spacing[2] have gone by,
--   * After / NotAfter / NoRepeat rules (a jump needs a straight run-up, no sharp bend straight after a
--     landing, never the same cavern twice running),
--   * the first and last EdgeTunnels segments of a leg are plain tunnels (no caverns, jumps or splits),
--   * every leg gets at least one of each of its EveryLeg tags.
-- Each leg has a difficulty (Easy, Medium, Hard): it scales each chunk's weight by its Tier (1 easy .. 3
-- hard), and can tighten the spacing and add EveryLeg tags, so later legs are harder.
-- Every chunk is modeled around the exact track Track.build makes from it.

local Rng = require("./Rng")
local Track = require("./Track")

-- A KitData piece. Kind is "Station", "Stop", "Tunnel", "Cavern" or "Cap" (TRAPS #19). Broken-track pieces
-- have a Gap: its ends in horizontal studs into the piece, and how much lower the far side sits (that drop
-- is part of the piece's Drop). Junctions have a Split (Rules/Split), the same way.
export type GapDef = { From: number, To: number, Drop: number }
export type SplitDef = { From: number, To: number, Buffer: number, Offset: number, Ramp: number }
export type PieceDef = {
    Kind: string,
    Length: number,
    Turn: number,
    Drop: number,
    Sharp: boolean,
    Gap: GapDef?,
    Split: SplitDef?,
}
export type Pieces = { [string]: PieceDef }

-- One entry in a zone's chunk pool. Tier: 1 easy, 2 medium, 3 hard (1 if left out).
export type Chunk = { Id: string, Weight: number, Tier: number?, Tag: string?, After: { string }? }
-- How a tag's chunks are spread out. NotAfter: never straight after a chunk with one of these tags.
export type TagRule = { Spacing: { number }, NoRepeat: boolean?, NotAfter: { string }? }
-- A leg difficulty: weight multipliers by tier, tighter spacings, and more tags every leg must have.
export type Difficulty = { Tiers: { number }, Spacing: { [string]: { number } }?, EveryLeg: { string }? }

-- A zone's Kit config.
export type Spec = {
    Station: string,
    Stop: string,
    Cap: string,
    Straight: string, -- the plain tunnel: run-ups, and the fallback when nothing else fits
    Chunks: { Chunk },
    Tags: { [string]: TagRule },
    EveryLeg: { string }, -- tags every leg has at least one of (unless its difficulty says otherwise)
    Difficulty: { [string]: Difficulty }?,
    EdgeTunnels: number,
    MaxHeading: number,
}

local Kit = {}

-- The track piece a kit piece is modeled around. `open` is a split's open lane (-1, 0 or 1).
function Kit.trackPiece(def: PieceDef, open: number?): Track.Piece
    local gap = def.Gap
    local split = def.Split
    local gapDrop = if gap then gap.Drop else 0
    return {
        kind = if def.Turn == 0 then "Straight" else "Curve",
        length = def.Length,
        turn = def.Turn,
        grade = if def.Length > 0 then (def.Drop - gapDrop) / def.Length else 0,
        sharp = def.Sharp,
        gap = if gap then { from = gap.From, to = gap.To, drop = gap.Drop } else nil,
        split = if split
            then {
                from = split.From,
                to = split.To,
                buffer = split.Buffer,
                offset = split.Offset,
                ramp = split.Ramp,
                open = open or 0,
            }
            else nil,
    }
end

-- The pool entry for a chunk id (nil if it isn't in the pool).
function Kit.chunk(spec: Spec, id: string): Chunk?
    for _, chunk in spec.Chunks do
        if chunk.Id == id then
            return chunk
        end
    end
    return nil
end

local function tagOf(spec: Spec, id: string?): string?
    local chunk = if id then Kit.chunk(spec, id) else nil
    return if chunk then chunk.Tag else nil
end

-- Plain tunnels only at the ends of a leg: no caverns, nothing to jump, no splits.
local function plainTunnel(def: PieceDef): boolean
    return def.Kind == "Tunnel" and def.Gap == nil and def.Split == nil
end

local function contains(list: { string }?, value: string?): boolean
    return list ~= nil and value ~= nil and table.find(list, value) ~= nil
end

-- The pool and rules for one difficulty: each chunk's weight scaled by its tier (chunks scaled to nothing
-- are left out), each tag's spacing (tightened by the difficulty), the leg's required tags, and for each of
-- those whether it needs the middle of a leg and a run-up before it.
type View = {
    chunks: { Chunk },
    weights: { [string]: number },
    spacing: { [string]: { number } },
    everyLeg: { string },
    middle: { [string]: boolean },
    runUp: { [string]: boolean },
}

local function view(spec: Spec, pieces: Pieces, difficultyName: string?): View
    local difficulty = if difficultyName and spec.Difficulty then spec.Difficulty[difficultyName] else nil
    local chunks, weights = {}, {}
    for _, chunk in spec.Chunks do
        local scale = if difficulty then difficulty.Tiers[chunk.Tier or 1] or 0 else 1
        if chunk.Weight * scale > 0 then
            table.insert(chunks, chunk)
            weights[chunk.Id] = chunk.Weight * scale
        end
    end
    local spacing = {}
    for tag, rule in spec.Tags do
        local override = if difficulty and difficulty.Spacing then difficulty.Spacing[tag] else nil
        spacing[tag] = override or rule.Spacing
    end
    local everyLeg: { string } = spec.EveryLeg
    if difficulty and difficulty.EveryLeg then
        everyLeg = difficulty.EveryLeg
    end
    local middle, runUp = {}, {}
    for _, tag in everyLeg do
        local allMiddle, allRunUp, any = true, true, false
        for _, chunk in chunks do
            if chunk.Tag == tag and pieces[chunk.Id] then
                any = true
                allMiddle = allMiddle and not plainTunnel(pieces[chunk.Id])
                allRunUp = allRunUp and chunk.After ~= nil
            end
        end
        middle[tag] = any and allMiddle
        runUp[tag] = any and allRunUp
    end
    return {
        chunks = chunks,
        weights = weights,
        spacing = spacing,
        everyLeg = everyLeg,
        middle = middle,
        runUp = runUp,
    }
end

-- What the roll needs to know about the leg so far.
type State = {
    heading: number,
    previous: string?,
    since: { [string]: number }, -- segments since each tag last turned up
    lastOf: { [string]: string }, -- the last chunk of each tag
    seen: { [string]: boolean }, -- tags seen this leg
}

-- Whether chunk `chunk` can go in this segment.
local function allowed(
    chunk: Chunk,
    pieces: Pieces,
    spec: Spec,
    rules: View,
    state: State,
    edge: boolean,
    base: number
): boolean
    local def = pieces[chunk.Id]
    if not def or (def.Kind ~= "Tunnel" and def.Kind ~= "Cavern") then
        return false
    end
    if edge and not plainTunnel(def) then
        return false
    end
    if math.abs(state.heading + def.Turn - base) > spec.MaxHeading + 1e-9 then
        return false
    end
    if chunk.After and not contains(chunk.After, state.previous) then
        return false
    end
    local tag = chunk.Tag
    local rule = if tag then spec.Tags[tag] else nil
    if tag and rule then
        if (state.since[tag] or math.huge) < rules.spacing[tag][1] then
            return false
        end
        if rule.NoRepeat and state.lastOf[tag] == chunk.Id then
            return false
        end
        if contains(rule.NotAfter, tagOf(spec, state.previous)) then
            return false
        end
    end
    return true
end

local function weighted(rng: Rng.Rng, chunks: { Chunk }, weights: { [string]: number }): Chunk
    local total = 0
    for _, chunk in chunks do
        total += weights[chunk.Id]
    end
    local roll = Rng.float(rng) * total
    for _, chunk in chunks do
        roll -= weights[chunk.Id]
        if roll < 0 then
            return chunk
        end
    end
    return chunks[#chunks]
end

local function withTag(chunks: { Chunk }, tag: string): { Chunk }
    local list = {}
    for _, chunk in chunks do
        if chunk.Tag == tag then
            table.insert(list, chunk)
        end
    end
    return list
end

-- The tag this segment must be, if any: a required tag about to run out of room in the leg (counting the
-- room the other missing ones need, and a slot for a run-up), else the tag most overdue by its spacing.
local function forcedTag(spec: Spec, rules: View, state: State, index: number, count: number): string?
    local nonEdgeLeft = math.max(0, (count - spec.EdgeTunnels) - math.max(index, spec.EdgeTunnels + 1) + 1)
    local slotsLeft = count - index + 1
    local needMiddle, needAny = 0, 0
    local firstMiddle: string?, firstAny: string? = nil, nil
    for _, tag in rules.everyLeg do
        if not state.seen[tag] then
            if rules.middle[tag] then
                needMiddle += if rules.runUp[tag] then 2 else 1
                firstMiddle = firstMiddle or tag
            else
                needAny += 1
                firstAny = firstAny or tag
            end
        end
    end
    if firstMiddle and nonEdgeLeft > 0 and nonEdgeLeft <= needMiddle then
        return firstMiddle
    end
    if firstAny and slotsLeft <= needAny + 1 then
        return firstAny
    end
    local due, most = nil, -math.huge
    for tag in spec.Tags do
        local over = (state.since[tag] or 0) - rules.spacing[tag][2]
        if over >= 0 and over > most then
            due, most = tag, over
        end
    end
    return due
end

-- The chunks for one ride leg of `count` segments at `difficulty`, starting at `heading` (the zone heading
-- is `base`).
function Kit.leg(
    rng: Rng.Rng,
    pieces: Pieces,
    spec: Spec,
    count: number,
    heading: number,
    base: number,
    difficulty: string?
): { string }
    local rules = view(spec, pieces, difficulty)
    local state: State = { heading = heading, previous = nil, since = {}, lastOf = {}, seen = {} }
    for tag in spec.Tags do
        state.since[tag] = rules.spacing[tag][1]
    end
    local sequence: { string } = {}
    for index = 1, count do
        local edge = index <= spec.EdgeTunnels or index > count - spec.EdgeTunnels
        local candidates = {}
        for _, chunk in rules.chunks do
            if allowed(chunk, pieces, spec, rules, state, edge, base) then
                table.insert(candidates, chunk)
            end
        end
        local forced = forcedTag(spec, rules, state, index, count)
        if forced then
            local tagged = withTag(candidates, forced)
            if #tagged > 0 then
                candidates = tagged
            else
                -- Not possible here yet: lay a run-up for a chunk that needs one (a jump after a straight).
                for _, chunk in withTag(rules.chunks, forced) do
                    local after = chunk.After
                    if after and not edge then
                        local runUp = Kit.chunk(spec, after[1])
                        if runUp and allowed(runUp, pieces, spec, rules, state, edge, base) then
                            candidates = { runUp }
                            break
                        end
                    end
                end
            end
        end
        local weights = rules.weights
        if #candidates == 1 and not weights[candidates[1].Id] then
            weights = table.clone(weights)
            weights[candidates[1].Id] = 1
        end
        local id = if #candidates > 0 then weighted(rng, candidates, weights).Id else spec.Straight
        table.insert(sequence, id)

        local tag = tagOf(spec, id)
        for name in spec.Tags do
            state.since[name] = (state.since[name] or 0) + 1
        end
        if tag then
            state.since[tag] = 0
            state.lastOf[tag] = id
            state.seen[tag] = true
        end
        state.heading += pieces[id].Turn
        state.previous = id
    end
    return sequence
end

-- A leg is rideable when every chunk exists, can ride, and belongs at `difficulty`; the heading never
-- leaves base +/- MaxHeading; the ends are plain tunnels; every chunk keeps its pool rules; and each of the
-- leg's EveryLeg tags turns up.
function Kit.check(
    sequence: { string },
    pieces: Pieces,
    spec: Spec,
    heading: number,
    base: number,
    difficulty: string?
): (boolean, string?)
    if #sequence == 0 then
        return false, "leg has no chunks"
    end
    local rules = view(spec, pieces, difficulty)
    local since: { [string]: number } = {}
    local seen: { [string]: boolean } = {}
    for tag in spec.Tags do
        since[tag] = rules.spacing[tag][1]
    end
    for index, id in sequence do
        local def = pieces[id]
        if not def then
            return false, "unknown chunk " .. id
        end
        -- Plain booleans: comparing Kind repeatedly trips the old type solver's narrowing.
        local isTunnel = def.Kind == "Tunnel"
        local isCavern = def.Kind == "Cavern"
        if not isTunnel and not isCavern then
            return false, id .. " (" .. def.Kind .. ") can't be part of a leg"
        end
        if difficulty and id ~= spec.Straight and not rules.weights[id] then
            return false, id .. " doesn't belong on a " .. difficulty .. " leg"
        end
        heading += def.Turn
        if math.abs(heading - base) > spec.MaxHeading + 1e-9 then
            return false, "heading leaves the limit at segment " .. index
        end
        local edge = index <= spec.EdgeTunnels or index > #sequence - spec.EdgeTunnels
        if edge and not plainTunnel(def) then
            return false, "segment " .. index .. " (" .. id .. ") is too close to the end of the leg"
        end
        local previous = sequence[index - 1]
        local chunk = Kit.chunk(spec, id)
        if chunk and chunk.After and not contains(chunk.After, previous) then
            return false, id .. " at segment " .. index .. " has no " .. chunk.After[1] .. " before it"
        end
        local tag = chunk and chunk.Tag
        local rule = if tag then spec.Tags[tag] else nil
        if tag and rule then
            if since[tag] < rules.spacing[tag][1] then
                return false, tag .. " chunks too close together at segment " .. index
            end
            if contains(rule.NotAfter, tagOf(spec, previous)) then
                return false,
                    tag .. " chunk straight after a " .. tostring(tagOf(spec, previous)) .. " at segment " .. index
            end
        end
        for name in spec.Tags do
            since[name] += 1
        end
        if tag then
            since[tag] = 0
            seen[tag] = true
        end
    end
    for _, tag in rules.everyLeg do
        if not seen[tag] then
            return false, "leg has no " .. tag
        end
    end
    return true, nil
end

return Kit
