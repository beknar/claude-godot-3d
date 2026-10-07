"""Rigs an unrigged, single-mesh figure with Blender's automatic (bone heat) weights and
exports a skinned glb for tools/build_figure.gd.

Run from the project root (Blender 4.x or 5.x), naming a figure from FIGURES:
    blender -b --factory-startup -P tools/rig_figure.py -- fig1
    blender -b --factory-startup -P tools/rig_figure.py -- fig2

Each figure's joint table was measured for that model: horizontal slices and front/side
projections of the mesh, scaled to 1.70 m with the soles on the floor, in glTF axes
(y up, she faces +z, her left is +x).
"""

import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
HEIGHT = 1.70

FIGURES = {
    # Standing with her left leg angled out and her arms close to her sides, so the
    # joints are not mirrored.
    "fig1": {
        "source": "fig1/woman-model.glb",
        "output": "fig1/woman_rigged.glb",
        "decimate_to": None,
        "detail": None,
        "arm_band": None,
        "hair": None,
        "skirt": None,
        "joints": {
            "Hips": (-0.05, 1.00, -0.005),
            "Spine": (-0.04, 1.12, -0.01),
            "Chest": (-0.03, 1.26, -0.01),
            "Neck": (-0.02, 1.45, -0.025),
            "Head": (-0.02, 1.52, -0.015),
            "HeadTop": (-0.02, 1.70, -0.01),
            "RightShoulder": (-0.04, 1.42, -0.03),
            "RightUpperArm": (-0.125, 1.405, -0.05),
            "RightLowerArm": (-0.163, 1.13, -0.09),
            "RightHand": (-0.195, 0.985, -0.065),
            "RightHandEnd": (-0.205, 0.85, -0.045),
            "LeftShoulder": (0.0, 1.42, -0.03),
            "LeftUpperArm": (0.09, 1.405, -0.045),
            "LeftLowerArm": (0.085, 1.13, -0.072),
            "LeftHand": (0.10, 0.985, -0.055),
            "LeftHandEnd": (0.085, 0.85, -0.04),
            "RightUpperLeg": (-0.135, 0.97, -0.005),
            "RightLowerLeg": (-0.145, 0.52, -0.045),
            "RightFoot": (-0.105, 0.13, -0.04),
            "RightToes": (-0.095, 0.025, 0.04),
            "RightToeEnd": (-0.095, 0.01, 0.08),
            "LeftUpperLeg": (0.005, 0.97, 0.01),
            "LeftLowerLeg": (0.10, 0.52, 0.002),
            "LeftFoot": (0.17, 0.13, 0.015),
            "LeftToes": (0.19, 0.025, 0.085),
            "LeftToeEnd": (0.195, 0.01, 0.125),
        },
    },
    # A symmetric T-pose in heels, 1.29 M triangles. Decimated for the game except the
    # face (`detail`: kept at full resolution). Her long hair hangs beside her upper arms,
    # so arm bones may only weight the slab the arms occupy (arm_band: y range and
    # minimum |x|). Her hanging hair and skirt get chains of spring bones (`hair`,
    # `skirt`), weighted geometrically (see chain_weights).
    "fig2": {
        "source": "fig2/source/fig2.glb",
        "output": "fig2/fig2_rigged.glb",
        "decimate_to": 190000,
        # Front of the head (centroid y, min z, max |x|): eyes, nose, mouth, bangs.
        "detail": (1.44, -0.01, 0.105),
        "arm_band": (1.30, 1.435, 0.16),
        # Points down each lock (glTF axes), from the scalp to the tip; parent Head.
        "hair": [
            [(0.0, 1.47, -0.11), (0.0, 1.37, -0.155), (0.0, 1.26, -0.15), (0.0, 1.14, -0.13)],
            [(0.075, 1.47, -0.10), (0.10, 1.37, -0.145), (0.12, 1.26, -0.14), (0.13, 1.14, -0.12)],
            [(-0.075, 1.47, -0.10), (-0.10, 1.37, -0.145), (-0.12, 1.26, -0.14), (-0.13, 1.14, -0.12)],
            [(0.10, 1.49, -0.04), (0.17, 1.39, -0.08), (0.20, 1.27, -0.07), (0.21, 1.14, -0.05)],
            [(-0.10, 1.49, -0.04), (-0.17, 1.39, -0.08), (-0.20, 1.27, -0.07), (-0.21, 1.14, -0.05)],
            [(0.09, 1.50, 0.03), (0.15, 1.40, 0.02), (0.19, 1.28, 0.02), (0.20, 1.16, 0.02)],
            [(-0.09, 1.50, 0.03), (-0.15, 1.40, 0.02), (-0.19, 1.28, 0.02), (-0.20, 1.16, 0.02)],
        ],
        # Hair weight fades in below `start_y` (full below `full_y`); the scalp stays on Head.
        "hair_fade": (1.475, 1.40),
        "hair_bottom": 1.05,
        # Skirt: chains around the hips from waist to hem; parent Hips. (count, rings of
        # (y, half-width x, half-depth z, centre z)).
        "skirt": (12, [(1.08, 0.15, 0.125, 0.01), (0.98, 0.20, 0.165, 0.015), (0.875, 0.245, 0.19, 0.015)]),
        "skirt_fade": (1.10, 1.04),
        # Bust: one spring bone per side from inside the chest out through the front
        # (her left first), weighted by a soft ellipsoid round each side (centre given
        # for her left; mirrored), so it bounces when she runs and lands.
        "bust": {
            # Two bones per side: Godot's SpringBoneSimulator3D won't simulate a
            # one-bone chain (it drops the extended end bone).
            "bones": [
                [(0.07, 1.29, 0.04), (0.073, 1.265, 0.10), (0.075, 1.24, 0.16)],
                [(-0.07, 1.29, 0.04), (-0.073, 1.265, 0.10), (-0.075, 1.24, 0.16)],
            ],
            "center": (0.075, 1.26, 0.12),
            "radii": (0.065, 0.08, 0.075),
        },
        "joints": {
            "Hips": (0.0, 0.93, 0.0),
            "Spine": (0.0, 1.05, -0.005),
            "Chest": (0.0, 1.21, -0.01),
            "Neck": (0.0, 1.44, -0.02),
            "Head": (0.0, 1.51, 0.0),
            "HeadTop": (0.0, 1.70, 0.02),
            "LeftShoulder": (0.04, 1.40, -0.035),
            "LeftUpperArm": (0.175, 1.375, -0.03),
            "LeftLowerArm": (0.39, 1.362, -0.02),
            "LeftHand": (0.575, 1.355, -0.012),
            "LeftHandEnd": (0.745, 1.355, -0.02),
            "RightShoulder": (-0.04, 1.40, -0.035),
            "RightUpperArm": (-0.175, 1.375, -0.03),
            "RightLowerArm": (-0.39, 1.362, -0.02),
            "RightHand": (-0.575, 1.355, -0.012),
            "RightHandEnd": (-0.745, 1.355, -0.02),
            "LeftUpperLeg": (0.085, 0.88, 0.0),
            "LeftLowerLeg": (0.075, 0.47, -0.012),
            "LeftFoot": (0.066, 0.155, -0.02),
            "LeftToes": (0.062, 0.03, 0.06),
            "LeftToeEnd": (0.062, 0.01, 0.1),
            "RightUpperLeg": (-0.085, 0.88, 0.0),
            "RightLowerLeg": (-0.075, 0.47, -0.012),
            "RightFoot": (-0.066, 0.155, -0.02),
            "RightToes": (-0.062, 0.03, 0.06),
            "RightToeEnd": (-0.062, 0.01, 0.1),
        },
    },
}

# bone: (head joint, tail joint, parent)
BONES = [
    ("Hips", "Hips", "Spine", None),
    ("Spine", "Spine", "Chest", "Hips"),
    ("Chest", "Chest", "Neck", "Spine"),
    ("Neck", "Neck", "Head", "Chest"),
    ("Head", "Head", "HeadTop", "Neck"),
]
for side in ("Left", "Right"):
    BONES += [
        (side + "Shoulder", side + "Shoulder", side + "UpperArm", "Chest"),
        (side + "UpperArm", side + "UpperArm", side + "LowerArm", side + "Shoulder"),
        (side + "LowerArm", side + "LowerArm", side + "Hand", side + "UpperArm"),
        (side + "Hand", side + "Hand", side + "HandEnd", side + "LowerArm"),
        (side + "UpperLeg", side + "UpperLeg", side + "LowerLeg", "Hips"),
        (side + "LowerLeg", side + "LowerLeg", side + "Foot", side + "UpperLeg"),
        (side + "Foot", side + "Foot", side + "Toes", side + "LowerLeg"),
        (side + "Toes", side + "Toes", side + "ToeEnd", side + "Foot"),
    ]
ARM_BONES = {s + b for s in ("Left", "Right") for b in ("UpperArm", "LowerArm", "Hand")}


def to_blender(p):
    """glTF (x, y up, z forward) to Blender (x, -z, z up)."""
    return Vector((p[0], -p[2], p[1]))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def gltf_positions(obj):
    """World-space vertex positions in glTF axes (x, y up, z forward), as an (n, 3) array."""
    me = obj.data
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3).astype(np.float64)
    return np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=1)


def vertex_colors(obj):
    """Base-colour texture sampled at each vertex (averaged over its face corners)."""
    me = obj.data
    image = None
    for mat in me.materials:
        if mat and mat.node_tree:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    linked = [l.to_socket.name for l in node.outputs["Color"].links]
                    if "Base Color" in linked or image is None:
                        image = node.image
    w, h = image.size
    pixels = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(h, w, 4)
    uv = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    loop_vert = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", loop_vert)
    px = np.clip(((uv[:, 0] % 1.0) * w).astype(int), 0, w - 1)
    py = np.clip(((uv[:, 1] % 1.0) * h).astype(int), 0, h - 1)
    col = np.zeros((len(me.vertices), 3))
    count = np.zeros(len(me.vertices))
    np.add.at(col, loop_vert, pixels[py, px, :3])
    np.add.at(count, loop_vert, 1.0)
    return col / np.maximum(count, 1.0)[:, None]


def chain_bones(cfg):
    """Spring-bone chains: [(bone name, head, tail, parent)] in glTF axes."""
    bones = []
    for c, points in enumerate(cfg.get("hair") or []):
        parent = "Head"
        for k in range(len(points) - 1):
            bone = f"Hair{c + 1}_{k + 1}"
            bones.append((bone, points[k], points[k + 1], parent))
            parent = bone
    for n, points in enumerate((cfg.get("bust") or {}).get("bones", [])):
        parent = "Chest"
        for k in range(len(points) - 1):
            bone = f"Breast{n + 1}_{k + 1}"
            bones.append((bone, points[k], points[k + 1], parent))
            parent = bone
    if cfg.get("skirt"):
        count, rings = cfg["skirt"]
        for i in range(count):
            a = 2.0 * math.pi * i / count
            pts = [(hx * math.sin(a), y, cz + hz * math.cos(a)) for y, hx, hz, cz in rings]
            parent = "Hips"
            for k in range(len(pts) - 1):
                bone = f"Skirt{i + 1}_{k + 1}"
                bones.append((bone, pts[k], pts[k + 1], parent))
                parent = bone
    return bones


def body_core(P):
    """Vertices on her body (torso, neck, arms in the T-pose) rather than hanging hair."""
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    neck = (y > 1.38) & (y < 1.50) & (np.hypot(x, z + 0.02) < 0.065)
    torso = (y > 0.90) & (y < 1.42) & (np.abs(x) < 0.15) & (z > -0.105) & (z < 0.18)
    # Arms, with room for the puffed off-shoulder sleeves near the shoulders.
    sleeve = np.where(np.abs(x) < 0.32, 0.085, 0.06)
    arms = (np.abs(x) > 0.12) & (y > 1.26) & (np.hypot(y - 1.36, z + 0.02) < sleeve)
    return neck | torso | arms


def chain_weights(obj, cfg, chains):
    """Hands hanging hair and the skirt to their spring-bone chains. Each affected
    vertex blends its body weights with the two nearest chain segments (inverse
    distance), fading in below the scalp / waistband so the roots stay attached."""
    P = gltf_positions(obj)
    col = vertex_colors(obj)
    lum = col @ np.array([0.299, 0.587, 0.114])
    red = (col[:, 0] > 0.35) & (col[:, 0] > 2.0 * col[:, 1]) & (col[:, 0] > 2.0 * col[:, 2])
    y = P[:, 1]
    jobs = []
    if cfg.get("hair"):
        start, full = cfg["hair_fade"]
        # Only down to the tips of her hair: her shoes and stocking tops are dark too.
        f = smoothstep(start, full, y) * ((lum < 0.5) & ~red & ~body_core(P) & (y > cfg["hair_bottom"]))
        jobs.append(("Hair", f))
    if cfg.get("skirt"):
        start, full = cfg["skirt_fade"]
        f = smoothstep(start, full, y) * (red & (y > 0.80))
        jobs.append(("Skirt", f))
    if cfg.get("bust"):
        c = np.array(cfg["bust"]["center"])
        r = np.array(cfg["bust"]["radii"])
        f = np.zeros(len(P))
        for side in (1.0, -1.0):
            d = np.linalg.norm((P - c * np.array([side, 1.0, 1.0])) / r, axis=1)
            f = np.maximum(f, smoothstep(1.0, 0.35, d))
        # Front of the chest only (not the back or the arms behind it).
        f *= (P[:, 2] > 0.06) & (np.abs(P[:, 0]) < 0.15)
        jobs.append(("Breast", f))
    groups = obj.vertex_groups
    for prefix, factor in jobs:
        segs = [(b, np.array(h), np.array(t)) for b, h, t, _ in chains if b.startswith(prefix)]
        idx = np.flatnonzero(factor > 0.01)
        Q = P[idx]
        dist = np.empty((len(idx), len(segs)))
        for s, (_, a, b) in enumerate(segs):
            ab = b - a
            t = np.clip(((Q - a) @ ab) / (ab @ ab), 0.0, 1.0)
            dist[:, s] = np.linalg.norm(a + t[:, None] * ab - Q, axis=1)
        nearest = np.argsort(dist, axis=1)[:, :2]
        for row, v in enumerate(idx.tolist()):
            f = float(factor[v])
            vert = obj.data.vertices[v]
            for g in list(vert.groups):
                groups[g.group].add([v], g.weight * (1.0 - f), "REPLACE")
            d = dist[row, nearest[row]]
            w = 1.0 / (d + 0.01) ** 2
            w /= w.sum()
            for s, ws in zip(nearest[row].tolist(), w.tolist()):
                name = segs[s][0]
                (groups.get(name) or groups.new(name=name)).add([v], f * float(ws), "ADD")
        print(f"RIG {prefix.lower()}: {len(idx)} vertices on {len(segs)} spring bones")


def detail_region(obj, cfg):
    """Vertices of faces inside the `detail` region (kept at full resolution)."""
    y0, z0, xmax = cfg["detail"]
    me = obj.data
    centers = np.empty(len(me.polygons) * 3, np.float32)
    me.polygons.foreach_get("center", centers)
    c = centers.reshape(-1, 3)
    cy, cz = c[:, 2], -c[:, 1]
    inside = (cy > y0) & (cz > z0) & (np.abs(c[:, 0]) < xmax)
    keep = np.zeros(len(me.vertices), bool)
    loop_total = np.empty(len(me.polygons), np.int32)
    me.polygons.foreach_get("loop_total", loop_total)
    loop_vert = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", loop_vert)
    poly_of_loop = np.repeat(np.arange(len(me.polygons)), loop_total)
    keep[loop_vert[inside[poly_of_loop]]] = True
    return keep, int(inside.sum())


def decimate(obj, target, protect=None):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, target / tris)
    if protect is not None:
        # Collapse cost rises steeply where the group weight is 0, so the protected
        # (ungrouped) vertices keep their triangles while the rest is reduced.
        group = obj.vertex_groups.new(name="_decimate")
        group.add([int(i) for i in np.flatnonzero(~protect)], 1.0, "REPLACE")
        mod.vertex_group = group.name
        mod.vertex_group_factor = 1000.0
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    if protect is not None:
        obj.vertex_groups.remove(obj.vertex_groups["_decimate"])
    print(f"RIG {obj.name}: decimated {tris} -> {sum(len(p.vertices) - 2 for p in obj.data.polygons)} triangles")


def rig(name, cfg):
    joints = cfg["joints"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / cfg["source"]), merge_vertices=True)
    mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Scale to HEIGHT and stand the soles on the floor (only z is moved, as measured).
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.scale = (scale, scale, scale)
    bpy.ops.object.transform_apply(scale=True)
    mesh.location.z = -min(v.co.z for v in mesh.data.vertices)
    bpy.ops.object.transform_apply(location=True)
    mesh.name = "Body"
    # Generated meshes have a few degenerate faces; clean them up before binding.
    mesh.data.validate(clean_customdata=False)

    # Bone heat struggles with dense meshes, so a figure with a full-resolution region
    # is weighted on a light proxy and the weights are transferred afterwards.
    target = mesh
    if cfg["detail"]:
        proxy = mesh.copy()
        proxy.data = mesh.data.copy()
        proxy.name = "WeightProxy"
        bpy.context.scene.collection.objects.link(proxy)
        decimate(proxy, 40000)
        keep, face_tris = detail_region(mesh, cfg)
        print(f"RIG detail region: {face_tris} triangles kept at full resolution")
        decimate(mesh, cfg["decimate_to"], keep)
        _, face_after = detail_region(mesh, cfg)
        print(f"RIG detail region after decimation: {face_after} triangles")
        target = proxy
    elif cfg["decimate_to"]:
        decimate(mesh, cfg["decimate_to"])

    chains = chain_bones(cfg)
    arm_data = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, head, tail, parent in BONES:
        b = arm_data.edit_bones.new(bone)
        b.head = to_blender(joints[head])
        b.tail = to_blender(joints[tail])
        b.roll = 0.0
        if parent:
            b.parent = arm_data.edit_bones[parent]
            b.use_connect = False
    for bone, head, tail, parent in chains:
        b = arm_data.edit_bones.new(bone)
        b.head = to_blender(head)
        b.tail = to_blender(tail)
        b.roll = 0.0
        b.parent = arm_data.edit_bones[parent]
        b.use_connect = False
        b.use_deform = False      # no bone heat: weighted geometrically below
    bpy.ops.object.mode_set(mode="OBJECT")

    # Bind with automatic (bone heat) weights.
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    body_bones = {b[0] for b in BONES}
    segments = [(b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local)
            for b in arm_data.bones if b.name in body_bones]

    def nearest_bone(p, exclude=()):
        best, best_d = None, 1e9
        for bone, a, b in segments:
            if bone in exclude:
                continue
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (a + ab * t - p).length
            if d < best_d:
                best, best_d = bone, d
        return best

    groups = {g.index: g for g in target.vertex_groups}

    # Keep arm bones off anything outside the arms' slab (hair hanging beside them).
    if cfg["arm_band"]:
        y0, y1, min_x = cfg["arm_band"]
        moved = 0
        for v in target.data.vertices:
            p = target.matrix_world @ v.co          # Blender: z up, -y forward
            inside = y0 <= p.z <= y1 and abs(p.x) >= min_x
            if inside:
                continue
            arm_weight = 0.0
            for g in list(v.groups):
                if groups[g.group].name in ARM_BONES and g.weight > 0.0:
                    arm_weight += g.weight
                    groups[g.group].remove([v.index])
            if arm_weight > 0.0:
                bone = nearest_bone(p, exclude=ARM_BONES)
                (target.vertex_groups.get(bone) or target.vertex_groups.new(name=bone)).add([v.index], arm_weight, "ADD")
                moved += 1
        print(f"RIG moved arm weight off {moved} vertices outside the arm band")

    # Bone heat misses a few small, isolated islands. A vertex with no weight would
    # collapse to the skeleton's origin in game, so give each one to its nearest bone.
    def fill_unweighted(obj):
        fixed = 0
        for v in obj.data.vertices:
            if sum(g.weight for g in v.groups) < 1e-4:
                bone = nearest_bone(obj.matrix_world @ v.co)
                (obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)).add([v.index], 1.0, "REPLACE")
                fixed += 1
        print(f"RIG gave {fixed} unweighted vertices of {obj.name} to their nearest bone")

    fill_unweighted(target)

    if target is not mesh:
        # Transfer the proxy's weights onto the detailed mesh, then drop the proxy.
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = mesh
        mesh.select_set(True)
        dt = mesh.modifiers.new("Weights", "DATA_TRANSFER")
        dt.object = target
        dt.use_vert_data = True
        dt.data_types_verts = {"VGROUP_WEIGHTS"}
        dt.vert_mapping = "POLYINTERP_NEAREST"
        dt.layers_vgroup_select_src = "ALL"
        dt.layers_vgroup_select_dst = "NAME"
        bpy.ops.object.datalayout_transfer(modifier=dt.name)
        bpy.ops.object.modifier_apply(modifier=dt.name)
        bpy.data.objects.remove(target, do_unlink=True)
        mesh.select_set(True)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.parent_set(type="ARMATURE")
        fill_unweighted(mesh)

    if chains:
        chain_weights(mesh, cfg, chains)
        for bone, _, _, _ in chains:
            arm_data.bones[bone].use_deform = True

    groups = {g.index: g.name for g in mesh.vertex_groups}
    counts = {}
    for v in mesh.data.vertices:
        if v.groups:
            best = max(v.groups, key=lambda g: g.weight)
            counts[groups[best.group]] = counts.get(groups[best.group], 0) + 1
    print(f"RIG {name}: {len(mesh.data.vertices)} vertices, {sum(len(p.vertices) - 2 for p in mesh.data.polygons)} triangles, {len(arm_data.bones)} bones")
    for bone, n in sorted(counts.items(), key=lambda kv: -kv[1])[:30]:
        print(f"RIG   {bone:16s} {n:6d}")

    out = ROOT / cfg["output"]
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_yup=True,
        export_skins=True,
        export_animations=False,
        export_morph=False,
        export_apply=False,
    )
    print(f"RIG wrote {out}")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args or args[0] not in FIGURES:
        print(f"usage: blender -b --factory-startup -P tools/rig_figure.py -- <{'|'.join(FIGURES)}>")
        sys.exit(1)
    rig(args[0], FIGURES[args[0]])
    sys.exit(0)
