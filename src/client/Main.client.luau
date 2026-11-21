--!strict
-- Client entry point: starts input and effects, then mounts the React UI into a ScreenGui under
-- PlayerGui (not the Player; TRAPS #8).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local App = require(script.Parent.UI.App)
local Controls = require(script.Parent.Controls)
local Fx = require(script.Parent.Fx)
local Weapons = require(script.Parent.Weapons)

Fx.start()
Controls.start()
Weapons.start()

local screen = Instance.new("ScreenGui")
screen.Name = "App"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local root = ReactRoblox.createRoot(screen)
root:render(React.createElement(App))
