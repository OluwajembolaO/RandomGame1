--!strict
-- Collision groups. The cart never touches the cave (it's pulled along the track, not driven on it),
-- crew members don't block each other, and monsters ignore the cart (Crawlers weld onto it instead).

local PhysicsService = game:GetService("PhysicsService")

local Groups = {
    Cart = "Cart",
    Crew = "Crew",
    Mobs = "Mobs",
}

for _, name in { Groups.Cart, Groups.Crew, Groups.Mobs } do
    if not PhysicsService:IsCollisionGroupRegistered(name) then
        PhysicsService:RegisterCollisionGroup(name)
    end
end
PhysicsService:CollisionGroupSetCollidable(Groups.Cart, "Default", false)
PhysicsService:CollisionGroupSetCollidable(Groups.Cart, Groups.Mobs, false)
PhysicsService:CollisionGroupSetCollidable(Groups.Crew, Groups.Crew, false)

-- Puts every part under `root` (and any added later) into a group.
function Groups.assign(root: Instance, group: string): RBXScriptConnection
    local function apply(instance: Instance)
        if instance:IsA("BasePart") then
            instance.CollisionGroup = group
        end
    end
    apply(root)
    for _, descendant in root:GetDescendants() do
        apply(descendant)
    end
    return root.DescendantAdded:Connect(apply)
end

return Groups
