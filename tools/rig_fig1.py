"""Rigs fig1/woman-model.glb (an unrigged, single-mesh figure) with Blender's automatic
(bone heat) weights and exports fig1/woman_rigged.glb for tools/build_fig1.gd.

Run from the project root (Blender 4.x or 5.x):
    blender -b --factory-startup -P tools/rig_fig1.py

The joint positions below were measured for this model: horizontal slices and front/side
projections of the mesh, scaled to 1.70 m with the soles on the floor, in glTF axes
(y up, she faces +z, her left is +x). She stands with her left foot forward and her left
leg angled out, and her arms hang close to her sides, so the joints are not mirrored.
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "fig1" / "woman-model.glb"
OUTPUT = ROOT / "fig1" / "woman_rigged.glb"
HEIGHT = 1.70

# Joint positions (metres, glTF axes, after scaling to HEIGHT with the soles at y = 0).
J = {
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


def to_blender(p):
    """glTF (x, y up, z forward) to Blender (x, -z, z up)."""
    return Vector((p[0], -p[2], p[1]))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE), merge_vertices=True)
    mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    bpy.context.view_layer.objects.active = mesh
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Scale to HEIGHT and stand the soles on the floor (only z is moved, as measured).
    zs = [v.co.z for v in mesh.data.vertices]
    scale = HEIGHT / (max(zs) - min(zs))
    mesh.scale = (scale, scale, scale)
    bpy.ops.object.transform_apply(scale=True)
    floor = min(v.co.z for v in mesh.data.vertices)
    mesh.location.z = -floor
    bpy.ops.object.transform_apply(location=True)
    mesh.name = "Body"
    # The generated mesh has a few degenerate faces; clean them up before binding.
    mesh.data.validate(clean_customdata=False)

    arm_data = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        b = arm_data.edit_bones.new(name)
        b.head = to_blender(J[head])
        b.tail = to_blender(J[tail])
        b.roll = 0.0
        if parent:
            b.parent = arm_data.edit_bones[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")

    # Bind with automatic (bone heat) weights.
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    # Bone heat misses a few small, isolated islands. A vertex with no weight would
    # collapse to the skeleton's origin in game, so give each one to its nearest bone.
    segments = [(b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm_data.bones]

    def nearest_bone(p):
        best, best_d = None, 1e9
        for name, a, b in segments:
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            d = (a + ab * t - p).length
            if d < best_d:
                best, best_d = name, d
        return best

    fixed = 0
    for v in mesh.data.vertices:
        if sum(g.weight for g in v.groups) < 1e-4:
            name = nearest_bone(mesh.matrix_world @ v.co)
            group = mesh.vertex_groups.get(name) or mesh.vertex_groups.new(name=name)
            group.add([v.index], 1.0, "REPLACE")
            fixed += 1
    print(f"RIG gave {fixed} unweighted vertices to their nearest bone")

    # Report coverage: every vertex should have weight from some bone.
    groups = {g.index: g.name for g in mesh.vertex_groups}
    counts = {name: 0 for name in groups.values()}
    unweighted = 0
    for v in mesh.data.vertices:
        total = sum(g.weight for g in v.groups)
        if total < 1e-4:
            unweighted += 1
        if v.groups:
            best = max(v.groups, key=lambda g: g.weight)
            counts[groups[best.group]] += 1
    print(f"RIG vertices {len(mesh.data.vertices)}, unweighted {unweighted}")
    for name, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"RIG   {name:16s} {n:6d}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        export_yup=True,
        export_skins=True,
        export_animations=False,
        export_morph=False,
        export_apply=False,
    )
    print(f"RIG wrote {OUTPUT}")


if __name__ == "__main__":
    main()
    sys.exit(0)
