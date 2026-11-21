--!strict
-- Tiny test helper for Lune. Specs call T.describe/T.it; run.luau prints the summary.

local T = {}

local suite = ""
local passed = 0
local failures: { string } = {}

local function show(value: any): string
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

function T.describe(name: string, body: () -> ())
    local previous = suite
    suite = if previous == "" then name else previous .. " > " .. name
    body()
    suite = previous
end

function T.it(name: string, body: () -> ())
    local ok, err = pcall(body)
    if ok then
        passed += 1
    else
        table.insert(failures, suite .. " > " .. name .. "\n      " .. tostring(err))
    end
end

function T.equal(actual: any, expected: any, label: string?)
    if actual ~= expected then
        error(
            string.format("%sexpected %s, got %s", if label then label .. ": " else "", show(expected), show(actual)),
            2
        )
    end
end

function T.near(actual: number, expected: number, tolerance: number?, label: string?)
    local eps = tolerance or 1e-6
    if math.abs(actual - expected) > eps then
        error(
            string.format("%sexpected %s (+/- %s), got %s", if label then label .. ": " else "", expected, eps, actual),
            2
        )
    end
end

function T.truthy(value: any, label: string?)
    if not value then
        error((label or "expected a truthy value") .. ", got " .. show(value), 2)
    end
end

function T.falsy(value: any, label: string?)
    if value then
        error((label or "expected a falsy value") .. ", got " .. show(value), 2)
    end
end

function T.fail(message: string)
    error(message, 2)
end

function T.summary(): (number, { string })
    return passed, failures
end

return T
