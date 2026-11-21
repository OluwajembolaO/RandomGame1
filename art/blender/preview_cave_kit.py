"""Chains cave kit pieces into a sample route and renders it, to judge the kit before exporting.

Run build_cave_kit.py first. This makes a separate scene (KitPreview) with linked copies of the kit meshes
snapped end to end exactly like the game does, adds every kit light, and renders views to PREVIEW_DIR.
"""

import json
import math

import bpy
from mathutils import Matrix, Vector

PREVIEW_DIR = r"C:\Users\jembo\AppData\Local\Temp\claude\32e351745ce094d2\8e7e5ed1-c280-4d1b-8823-d72de75db220\scratchpad"
ROUTE = [
    "Station", "Tunnel_Straight", "Tunnel_BendR", "Cavern_Lake", "Tunnel_SharpL", "Tunnel_Straight",
    "Cavern_Chasm", "Tunnel_BendL", "Cavern_Garden", "Tunnel_Straight", "StopChamber", "EndCap",
]
LIGHT_RGB = {
    "Lamp": (255, 176, 92), "Blue": (40, 120, 255), "Green": (40, 255, 120), "Red": (255, 40, 60),
    "Yellow": (255, 200, 40), "Shaft": (170, 200, 255),
}

data = json.loads(bpy.data.texts["KitData.json"].as_string())
kit = bpy.data.collections["CaveKit"]

scene = bpy.data.scenes.get("KitPreview") or bpy.data.scenes.new("KitPreview")
bpy.context.window.scene = scene
coll = bpy.data.collections.get("KitPreview")
if coll:
    for obj in list(coll.objects):
        light = obj.data if obj.type == "LIGHT" else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if light and light.users == 0:
            bpy.data.lights.remove(light)
else:
    coll = bpy.data.collections.new("KitPreview")
if coll.name not in scene.collection.children:
    scene.collection.children.link(coll)


def end_of(spec):
    """Where a piece's track ends (piece space) and its turn, stepping like Rules/Track.build."""
    length, turn, drop = spec["length"], spec["turn"], spec["drop"]
    count = max(1, math.ceil(length / 4))
    ds, dh, grade = length / count, turn / count, drop / length
    x = y = z = h = 0.0
    for _ in range(count):
        mid = h + dh / 2
        x, y, z, h = x + math.sin(mid) * ds, y + math.cos(mid) * ds, z - grade * ds, h + dh
    return Vector((x, y, z)), turn


def add_light(name, kind, matrix, energy, rgb, radius=0.5):
    data_block = bpy.data.lights.new(name, kind)
    data_block.energy = energy
    data_block.color = tuple(c / 255 for c in rgb)
    data_block.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data_block)
    obj.matrix_world = matrix
    coll.objects.link(obj)
    return obj


transform = Matrix.Identity(4)
placed = {}
for step, name in enumerate(ROUTE):
    placed.setdefault(name, []).append(transform.copy())
    for source in kit.objects:
        if source.name.startswith(name + "__"):
            copy = bpy.data.objects.new(f"{step:02d}_{source.name}", source.data)
            copy.matrix_world = transform
            coll.objects.link(copy)
    for i, light in enumerate(data[name]["lights"]):
        where = transform @ Vector(light["position"])
        # Roblox Brightness x Range, scaled to Blender watts.
        add_light(f"{step:02d}_{name}_L{i}", "POINT", Matrix.Translation(where),
                  light["brightness"] * light["range"] * 110, LIGHT_RGB[light["color"]], 0.8)
    for i, shaft in enumerate(data[name]["shafts"]):
        top = transform @ Vector(shaft["top"])
        add_light(f"{step:02d}_{name}_S{i}", "SPOT", Matrix.Translation(top), 9000, LIGHT_RGB["Shaft"], 2.0)
    end, turn = end_of(data[name]["spec"])
    transform = transform @ Matrix.Translation(end) @ Matrix.Rotation(-turn, 4, "Z")

# Dim, cool ambient like the zone's Lighting.Ambient.
world = bpy.data.worlds.get("KitWorld") or bpy.data.worlds.new("KitWorld")
try:
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.06, 0.06, 0.085, 1)
    background.inputs["Strength"].default_value = 1.0
except AttributeError:
    pass
scene.world = world
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"

camera_data = bpy.data.cameras.get("KitCamera") or bpy.data.cameras.new("KitCamera")
camera_data.lens = 24
camera_data.clip_end = 3000
camera = bpy.data.objects.get("KitCamera") or bpy.data.objects.new("KitCamera", camera_data)
if camera.name not in coll.objects:
    coll.objects.link(camera)
scene.camera = camera


def view(piece, along, local_eye, local_target, filename):
    """Render from a point in a placed piece's space (Blender axes: +Y forward, +X right, +Z up)."""
    base = placed[piece][0]
    eye = base @ Vector(local_eye)
    target = base @ Vector(local_target)
    camera.location = eye
    camera.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = PREVIEW_DIR + "\\" + filename
    bpy.ops.render.render(write_still=True, scene=scene.name)
    return scene.render.filepath


renders = [
    view("Cavern_Lake", 0, (0, 20, 7), (10, 120, -5), "kit_lake_rider.png"),
    view("Cavern_Lake", 0, (-60, 60, 40), (30, 140, -40), "kit_lake_wide.png"),
    view("Cavern_Chasm", 0, (0, 30, 7), (-15, 140, -30), "kit_chasm_rider.png"),
    view("Cavern_Garden", 0, (30, 50, 25), (-10, 150, -15), "kit_garden.png"),
    view("Tunnel_Straight", 0, (0, 4, 6), (0, 60, 4), "kit_tunnel.png"),
]
result = {"renders": renders, "objects": len(coll.objects)}
