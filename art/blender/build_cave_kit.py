"""Builds the Last Cart Down cave kit in Blender (run through the Blender MCP, or Blender's Text Editor).

The cave is a kit of pieces the game snaps together into a new route every run: tunnel straights and bends,
big crystal caverns crossed on timber trestles, the station, a stop chamber and an end cap. Every piece is
modeled around the exact track path the game computes (Rules/Track.build: 4-stud steps along an arc that
drops linearly), and every tunnel mouth has the same cross-section, so any piece joins any other.

Units are studs. Each piece is built in its own local space: the track starts at the origin heading +Y
(Blender), rails at height 0. Roblox's GLB import (after the 180 degree turn, TRAPS #39) maps
Blender (x, y, z) to Roblox (x, z, -y), so +Y here is the piece's forward (-Z, LookVector) in Roblox.

Objects are named <Piece>__<Group> (Rock, Timber, Crystals_Blue, ...) so each group imports as one MeshPart
that Studio can color and light. The script also writes src/shared/Config/KitData.luau: each piece's
track shape plus the lights, spores, mist and light shafts the game adds on top.
"""

import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

REPO = r"c:\RobloxGames\RandomGame1"
SCENE = "CaveKit"
STEP = 4.0  # Run.Track.Step
UP = Vector((0, 0, 1))

# The standard tunnel mouth every piece starts and ends with. LIFT is the cross-section's center above the
# rails; the floor sits BOTTOM - LIFT = 3 studs under the rails.
LIFT, HALF_W, TOP, BOTTOM = 10.0, 20.0, 18.0, 13.0

COLORS = ("Blue", "Green", "Red", "Yellow")

KIT = {
    "Station": dict(kind="Station", length=64, turn=0.0, drop=0.0, palette=("Yellow", "Blue"), seed=11),
    "StopChamber": dict(kind="Stop", length=180, turn=0.0, drop=0.0, palette=COLORS, seed=12),
    "Tunnel_Straight": dict(kind="Tunnel", length=64, turn=0.0, drop=4.0, palette=COLORS, seed=21),
    "Tunnel_BendL": dict(kind="Tunnel", length=64, turn=-math.radians(30), drop=4.0, palette=COLORS, seed=22),
    "Tunnel_BendR": dict(kind="Tunnel", length=64, turn=math.radians(30), drop=4.0, palette=COLORS, seed=23),
    "Tunnel_SharpL": dict(kind="Tunnel", length=48, turn=-math.radians(45), drop=2.0, sharp=True, palette=COLORS, seed=24),
    "Tunnel_SharpR": dict(kind="Tunnel", length=48, turn=math.radians(45), drop=2.0, sharp=True, palette=COLORS, seed=25),
    # Caverns: (half width, ceiling, floor depth below the cross-section center) at full size, lake or not.
    "Cavern_Lake": dict(kind="Cavern", length=224, turn=0.0, drop=10.0, palette=("Blue", "Green"), seed=31,
                        size=(85, 70, 70), lake=True, side=1),
    "Cavern_Chasm": dict(kind="Cavern", length=224, turn=0.0, drop=10.0, palette=("Red", "Yellow"), seed=32,
                         size=(75, 80, 125), lake=False, side=-1),
    "Cavern_Garden": dict(kind="Cavern", length=224, turn=0.0, drop=10.0, palette=COLORS, seed=33,
                          size=(95, 60, 42), lake=True, side=1),
    "EndCap": dict(kind="Cap", length=8, turn=0.0, drop=0.0, palette=COLORS, seed=41),
}

# Preview colors (Roblox colors are set in Studio; see TRAPS #39).
SWATCH = {
    "Rock": (78, 70, 66), "Timber": (110, 78, 48), "Lanterns": (150, 112, 56), "LanternGlass": (255, 196, 120),
    "Glowworms": (150, 235, 255), "Threads": (120, 130, 140), "Stems": (215, 205, 185), "Water": (30, 95, 105),
    "Blue": (40, 120, 255), "Green": (40, 255, 120), "Red": (255, 40, 60), "Yellow": (255, 200, 40),
}
GLOWING = {"LanternGlass", "Glowworms", "Blue", "Green", "Red", "Yellow"}


# --- small helpers ---------------------------------------------------------------------------------------


def srgb(rgb):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), 1.0)


def material(key):
    rgb = SWATCH[key]
    name = "Kit_" + key
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = srgb(rgb)
    bsdf.inputs["Roughness"].default_value = 0.85 if key == "Rock" else 0.5
    if key in GLOWING:
        bsdf.inputs["Emission Color"].default_value = srgb(rgb)
        bsdf.inputs["Emission Strength"].default_value = 2.5
    mat.diffuse_color = srgb(rgb)
    return mat


def smoothstep(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def frame_z(z_axis):
    z = z_axis.normalized()
    hint = Vector((1, 0, 0)) if abs(z.z) > 0.9 else UP
    x = hint.cross(z).normalized()
    y = z.cross(x)
    return Matrix(((x.x, y.x, z.x, 0), (x.y, y.y, z.y, 0), (x.z, y.z, z.z, 0), (0, 0, 0, 1)))


def cone(bm, base, direction, length, radius, tip=0.0, segments=7):
    """A tapered spike (or cylinder) from base along direction."""
    m = Matrix.Translation(base + direction.normalized() * length / 2) @ frame_z(direction)
    bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=tip, depth=length, matrix=m
    )


def box(bm, center, size, axes=None):
    m = Matrix.Translation(center) @ (axes or Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def beam(bm, a, b, thickness):
    direction = b - a
    m = Matrix.Translation((a + b) / 2) @ frame_z(direction) @ Matrix.Diagonal((thickness, thickness, direction.length, 1))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def rock(bm, center, radius, rng):
    m = Matrix.Translation(center) @ Matrix.Diagonal((radius * rng.uniform(0.8, 1.3), radius * rng.uniform(0.8, 1.3), radius * rng.uniform(0.5, 0.9), 1))
    result = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=m)
    for v in result["verts"]:
        v.co += (v.co - center).normalized() * rng.uniform(-0.18, 0.18) * radius


def to_roblox(v):
    """Blender piece space -> Roblox piece space (after the import turn): (x, z, -y)."""
    return (round(v.x, 2), round(v.z, 2), round(-v.y, 2))


# --- the track path, exactly as Rules/Track.build steps it ---------------------------------------------


def path(spec):
    """Points every STEP studs: (position, heading, distance). Heading 0 is +Y; positive turns right (+X)."""
    length, turn, drop = spec["length"], spec["turn"], spec["drop"]
    count = max(1, math.ceil(length / STEP))
    ds, dh, grade = length / count, turn / count, drop / length
    x = y = z = h = 0.0
    travelled = 0.0
    points = [(Vector((0, 0, 0)), 0.0, 0.0)]
    for _ in range(count):
        mid = h + dh / 2
        dx, dy, dz = math.sin(mid) * ds, math.cos(mid) * ds, -grade * ds
        x, y, z, h = x + dx, y + dy, z + dz, h + dh
        travelled += math.sqrt(dx * dx + dy * dy + dz * dz)
        points.append((Vector((x, y, z)), h, travelled))
    return points


def right_of(heading):
    return Vector((math.cos(heading), -math.sin(heading), 0))


def forward_of(heading):
    return Vector((math.sin(heading), math.cos(heading), 0))


# --- cross-sections --------------------------------------------------------------------------------------


def section(theta, hw, top, bottom, floor=None, offset=0.0):
    """A squarish, lumpy loop around the track: (lateral, height above the rails)."""
    c, s = math.cos(theta), math.sin(theta)
    n = 2.6
    a = math.copysign(abs(c) ** (2 / n), c) * hw
    b = math.copysign(abs(s) ** (2 / n), s) * (top if s > 0 else bottom)
    wobble = 1 + 0.07 * math.sin(3 * theta + 1.3) + 0.05 * math.sin(5 * theta + 0.4) + 0.03 * math.sin(9 * theta + 2.2)
    a, b = a * wobble, b * wobble
    if floor is not None:
        b = max(b, -floor)
    return a + offset, b + LIFT


def shape_for(name, spec):
    """Returns (params(d) -> dict of section args, displacement amplitude(d))."""
    length = spec["length"]
    kind = spec["kind"]

    def lerp(a, b, t):
        return a + (b - a) * t

    def ends_taper(d, span=8.0):
        return min(1.0, d / span, (length - d) / span)

    if kind == "Cavern":
        hw, top, bottom = spec["size"]

        def ramp(d):
            return smoothstep((d - 6) / 70) * smoothstep((length - d - 6) / 70)

        def params(d):
            r = ramp(d)
            wave = math.sin(d / length * math.pi * 2.0 + spec["seed"]) * 0.12
            return dict(
                hw=lerp(HALF_W, hw * (1 + wave), r),
                top=lerp(TOP, top * (1 - wave), r),
                bottom=lerp(BOTTOM, bottom, r),
                offset=spec["side"] * 22 * r,
            )

        return params, lambda d: (2.0 + 14.0 * ramp(d)) * ends_taper(d), ramp

    if kind == "Station":

        def ramp(d):
            return smoothstep((length - d - 4) / 22)

        def params(d):
            r = ramp(d)
            return dict(hw=lerp(HALF_W, 52, r), top=lerp(TOP, 30, r), bottom=lerp(BOTTOM, 12, r),
                        floor=lerp(BOTTOM, 11.2, r), offset=10 * r)

        return params, lambda d: 1.6 * ends_taper(d, 10) * (1 - 0.5 * ramp(d)), ramp

    if kind == "Stop":

        def ramp(d):
            return smoothstep((d - 4) / 26) * smoothstep((length - d - 4) / 26)

        def params(d):
            r = ramp(d)
            return dict(hw=lerp(HALF_W, 62, r), top=lerp(TOP, 40, r), bottom=lerp(BOTTOM, 12, r),
                        floor=lerp(BOTTOM, 11.2, r), offset=8 * r)

        return params, lambda d: (1.6 + 4 * ramp(d)) * ends_taper(d), ramp

    def params(d):
        return dict(hw=HALF_W, top=TOP, bottom=BOTTOM)

    return params, lambda d: 1.8 * ends_taper(d), lambda d: 0.0


# --- the rock shell: a cross-section swept along the track, faces pointing inward ------------------------


def sweep(bm, spec, params, amplitude, segments, seed, cap_start=False, cap_end=False):
    points = path(spec)
    uv = bm.loops.layers.uv.verify()
    rings = []
    info = []  # per vertex: (d, theta, lateral, height above that point's rails)
    offset = Vector((seed * 17.3, seed * 7.1, seed * 3.7))
    for position, heading, d in points:
        right = right_of(heading)
        p = params(d)
        amp = amplitude(d)
        ring = []
        for k in range(segments + 1):
            theta = 2 * math.pi * (k % segments) / segments
            a, b = section(theta, **p)
            base = position + right * a + UP * b
            radial = (right * (a - p.get("offset", 0.0)) + UP * (b - LIFT)).normalized()
            n = noise.noise((base + offset) * 0.045) + 0.45 * noise.noise((base + offset) * 0.14)
            vert = bm.verts.new(base + radial * n * amp)
            ring.append(vert)
            info.append((vert, d, theta, a, b))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segments):
            face = bm.faces.new((rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]))
            for loop in face.loops:
                index = rings[i].index(loop.vert) if loop.vert in rings[i] else rings[i + 1].index(loop.vert)
                row = i if loop.vert in rings[i] else i + 1
                loop[uv].uv = (index / segments * 10.0, points[row][2] / 14.0)
    for ring, point, inward in ((rings[0], points[0], forward_of(points[0][1])), (rings[-1], points[-1], -forward_of(points[-1][1]))):
        if (ring is rings[0] and cap_start) or (ring is rings[-1] and cap_end):
            center = bm.verts.new(sum((v.co for v in ring[:-1]), Vector()) / segments)
            for k in range(segments):
                face = bm.faces.new((center, ring[k], ring[k + 1]))
                face.normal_update()
                if face.normal.dot(inward) < 0:
                    face.normal_flip()
    bm.normal_update()
    return points, info


# --- details ------------------------------------------------------------------------------------------------


class Piece:
    def __init__(self, name, spec):
        self.name, self.spec = name, spec
        self.rng = random.Random(spec["seed"])
        self.groups = {}
        self.lights = []
        self.emitters = []
        self.shafts = []
        self.lake = None

    def bm(self, group):
        if group not in self.groups:
            self.groups[group] = bmesh.new()
        return self.groups[group]

    def light(self, position, color, rng_range, brightness, flicker=False, pulse=False):
        self.lights.append(dict(position=position, color=color, range=rng_range, brightness=brightness,
                                flicker=flicker, pulse=pulse))

    def track_z(self, d):
        return -self.spec["drop"] * d / self.spec["length"]


def corridor(piece, vert, d, a, margin=0.0):
    """True when a point is in the space the cart and riders pass through."""
    above = vert.co.z - piece.track_z(d)
    return abs(a - 0) < 13 + margin and -6 < above < 22 + margin


def crystal_cluster(piece, base, normal, size, color):
    bm = piece.bm("Crystals_" + color)
    rng = piece.rng
    count = rng.randint(4, 8) if size < 12 else rng.randint(3, 5)
    for i in range(count):
        jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.55
        direction = (normal + jitter).normalized()
        length = size * (1.0 if i == 0 else rng.uniform(0.35, 0.8))
        radius = length * rng.uniform(0.12, 0.17)
        start = base + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * size * 0.15 - direction * 0.4
        body = length * 0.72
        cone(bm, start, direction, body, radius, radius * 0.88, 6)
        cone(bm, start + direction * body, direction, length - body, radius * 0.88, 0.0, 6)


def mushroom_patch(piece, base, color):
    rng = piece.rng
    stems, caps = piece.bm("Stems"), piece.bm("Mushrooms_" + color)
    for _ in range(rng.randint(3, 7)):
        spot = base + Vector((rng.uniform(-2.5, 2.5), rng.uniform(-2.5, 2.5), 0))
        height = rng.uniform(0.8, 3.2)
        radius = rng.uniform(0.5, 1.8)
        lean = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 1)).normalized()
        cone(stems, spot - UP * 0.3, lean, height + 0.3, radius * 0.22, radius * 0.18, 6)
        top = spot + lean * height
        cone(caps, top - lean * radius * 0.15, lean, radius * 0.55, radius, radius * 0.25, 10)


def glowworm(piece, anchor):
    rng = piece.rng
    length = rng.uniform(1.2, 4.5)
    tip = anchor - UP * length
    cone(piece.bm("Threads"), tip, UP, length + 0.5, 0.035, 0.035, 3)
    bmesh.ops.create_icosphere(piece.bm("Glowworms"), subdivisions=1, radius=rng.uniform(0.16, 0.28), matrix=Matrix.Translation(tip))


def lantern(piece, at, light_range=30):
    frame, glass = piece.bm("Lanterns"), piece.bm("LanternGlass")
    cone(frame, at + UP * 0.6, UP, 0.3, 0.55, 0.15, 8)
    cone(frame, at - UP * 0.7, UP, 0.15, 0.45, 0.45, 8)
    cone(glass, at - UP * 0.55, UP, 1.1, 0.32, 0.32, 8)
    piece.light(at, "Lamp", light_range, 2.4, flicker=True)


def shoring(piece, position, heading):
    """A timber mine support across the tunnel with a lantern hanging from the cap."""
    bm = piece.bm("Timber")
    right = right_of(heading)
    for side in (-1, 1):
        foot = position + right * side * 12 - UP * 4
        top = position + right * side * 12 + UP * 14
        beam(bm, foot, top, 1.4)
        beam(bm, position + right * side * 12 + UP * 9.5, position + right * side * 8.5 + UP * 13.3, 0.8)
    beam(bm, position + right * -13 + UP * 14, position + right * 13 + UP * 14, 1.4)
    lantern(piece, position + right * 7 + UP * 12.2, 30)


def trestle(piece, info_by_ring, points, ramp):
    """Timber bents under the track wherever the floor drops away, plus the deck and lantern posts."""
    bm = piece.bm("Timber")
    gauge = 2.5 + 1.4
    # Deck stringers along the whole piece.
    for side in (-1, 1):
        for i in range(len(points) - 1):
            a, ha = points[i][0], points[i][1]
            b, hb = points[i + 1][0], points[i + 1][1]
            beam(bm, a + right_of(ha) * side * 3.1 - UP * 1.3, b + right_of(hb) * side * 3.1 - UP * 1.3, 1.1)
    bent = 0
    for i in range(0, len(points), 3):
        position, heading, d = points[i]
        floor = lowest_below(info_by_ring[i], position)
        if floor is None or position.z - floor < 8:
            continue
        right = right_of(heading)
        deck = position.z - 1.9
        for side in (-1, 1):
            top = position + right * side * gauge
            beam(bm, Vector((top.x, top.y, floor - 2)), Vector((top.x, top.y, deck)), 1.3)
        beam(bm, position - right * (gauge + 1) + UP * (deck - position.z), position + right * (gauge + 1) + UP * (deck - position.z), 1.1)
        y = 2.0
        while y + 16 < deck - floor and y < 140:
            for side in (-1, 1):
                a = position + right * side * gauge
                b = position - right * side * gauge
                beam(bm, Vector((a.x, a.y, deck - y)), Vector((b.x, b.y, deck - y - 16)), 0.7)
            y += 18
        if bent % 3 == 0:
            side = 1 if bent % 6 == 0 else -1
            post = position + right * side * (gauge + 0.7)
            beam(bm, Vector((post.x, post.y, deck)), Vector((post.x, post.y, deck + 7)), 0.6)
            lantern(piece, Vector((post.x, post.y, deck + 7.6)), 32)
        bent += 1


def lowest_below(ring_info, position):
    """Height of the shell's floor straight under the track at this ring (None if it can't tell)."""
    best = None
    for vert, d, theta, a, b in ring_info:
        if math.sin(theta) < -0.2 and abs(a) < 14:
            z = vert.co.z
            best = z if best is None else min(best, z)
    return best


def dress(piece, points, info):
    """Crystals, giant crystals, stalactites, mushrooms, glow-worms, boulders, shoring and the lake."""
    spec, rng = piece.spec, piece.rng
    kind = spec["kind"]
    palette = spec["palette"]
    by_ring = {}
    for entry in info:
        by_ring.setdefault(round(entry[1] / STEP), []).append(entry)
    ring_keys = sorted(by_ring)

    walls = [e for e in info if abs(math.cos(e[2])) > 0.45]
    ceilings = [e for e in info if math.sin(e[2]) > 0.55]
    floors = [e for e in info if math.sin(e[2]) < -0.55]

    big = kind == "Cavern"
    room = kind in ("Station", "Stop")
    counts = {
        "Cavern": dict(clusters=40, giants=4, spikes=26, mites=14, worms=90, patches=22, rocks=16),
        "Station": dict(clusters=6, giants=0, spikes=6, mites=0, worms=24, patches=6, rocks=8),
        "Stop": dict(clusters=14, giants=2, spikes=12, mites=4, worms=40, patches=10, rocks=8),
        "Tunnel": dict(clusters=3, giants=0, spikes=4, mites=0, worms=14, patches=3, rocks=4),
        "Cap": dict(clusters=2, giants=0, spikes=2, mites=0, worms=4, patches=1, rocks=6),
    }[kind]

    def pick(pool, avoid_margin=0.0, tries=40):
        if not pool:
            return None
        for _ in range(tries):
            vert, d, theta, a, b = rng.choice(pool)
            if not corridor(piece, vert, d, a, avoid_margin) and 3 < d < spec["length"] - 3:
                return vert, d, theta, a, b
        return None

    # Lake first: everything below the waterline is underwater.
    if spec.get("lake"):
        hw, top, bottom = spec["size"]
        level = LIFT - bottom + 15 + piece.track_z(spec["length"] / 2)
        piece.lake = level
        mid = spec["length"] / 2
        water = piece.bm("Water")
        box(water, Vector((spec["side"] * 22, mid, level - 0.3)), (hw * 2.4, spec["length"] - 70, 0.6))
        for i in range(3):
            spot = Vector((spec["side"] * 22 + rng.uniform(-hw, hw) * 0.6, mid + rng.uniform(-50, 50), level - 3))
            piece.light(spot, palette[i % len(palette)], 48, 1.4, pulse=True)
        piece.emitters.append(dict(kind="Mist", center=Vector((spec["side"] * 22, mid, level + 2.5)),
                                   size=Vector((hw * 1.6, spec["length"] * 0.55, 4))))

    def dry(vert):
        return piece.lake is None or vert.co.z > piece.lake + 0.5

    # Crystal clusters on the walls (and some on floors), each glowing with its own light.
    for i in range(counts["clusters"]):
        found = pick(walls + floors if i % 3 == 0 else walls)
        if not found:
            continue
        vert, d, theta, a, b = found
        color = rng.choice(palette)
        size = rng.uniform(4, 11) if big else rng.uniform(2.5, 6)
        crystal_cluster(piece, vert.co.copy(), vert.normal.copy(), size, color)
        if size > 5 or not big:
            piece.light(vert.co + vert.normal * (2.5 + size * 0.35), color, min(55, 16 + size * 3), 1.9, pulse=True)

    # Giant crystals: the focal points of a cavern.
    for _ in range(counts["giants"]):
        found = pick(floors + walls, avoid_margin=12)
        if not found:
            continue
        vert, d, theta, a, b = found
        color = rng.choice(palette)
        size = rng.uniform(22, 42)
        crystal_cluster(piece, vert.co.copy(), (vert.normal + UP * 0.6).normalized(), size, color)
        piece.light(vert.co + vert.normal * 6 + UP * size * 0.4, color, 60, 2.6, pulse=True)

    rock_bm = piece.bm("Rock")
    # Stalactites from the ceiling, stalagmites from dry floor.
    for _ in range(counts["spikes"]):
        found = pick(ceilings, avoid_margin=6)
        if found:
            vert = found[0]
            length = rng.uniform(8, 32) if big else rng.uniform(3, 9)
            cone(rock_bm, vert.co + UP * 1.0, Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), -1)), length,
                 length * rng.uniform(0.18, 0.28), 0.0, 7)
    for _ in range(counts["mites"]):
        found = pick(floors, avoid_margin=6)
        if found and dry(found[0]):
            vert = found[0]
            length = rng.uniform(6, 24)
            cone(rock_bm, vert.co - UP * 1.0, Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 1)), length,
                 length * rng.uniform(0.2, 0.3), 0.0, 7)

    # Boulders on the floor.
    for _ in range(counts["rocks"]):
        found = pick(floors)
        if found:
            rock(rock_bm, found[0].co.copy(), rng.uniform(1.5, 5.5) if big else rng.uniform(1.0, 3.0), rng)

    # Glowing mushroom patches on dry floor.
    for _ in range(counts["patches"]):
        found = pick(floors)
        if found and dry(found[0]):
            color = rng.choice(palette)
            mushroom_patch(piece, found[0].co.copy(), color)
            if rng.random() < 0.5:
                piece.light(found[0].co + UP * 3, color, 18, 1.2, pulse=True)

    # Glow-worm threads hanging from the ceiling: soft blue-white dots overhead.
    for _ in range(counts["worms"]):
        found = pick(ceilings)
        if found:
            glowworm(piece, found[0].co.copy())

    # Mine shoring every 32 studs through tunnels.
    if kind == "Tunnel":
        for d_mark in range(16, int(spec["length"]), 32):
            position, heading, d = points[round(d_mark / STEP)]
            shoring(piece, position, heading)

    if big:
        trestle(piece, [by_ring[k] for k in ring_keys], points, None)
        hw, top, bottom = spec["size"]
        mid = spec["length"] / 2
        piece.emitters.append(dict(kind="Spores", center=Vector((spec["side"] * 22, mid, LIFT + 6)),
                                   size=Vector((hw * 1.5, spec["length"] * 0.6, top * 0.9)), colors=list(palette)))
        # Light shafts through cracks in the ceiling, near the track.
        for _ in range(2):
            found = pick([e for e in ceilings if abs(e[3]) < 40 and 70 < e[1] < spec["length"] - 70])
            if found:
                vert = found[0]
                bottom_z = piece.lake if piece.lake is not None else vert.co.z - 140
                piece.shafts.append(dict(top=vert.co.copy() - UP * 1.0, bottom=Vector((vert.co.x, vert.co.y, bottom_z))))

    if room:
        piece.emitters.append(dict(kind="Spores", center=Vector((10, spec["length"] / 2, LIFT + 8)),
                                   size=Vector((80, spec["length"] * 0.7, 26)), colors=list(palette)))
        # Hanging work lamps along both walls.
        for d_mark in range(12, int(spec["length"]) - 8, 28):
            position, heading, d = points[round(d_mark / STEP)]
            for side in (-1, 1):
                lantern(piece, position + right_of(heading) * side * 24 + UP * 16, 40)


# --- build the kit -------------------------------------------------------------------------------------------


def fresh_collection(scene, name):
    coll = bpy.data.collections.get(name)
    if coll:
        for obj in list(coll.objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if isinstance(data, bpy.types.Mesh) and data.users == 0:
                bpy.data.meshes.remove(data)
        for light in [l for l in bpy.data.lights if l.users == 0]:
            bpy.data.lights.remove(light)
    else:
        coll = bpy.data.collections.new(name)
    if coll.name not in scene.collection.children:
        scene.collection.children.link(coll)
    return coll


def build_piece(name, spec):
    piece = Piece(name, spec)
    params, amplitude, _ = shape_for(name, spec)
    segments = 64 if spec["kind"] == "Cavern" else 44 if spec["kind"] in ("Station", "Stop") else 30
    rock_bm = piece.bm("Rock")
    points, info = sweep(
        rock_bm,
        spec,
        params,
        amplitude,
        segments,
        spec["seed"],
        cap_start=spec["kind"] == "Station",
        cap_end=spec["kind"] == "Cap",
    )
    dress(piece, points, info)
    return piece


def finish(piece, coll, offset):
    objects = []
    for group, bm in piece.groups.items():
        bm.normal_update()
        mesh = bpy.data.meshes.new(piece.name + "__" + group)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(piece.name + "__" + group, mesh)
        coll.objects.link(obj)
        obj.location = offset
        key = group.split("_")[-1] if group.startswith(("Crystals_", "Mushrooms_")) else group
        mesh.materials.append(material(key if key in SWATCH else "Rock"))
        if hasattr(mesh, "shade_smooth"):
            mesh.shade_smooth()
            mesh.set_sharp_from_angle(angle=math.radians(40 if group == "Rock" else 30))
        objects.append(obj)
    return objects


def lua_number(n):
    text = ("%.2f" % n).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def lua_vector(v):
    x, y, z = to_roblox(v)
    return "{ %s, %s, %s }" % (lua_number(x), lua_number(y), lua_number(z))


def lua_size(v):
    # Sizes are extents: swap axes like positions but keep them positive.
    return "{ %s, %s, %s }" % (lua_number(abs(v.x)), lua_number(abs(v.z)), lua_number(abs(v.y)))


def write_kit_data(pieces, path_out):
    lines = [
        "-- Generated by art/blender/build_cave_kit.py. Don't edit by hand: change the script and run it again.",
        "-- Each cave kit piece: its track shape (Length, Turn in radians, positive = right, Drop) and what the game",
        "-- adds on top of its meshes. Positions are in the piece's own space: the track starts at the origin heading",
        "-- -Z, rails at Y = 0. Colors name Zone palette entries (Lamp, Blue, Green, Red, Yellow).",
        "",
        "return {",
        "    Step = %s," % lua_number(STEP),
        "    Pieces = {",
    ]
    for piece in pieces:
        spec = piece.spec
        lines.append("        %s = {" % piece.name)
        lines.append('            Kind = "%s",' % spec["kind"])
        lines.append("            Length = %s," % lua_number(spec["length"]))
        lines.append("            Turn = %s," % repr(round(spec["turn"], 6)))
        lines.append("            Drop = %s," % lua_number(spec["drop"]))
        lines.append("            Sharp = %s," % ("true" if spec.get("sharp") else "false"))
        lines.append("            Palette = { %s }," % ", ".join('"%s"' % c for c in spec["palette"]))
        lines.append("            Lake = %s," % (lua_number(piece.lake) if piece.lake is not None else "nil"))
        lines.append("            Lights = {")
        for light in piece.lights:
            lines.append(
                '                { Position = %s, Color = "%s", Range = %s, Brightness = %s, Flicker = %s, Pulse = %s },'
                % (lua_vector(light["position"]), light["color"], lua_number(light["range"]),
                   lua_number(light["brightness"]), "true" if light["flicker"] else "false",
                   "true" if light["pulse"] else "false")
            )
        lines.append("            },")
        lines.append("            Emitters = {")
        for emitter in piece.emitters:
            colors = emitter.get("colors")
            lines.append(
                '                { Kind = "%s", Center = %s, Size = %s%s },'
                % (emitter["kind"], lua_vector(emitter["center"]), lua_size(emitter["size"]),
                   (", Colors = { %s }" % ", ".join('"%s"' % c for c in colors)) if colors else "")
            )
        lines.append("            },")
        lines.append("            Shafts = {")
        for shaft in piece.shafts:
            lines.append("                { Top = %s, Bottom = %s }," % (lua_vector(shaft["top"]), lua_vector(shaft["bottom"])))
        lines.append("            },")
        lines.append("        },")
    lines += ["    },", "}", ""]
    with open(path_out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))


scene = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
bpy.context.window.scene = scene
kit = fresh_collection(scene, "CaveKit")

SPACING = 700.0  # pieces are laid out side by side along X for export
pieces = []
report = {}
for index, (name, spec) in enumerate(KIT.items()):
    piece = build_piece(name, spec)
    offset = Vector((index * SPACING, 0, 0))
    objects = finish(piece, kit, offset)
    piece.offset = offset
    pieces.append(piece)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tris = {}
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        tris[obj.name.split("__")[1]] = len(mesh.loop_triangles)
    report[name] = dict(tris=tris, lights=len(piece.lights), shafts=len(piece.shafts))

write_kit_data(pieces, os.path.join(REPO, "src", "shared", "Config", "KitData.luau"))

# Blender-space copy of the lights and shafts, for preview_cave_kit.py.
import json

store = bpy.data.texts.get("KitData.json") or bpy.data.texts.new("KitData.json")
store.clear()
store.write(json.dumps({
    p.name: dict(
        spec=dict(length=p.spec["length"], turn=p.spec["turn"], drop=p.spec["drop"]),
        lights=[dict(position=list(l["position"]), color=l["color"], range=l["range"],
                     brightness=l["brightness"]) for l in p.lights],
        shafts=[dict(top=list(s["top"]), bottom=list(s["bottom"])) for s in p.shafts],
    ) for p in pieces
}))
over = {f"{n}.{g}": t for n, r in report.items() for g, t in r["tris"].items() if t > 20000}
result = {"pieces": report, "over_limit": over, "objects": len(kit.objects)}
