--!strict
-- Runs every tests/*.spec.luau file with Lune: `lune run tests/run`.

local fs = require("@lune/fs")
local process = require("@lune/process")

local T = require("./lib/T")

local specs = {}
for _, name in fs.readDir("tests") do
    local stem = string.match(name, "^(.+)%.spec%.luau$")
    if stem then
        table.insert(specs, stem)
    end
end
table.sort(specs)

for _, stem in specs do
    print("spec: " .. stem)
    require("./" .. stem .. ".spec")
end

local passed, failures = T.summary()
for _, failure in failures do
    print("  FAIL " .. failure)
end
print(string.format("%d passed, %d failed (%d spec files)", passed, #failures, #specs))

if #failures > 0 then
    process.exit(1)
end
