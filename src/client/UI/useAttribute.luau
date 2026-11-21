--!strict
-- React hook: the current value of an attribute on an instance, re-rendering when it changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local function read(instance: Instance, key: string, default: any): any
    local value = instance:GetAttribute(key)
    if value == nil then
        return default
    end
    return value
end

local function useAttribute(instance: Instance, key: string, default: any): any
    local value, setValue = React.useState(read(instance, key, default))
    React.useEffect(function()
        setValue(read(instance, key, default))
        local connection = instance:GetAttributeChangedSignal(key):Connect(function()
            setValue(read(instance, key, default))
        end)
        return function()
            connection:Disconnect()
        end
    end, { instance, key } :: { any })
    return value
end

return useAttribute
