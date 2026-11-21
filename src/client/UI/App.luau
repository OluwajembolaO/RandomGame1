--!strict
-- The root of the React UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Hud = require(script.Parent.Hud)

local function App()
    return React.createElement(Hud)
end

return App
