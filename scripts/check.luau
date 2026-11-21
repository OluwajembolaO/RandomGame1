--!strict
-- Runs the four required checks (rojo build, Lune tests, Selene, StyLua) plus a Luau type check. Usage from the project root: `lune run scripts/check`
-- Every check must pass before anything is synced into Studio.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

-- Prefer Rokit's shims so the versions pinned in rokit.toml are used even if another
-- copy of a tool comes first on PATH (see TRAPS.md).
local home = process.env.USERPROFILE or process.env.HOME or ""
local function tool(name: string): string
    for _, candidate in { home .. "/.rokit/bin/" .. name .. ".exe", home .. "/.rokit/bin/" .. name } do
        if fs.isFile(candidate) then
            return candidate
        end
    end
    return name
end

type Check = {
    name: string,
    program: string,
    args: { string },
    -- Optional extra verdict on the captured output, for tools whose exit code is too lenient.
    verdict: ((output: string) -> string?)?,
}

local function seleneVerdict(output: string): string?
    local warnings = tonumber(string.match(output, "(%d+) warnings?")) or 0
    if warnings > 0 then
        return warnings .. " selene warning(s); warnings count as failures"
    end
    return nil
end

if not fs.isDir("build") then
    fs.writeDir("build")
end

-- Roblox API type definitions for the type check, downloaded once (build/ is gitignored).
local DEFINITIONS = "build/globalTypes.d.luau"
local DEFINITIONS_URL = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
if not fs.isFile(DEFINITIONS) then
    print("downloading Roblox type definitions...")
    local response = net.request(DEFINITIONS_URL)
    if response.ok then
        fs.writeFile(DEFINITIONS, response.body)
    else
        print("  could not download definitions (" .. response.statusCode .. "); the type check will fail")
    end
end

-- luau-lsp exits 0 on warnings-only runs too; any reported error line counts as a failure.
local function typesVerdict(output: string): string?
    local count = 0
    for _ in string.gmatch(output, "TypeError") do
        count += 1
    end
    for _ in string.gmatch(output, "SyntaxError") do
        count += 1
    end
    return if count > 0 then count .. " type error report(s)" else nil
end

local checks: { Check } = {
    {
        name = "rojo build",
        program = tool("rojo"),
        args = { "build", "default.project.json", "--output", "build/check.rbxl" },
    },
    { name = "lune tests", program = tool("lune"), args = { "run", "tests/run" } },
    {
        name = "selene",
        program = tool("selene"),
        args = { "src", "tests", "scripts" },
        verdict = seleneVerdict,
    },
    { name = "stylua", program = tool("stylua"), args = { "--check", "src", "tests", "scripts" } },
    -- Bonus check beyond the four: types against the Roblox API (catches misspelled properties).
    -- The sourcemap is regenerated first so a stale one can't hide or invent errors (TRAPS.md #5).
    {
        name = "sourcemap (for types)",
        program = tool("rojo"),
        args = { "sourcemap", "default.project.json", "--output", "sourcemap.json" },
    },
    {
        name = "luau types",
        program = tool("luau-lsp"),
        args = {
            "analyze",
            "--platform=roblox",
            "--sourcemap=sourcemap.json",
            "--definitions=" .. DEFINITIONS,
            "--ignore=Packages/**",
            "--ignore=**/_Index/**",
            "src",
        },
        verdict = typesVerdict,
    },
}

local failed = {}
for index, check in checks do
    print(string.format("\n[%d/%d] %s", index, #checks, check.name))
    local result = process.exec(check.program, check.args)
    local output = result.stdout .. result.stderr
    if output ~= "" then
        print((string.gsub(output, "%s+$", "")))
    end
    local problem = if result.ok then nil else "exit code " .. result.code
    if not problem and check.verdict then
        problem = check.verdict(output)
    end
    if problem then
        print("  -> FAILED (" .. problem .. ")")
        table.insert(failed, check.name)
    else
        print("  -> ok")
    end
end

print("")
if #failed > 0 then
    print("CHECKS FAILED: " .. table.concat(failed, ", "))
    process.exit(1)
end
print("ALL CHECKS PASSED")
