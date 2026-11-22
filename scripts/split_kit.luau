--!strict
-- Splits a Studio "Save to File" of ServerStorage.Content.Kit (or of several chunk models) into one .rbxm
-- per chunk in assets/Content/Kit, the layout Rojo syncs (TRAPS #46). Chunks that already have a file are
-- left alone unless --all is given, so re-saving the whole kit doesn't churn the unchanged ones.
-- Usage from the project root: lune run scripts/split_kit <saved.rbxm> [--all]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local OUT = "assets/Content/Kit"

local input = process.args[1]
assert(input and fs.isFile(input), "usage: lune run scripts/split_kit <saved.rbxm> [--all]")
local all = table.find(process.args, "--all") ~= nil

local roots = roblox.deserializeModel(fs.readFile(input))
local chunks = {}
for _, root in roots do
    if root:IsA("Folder") then
        for _, child in root:GetChildren() do
            table.insert(chunks, child)
        end
    else
        table.insert(chunks, root)
    end
end

local written, skipped = {}, {}
for _, chunk in chunks do
    if chunk:IsA("Model") then
        local path = OUT .. "/" .. chunk.Name .. ".rbxm"
        if all or not fs.isFile(path) then
            fs.writeFile(path, roblox.serializeModel({ chunk }))
            table.insert(written, chunk.Name)
        else
            table.insert(skipped, chunk.Name)
        end
    end
end
table.sort(written)
print(("wrote %d: %s"):format(#written, table.concat(written, ", ")))
print(("kept %d existing"):format(#skipped))
