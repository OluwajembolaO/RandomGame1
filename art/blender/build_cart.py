"""Builds the Last Cart Down minecart in Blender (run through the Blender MCP, or Blender's Text Editor).

Units are studs (1 Blender unit = 1 stud). The cart's front faces Blender +Y, which Blender's FBX exporter
(forward -Z, up Y) turns into Roblox's -Z, the cart's LookVector. The origin is rail height at the cart's
center, matching CartService's Root part. Rails sit at x = +/-2.5 (Run.Track.RailGauge = 5).

Each material and each moving part is its own object, so it imports as its own MeshPart:
CartBody, CartChassis, Wheel_FL/FR/BL/BR, CartFloor, CartBenches, Bumpers, Headlamp, HeadlampLens,
Lantern, LanternGlass, BrakeLever, BrakeGrip, NumberPlate, PlateText.
Anything in the CartPreview collection (rails, lights, camera) is only for preview renders.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

SCENE = "Cart"
COLLECTION = "Cart"
PREVIEW = "CartPreview"

# Tub shape: a flared iron box (wider at the top).
FLOOR_Z, RIM_Z = 2.0, 4.8
BOTTOM_X, BOTTOM_Y = 3.0, 4.5
TOP_X, TOP_Y = 3.6, 5.1
WALL = 0.25
RAIL_X = 2.5
WHEEL_R = 0.98
AXLE_Y = 3.0

rng = random.Random(7)


# --- helpers -------------------------------------------------------------------------------------------


def srgb(rgb):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), 1.0)


def material(name, rgb, metallic=0.0, roughness=0.6, emission=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    color = srgb(rgb)
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = color
    return mat


def cols(a, b, c):
    """A 4x4 matrix whose local x, y, z axes are a, b, c."""
    return Matrix(((a.x, b.x, c.x, 0), (a.y, b.y, c.y, 0), (a.z, b.z, c.z, 0), (0, 0, 0, 1)))


def frame_z(z_axis, hint=Vector((0, 0, 1))):
    """Axes with local z along z_axis."""
    z = z_axis.normalized()
    if abs(z.dot(hint)) > 0.95:
        hint = Vector((1, 0, 0))
    x = hint.cross(z).normalized()
    y = z.cross(x)
    return cols(x, y, z)


def scale(x, y, z):
    return Matrix.Diagonal((x, y, z, 1))


def box(bm, center, size, axes=None):
    m = Matrix.Translation(center) @ (axes or Matrix.Identity(4)) @ scale(*size)
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def cylinder(bm, center, axis, radius, depth, segments=16, radius_top=None):
    m = Matrix.Translation(center) @ frame_z(axis)
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius if radius_top is None else radius_top,
        depth=depth,
        matrix=m,
    )


def rod(bm, a, b, radius, segments=8):
    cylinder(bm, (a + b) / 2, b - a, radius, (b - a).length, segments)


def rivet(bm, at, normal, radius=0.085):
    m = Matrix.Translation(at) @ frame_z(normal) @ scale(1, 1, 0.55)
    bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=3, radius=radius, matrix=m)


def bevel_sharp(bm, offset, min_angle=50):
    """Rounds every edge sharper than min_angle degrees, directly in the mesh (no modifier)."""
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(min_angle)]
    bmesh.ops.bevel(bm, geom=edges, offset=offset, segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)


def merge(into, other):
    """Appends one bmesh's geometry to another."""
    mesh = bpy.data.meshes.new("_merge")
    other.to_mesh(mesh)
    other.free()
    into.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


def ring(bm, center, axis, outer, inner, width, segments=28):
    """A flat-sided ring (washer) around axis."""
    m = Matrix.Translation(center) @ frame_z(axis)
    rows = []
    for radius, z in ((outer, -width / 2), (outer, width / 2), (inner, width / 2), (inner, -width / 2)):
        row = []
        for k in range(segments):
            angle = 2 * math.pi * k / segments
            row.append(bm.verts.new(m @ Vector((math.cos(angle) * radius, math.sin(angle) * radius, z))))
        rows.append(row)
    for r in range(4):
        a, b = rows[r], rows[(r + 1) % 4]
        for k in range(segments):
            k2 = (k + 1) % segments
            bm.faces.new((a[k], a[k2], b[k2], b[k]))


def curve_to_bmesh(bm, curve_data):
    """Converts a temporary curve to mesh and appends it to bm."""
    obj = bpy.data.objects.new("_tmp", curve_data)
    bpy.context.scene.collection.objects.link(obj)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    bm.from_mesh(mesh)
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.curves.remove(curve_data)
    bpy.data.meshes.remove(mesh)


def finish(bm, name, mat, coll, bevel=0.0, smooth=True, origin=None):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    mesh.materials.append(mat)
    if origin is not None:
        mesh.transform(Matrix.Translation(-origin))
        obj.location = origin
    if bevel > 0:
        # Only properly sharp edges: a cylinder's sides (under 50 degrees apart) stay as they are.
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(50)
        mod.harden_normals = True
    if smooth and hasattr(mesh, "shade_smooth"):
        mesh.shade_smooth()
        mesh.set_sharp_from_angle(angle=math.radians(35))
    return obj


# --- scene ---------------------------------------------------------------------------------------------


def fresh_collection(scene, name):
    coll = bpy.data.collections.get(name)
    if coll:
        for obj in list(coll.objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if isinstance(data, bpy.types.Mesh) and data.users == 0:
                bpy.data.meshes.remove(data)
    else:
        coll = bpy.data.collections.new(name)
    if coll.name not in scene.collection.children:
        scene.collection.children.link(coll)
    return coll


scene = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
bpy.context.window.scene = scene
cart = fresh_collection(scene, COLLECTION)

M = {
    "iron": material("CartIron", (128, 82, 56), metallic=0.6, roughness=0.75),
    "dark": material("CartDarkIron", (58, 54, 50), metallic=0.8, roughness=0.55),
    "wood": material("CartWood", (122, 86, 54), roughness=0.8),
    "brass": material("CartBrass", (196, 152, 72), metallic=1.0, roughness=0.35),
    "glow": material("CartGlow", (255, 200, 130), emission=12.0),
    "red": material("CartRed", (150, 38, 30), roughness=0.5),
}


# --- the tub (CartBody): flared walls, rolled rim, straps, corner irons, rivets -------------------------


def tub(bm):
    def rect(hx, hy, z):
        return [bm.verts.new(v) for v in ((-hx, -hy, z), (hx, -hy, z), (hx, hy, z), (-hx, hy, z))]

    inset = WALL * 1.02
    outer_bottom = rect(BOTTOM_X, BOTTOM_Y, FLOOR_Z)
    outer_top = rect(TOP_X, TOP_Y, RIM_Z)
    inner_top = rect(TOP_X - inset, TOP_Y - inset, RIM_Z)
    inner_bottom = rect(BOTTOM_X - inset, BOTTOM_Y - inset, FLOOR_Z + WALL)
    bm.faces.new(list(reversed(outer_bottom)))
    bm.faces.new(inner_bottom)
    for k in range(4):
        k2 = (k + 1) % 4
        bm.faces.new((outer_bottom[k], outer_bottom[k2], outer_top[k2], outer_top[k]))
        bm.faces.new((outer_top[k], outer_top[k2], inner_top[k2], inner_top[k]))
        bm.faces.new((inner_top[k], inner_top[k2], inner_bottom[k2], inner_bottom[k]))


def rim(bm):
    curve = bpy.data.curves.new("_rim", type="CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.17
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    corners = ((-TOP_X, -TOP_Y), (TOP_X, -TOP_Y), (TOP_X, TOP_Y), (-TOP_X, TOP_Y))
    spline.points.add(len(corners) - 1)
    for point, (x, y) in zip(spline.points, corners):
        point.co = (x, y, RIM_Z + 0.04, 1)
    spline.use_cyclic_u = True
    curve_to_bmesh(bm, curve)


def strap(bm, details, bottom, top, outward, across, width=0.42, thick=0.12, rivets=4):
    top = top - (top - bottom).normalized() * 0.2
    along = (top - bottom).normalized()
    normal = outward.normalized()
    center = (bottom + top) / 2 + normal * (thick / 2)
    box(bm, center, (width, thick, (top - bottom).length), cols(across, normal, along))
    for k in range(rivets):
        f = (k + 0.5) / rivets
        rivet(details, bottom + (top - bottom) * f + normal * thick, normal)


def straps(bm, details):
    """Iron straps and corner irons go in bm (beveled); their rivets go in details (not beveled)."""
    rise = RIM_Z - FLOOR_Z
    flare_x, flare_y = TOP_X - BOTTOM_X, TOP_Y - BOTTOM_Y
    for side in (-1, 1):
        out = Vector((side * rise, 0, -flare_x))
        for y in (-3.1, 0.0, 3.1):
            strap(
                bm,
                details,
                Vector((side * BOTTOM_X, y, FLOOR_Z)),
                Vector((side * TOP_X, y, RIM_Z)),
                out,
                Vector((0, 1, 0)),
            )
        out = Vector((0, side * rise, -flare_y))
        for x in (-1.7, 1.7):
            strap(
                bm,
                details,
                Vector((x, side * BOTTOM_Y, FLOOR_Z)),
                Vector((x, side * TOP_Y, RIM_Z)),
                out,
                Vector((1, 0, 0)),
            )
    # Angle irons on the four corners.
    for sx in (-1, 1):
        for sy in (-1, 1):
            bottom = Vector((sx * BOTTOM_X, sy * BOTTOM_Y, FLOOR_Z))
            top = Vector((sx * TOP_X, sy * TOP_Y, RIM_Z)) - Vector((0, 0, 0.18))
            along = (top - bottom).normalized()
            out = Vector((sx, sy, 0))
            out = (out - along * out.dot(along)).normalized()
            across = along.cross(out)
            box(bm, (bottom + top) / 2 + out * 0.03, (0.6, 0.12, (top - bottom).length), cols(across, out, along))
            for k in range(3):
                f = (k + 0.5) / 3
                for offset in (-0.18, 0.18):
                    rivet(details, bottom + (top - bottom) * f + out * 0.1 + across * offset, out, 0.07)
    # A row of rivets just under the rim along each long side.
    for side in (-1, 1):
        out = Vector((side * rise, 0, -flare_x)).normalized()
        for k in range(10):
            y = -TOP_Y + 0.7 + k * (2 * TOP_Y - 1.4) / 9
            rivet(details, Vector((side * (TOP_X - 0.06), y, RIM_Z - 0.32)) + out * 0.02, out, 0.07)


bm = bmesh.new()
details = bmesh.new()
tub(bm)
straps(bm, details)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bevel_sharp(bm, 0.05)
rim(details)
merge(bm, details)
finish(bm, "CartBody", M["iron"], cart)


# --- chassis (CartChassis): frame beams, axles, bearing blocks, buffers, brake quadrant, mounts ----------

bm = bmesh.new()
for side in (-1, 1):
    box(bm, Vector((side * 1.7, 0, 1.78)), (0.45, 9.6, 0.45))
    for y in (-AXLE_Y, AXLE_Y):
        box(bm, Vector((side * 1.7, y, 1.22)), (0.62, 0.95, 0.75))
for y in (-4.8, 4.8):
    box(bm, Vector((0, y, 1.78)), (3.85, 0.45, 0.45))
for y in (-AXLE_Y, AXLE_Y):
    rod(bm, Vector((-RAIL_X - 0.45, y, WHEEL_R)), Vector((RAIL_X + 0.45, y, WHEEL_R)), 0.16, 10)
for sy in (-1, 1):
    for sx in (-1, 1):
        cylinder(bm, Vector((sx * 2.6, sy * 5.82, 1.9)), Vector((0, 1, 0)), 0.22, 0.5, 12)
        cylinder(bm, Vector((sx * 2.6, sy * 6.1, 1.9)), Vector((0, 1, 0)), 0.44, 0.12, 16)
    box(bm, Vector((0, sy * 5.9, 1.75)), (0.3, 0.7, 0.26))
# Brake quadrant: a toothed arc plate on the right wall, centered on the lever's pivot.
PIVOT = Vector((3.42, -0.6, 2.75))
segments = 12
inner, outer = 0.25, 1.4
verts_in, verts_out = [], []
for k in range(segments + 1):
    angle = math.radians(-34 + 68 * k / segments)
    direction = Vector((0, -math.sin(angle), math.cos(angle)))
    verts_in.append(PIVOT + direction * inner)
    # Every other point sticks out: the teeth the lever's pawl catches on.
    verts_out.append(PIVOT + direction * (outer + (0.1 if k % 2 == 0 else 0)))
for k in range(segments):
    corners = (verts_in[k], verts_in[k + 1], verts_out[k + 1], verts_out[k])
    front = [bm.verts.new(v + Vector((-0.06, 0, 0))) for v in corners]
    back = [bm.verts.new(v + Vector((0.06, 0, 0))) for v in corners]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((front[i], back[i], back[j], front[j]))
cylinder(bm, PIVOT + Vector((0.12, 0, 0)), Vector((1, 0, 0)), 0.24, 0.32, 14)
# Headlamp mast and lantern hook.
rod(bm, Vector((0, TOP_Y - 0.15, RIM_Z - 0.6)), Vector((0, TOP_Y - 0.05, 6.15)), 0.12, 10)
rod(bm, Vector((0, -TOP_Y + 0.1, RIM_Z - 0.3)), Vector((0, -TOP_Y + 0.1, 5.75)), 0.08, 8)
rod(bm, Vector((0, -TOP_Y + 0.1, 5.75)), Vector((0, -TOP_Y - 0.65, 5.75)), 0.08, 8)
finish(bm, "CartChassis", M["dark"], cart, bevel=0.04)


# --- wheels: flanged rim, spokes, hub. Origins at the wheel centers so they can spin -----------------------


def wheel(name, x, y):
    bm = bmesh.new()
    axis = Vector((1, 0, 0))
    inward = -1 if x > 0 else 1  # flange sits on the inside of the rail
    center = Vector((0, 0, 0))
    ring(bm, center, axis, WHEEL_R, WHEEL_R - 0.2, 0.5, 22)
    ring(bm, center + axis * inward * 0.28, axis, WHEEL_R + 0.18, WHEEL_R - 0.16, 0.12, 22)
    cylinder(bm, center, axis, 0.3, 0.72, 14)
    cylinder(bm, center - axis * inward * 0.42, axis, 0.18, 0.16, 10)
    for k in range(6):
        angle = 2 * math.pi * k / 6
        radial = Vector((0, math.cos(angle), math.sin(angle)))
        tangent = Vector((0, -math.sin(angle), math.cos(angle)))
        middle = radial * ((0.28 + WHEEL_R - 0.18) / 2)
        box(bm, middle, (0.2, 0.15, WHEEL_R - 0.4), cols(axis, tangent, radial))
    obj = finish(bm, name, M["dark"], cart, bevel=0.025)
    obj.location = (x, y, WHEEL_R)
    return obj


for name, x, y in (
    ("Wheel_FL", -RAIL_X, AXLE_Y),
    ("Wheel_FR", RAIL_X, AXLE_Y),
    ("Wheel_BL", -RAIL_X, -AXLE_Y),
    ("Wheel_BR", RAIL_X, -AXLE_Y),
):
    wheel(name, x, y)


# --- floor planks and benches (wood) -------------------------------------------------------------------

bm = bmesh.new()
floor_top = FLOOR_Z + WALL
inner_x, inner_y = BOTTOM_X - WALL - 0.05, BOTTOM_Y - WALL - 0.05
planks = 6
width = 2 * inner_x / planks
for k in range(planks):
    x = -inner_x + width * (k + 0.5)
    tilt = Matrix.Rotation(math.radians(rng.uniform(-0.6, 0.6)), 4, "Z")
    box(bm, Vector((x, rng.uniform(-0.05, 0.05), floor_top + 0.07 + rng.uniform(-0.015, 0.015))), (width - 0.05, 2 * inner_y, 0.14), tilt)
finish(bm, "CartFloor", M["wood"], cart, bevel=0.03)

SEAT_TOP = 3.36
BENCH_Y = (2.2, -2.3)  # front bench, back bench
bm = bmesh.new()
for y in BENCH_Y:
    for offset in (-0.33, 0.33):
        box(bm, Vector((0, y + offset, SEAT_TOP - 0.1)), (5.1, 0.6, 0.2))
    for x in (-2.0, 0.0, 2.0):
        box(bm, Vector((x, y, (floor_top + 0.14 + SEAT_TOP - 0.2) / 2)), (0.3, 1.0, SEAT_TOP - 0.2 - floor_top - 0.14))
finish(bm, "CartBenches", M["wood"], cart, bevel=0.035)

bm = bmesh.new()
for sy in (-1, 1):
    box(bm, Vector((0, sy * 5.38, 1.9)), (7.3, 0.62, 0.85))
finish(bm, "Bumpers", M["wood"], cart, bevel=0.06)


# --- headlamp (brass housing + glowing lens) ------------------------------------------------------------

LAMP = Vector((0, TOP_Y + 0.2, 6.6))
forward = Vector((0, 1, 0))
bm = bmesh.new()
cylinder(bm, LAMP, forward, 0.55, 0.95, 20)
cylinder(bm, LAMP + forward * 0.55, forward, 0.66, 0.18, 24, radius_top=0.6)
ring(bm, LAMP + forward * 0.66, forward, 0.66, 0.5, 0.06, 24)
cylinder(bm, LAMP - forward * 0.5, forward, 0.4, 0.16, 16)
cylinder(bm, LAMP + Vector((0, -0.1, 0.62)), Vector((0, 0, 1)), 0.14, 0.36, 10)
cylinder(bm, LAMP + Vector((0, -0.1, 0.84)), Vector((0, 0, 1)), 0.24, 0.08, 12)
box(bm, LAMP + Vector((0, -0.05, -0.5)), (0.5, 0.4, 0.25))
finish(bm, "Headlamp", M["brass"], cart, bevel=0.02)

bm = bmesh.new()
cylinder(bm, LAMP + forward * 0.63, forward, 0.5, 0.05, 24)
finish(bm, "HeadlampLens", M["glow"], cart, smooth=True)


# --- lantern hanging off the back ----------------------------------------------------------------------

LANTERN = Vector((0, -TOP_Y - 0.65, 5.0))
up = Vector((0, 0, 1))
bm = bmesh.new()
cylinder(bm, LANTERN - up * 0.42, up, 0.34, 0.14, 16)
cylinder(bm, LANTERN + up * 0.42, up, 0.36, 0.22, 16, radius_top=0.12)
for k in range(4):
    angle = math.pi / 4 + k * math.pi / 2
    offset = Vector((math.cos(angle) * 0.27, math.sin(angle) * 0.27, 0))
    rod(bm, LANTERN + offset - up * 0.36, LANTERN + offset + up * 0.36, 0.035, 6)
ring(bm, LANTERN + up * 0.68, Vector((1, 0, 0)), 0.14, 0.09, 0.05, 12)
finish(bm, "Lantern", M["brass"], cart, bevel=0.015)

bm = bmesh.new()
cylinder(bm, LANTERN, up, 0.25, 0.72, 16)
finish(bm, "LanternGlass", M["glow"], cart)


# --- brake lever (origin at its pivot so it can swing) --------------------------------------------------

lean = Matrix.Rotation(math.radians(-14), 4, "X")  # leans back toward the riders
top = PIVOT + (lean @ Vector((0, 0, 3.3, 1))).to_3d()
bm = bmesh.new()
rod(bm, PIVOT + Vector((0.26, 0, 0)), top + Vector((0.26, 0, 0)), 0.11, 10)
box(bm, PIVOT + Vector((0.26, 0, 0)), (0.18, 0.5, 0.5))
finish(bm, "BrakeLever", M["dark"], cart, bevel=0.02, origin=PIVOT.copy())

bm = bmesh.new()
cylinder(bm, top + Vector((0.26, 0, 0)), (top - PIVOT), 0.17, 0.7, 12)
finish(bm, "BrakeGrip", M["red"], cart, bevel=0.02)


# --- number plate on the front wall ---------------------------------------------------------------------

rise, flare = RIM_Z - FLOOR_Z, TOP_Y - BOTTOM_Y
out = Vector((0, rise, -flare)).normalized()
along = Vector((0, flare, rise)).normalized()
plate_center = Vector((0, BOTTOM_Y + flare * 0.5, FLOOR_Z + rise * 0.5)) + out * 0.08
bm = bmesh.new()
box(bm, plate_center, (1.7, 0.08, 1.0), cols(Vector((1, 0, 0)), out, along))
finish(bm, "NumberPlate", M["brass"], cart, bevel=0.02)

text = bpy.data.curves.new("_plate_text", type="FONT")
text.body = "07"
text.size = 0.78
text.extrude = 0.035
text.align_x = "CENTER"
text.align_y = "CENTER"
bm = bmesh.new()
curve_to_bmesh(bm, text)
# Text is built flat in XY; stand it up on the plate, facing out. Seen from the front, world +X is on the
# viewer's left, so the text's x runs along -X to read correctly.
bmesh.ops.transform(
    bm,
    matrix=Matrix.Translation(plate_center + out * 0.075) @ cols(Vector((-1, 0, 0)), along, out),
    verts=bm.verts,
)
finish(bm, "PlateText", M["dark"], cart, smooth=False)


# --- a pickaxe strapped to the left side (wooden handle with the bumpers, iron head with the chassis) ----


def wall_x(z):
    """Outer surface of the long walls at height z."""
    return BOTTOM_X + (TOP_X - BOTTOM_X) * (z - FLOOR_Z) / (RIM_Z - FLOOR_Z)


handle_a = Vector((-wall_x(3.05) - 0.32, -2.5, 3.05))
handle_b = Vector((-wall_x(3.75) - 0.32, 1.3, 3.75))
pick_axis = (handle_b - handle_a).normalized()
wall_out = Vector((-(RIM_Z - FLOOR_Z), 0, -(TOP_X - BOTTOM_X))).normalized()
head_dir = pick_axis.cross(wall_out).normalized()  # across the handle, in the wall's plane
bm = bmesh.new()
rod(bm, handle_a, handle_b + pick_axis * 0.3, 0.11, 8)
finish(bm, "PickHandle", M["wood"], cart, bevel=0.0)
bm = bmesh.new()
head = handle_b + pick_axis * 0.05
for sign in (-1, 1):
    tip = head + head_dir * sign * 1.15 - pick_axis * 0.25
    box(bm, (head + tip) / 2, (0.22, 0.24, (tip - head).length), cols(pick_axis, wall_out, (tip - head).normalized()))
box(bm, head, (0.45, 0.36, 0.5), cols(head_dir, wall_out, pick_axis))
for f in (0.25, 0.7):
    clip = handle_a + (handle_b - handle_a) * f
    box(bm, clip - wall_out * 0.12, (0.3, 0.32, 0.36), cols(head_dir, wall_out, pick_axis))
finish(bm, "PickHead", M["dark"], cart, bevel=0.03)


# --- preview staging: rails, sleepers, ground, lights and camera (never exported) ------------------------

preview = fresh_collection(scene, PREVIEW)
bm = bmesh.new()
for x in (-RAIL_X, RAIL_X):
    box(bm, Vector((x, 0, -0.2)), (0.35, 40, 0.4))
for k in range(-20, 21):
    box(bm, Vector((0, k * 1.2, -0.55)), (7.4, 0.6, 0.3))
finish(bm, "PreviewRails", M["dark"], preview)
bm = bmesh.new()
box(bm, Vector((0, 0, -1.2)), (60, 60, 1.0))
finish(bm, "PreviewGround", material("PreviewRock", (52, 46, 42), roughness=0.95), preview, smooth=False)


def light(name, kind, location, energy, rgb, size=1.0, target=Vector((0, 0, 3))):
    data = bpy.data.lights.get(name) or bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = srgb(rgb)[:3]
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    preview.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (target - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    return obj


light("Key", "AREA", (7, 9, 10), 1400, (255, 214, 170), size=6)
light("Rim", "AREA", (-7, -8, 6), 1100, (150, 190, 255), size=5)
light("Fill", "POINT", (9, -4, 3), 220, (255, 230, 210))
beam = light("HeadlampBeam", "SPOT", tuple(LAMP + forward * 0.7), 900, (255, 205, 140), target=LAMP + Vector((0, 20, -6)))
beam.data.spot_size = math.radians(70)
beam.data.spot_blend = 0.6

camera_data = bpy.data.cameras.get("CartCamera") or bpy.data.cameras.new("CartCamera")
camera_data.lens = 45
camera = bpy.data.objects.new("CartCamera", camera_data)
preview.objects.link(camera)
scene.camera = camera
# Named views for preview renders: set camera.location / aim with aim_camera(view).
VIEWS = {
    "front": ((15.0, 19.5, 9.0), (0, 0.4, 3.0)),
    "rear": ((-13.0, -15.5, 13.0), (0, -0.4, 3.2)),
    "side": ((-20.0, 1.5, 5.0), (0, 0.0, 3.0)),
}


def aim_camera(view):
    location, target = VIEWS[view]
    camera.location = location
    camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()


aim_camera("front")

world = bpy.data.worlds.get("CartWorld") or bpy.data.worlds.new("CartWorld")
world.color = (0.012, 0.010, 0.010)
try:
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.012, 0.010, 0.010, 1)
    background.inputs["Strength"].default_value = 1.0
except AttributeError:
    pass
scene.world = world
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1280
scene.render.resolution_y = 800
scene.view_settings.look = "AgX - Medium High Contrast"

# Report back to whoever ran this.
depsgraph = bpy.context.evaluated_depsgraph_get()
counts = {}
for obj in cart.objects:
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    counts[obj.name] = len(mesh.loop_triangles)
    evaluated.to_mesh_clear()
result = {"objects": len(cart.objects), "triangles": counts, "total": sum(counts.values())}
