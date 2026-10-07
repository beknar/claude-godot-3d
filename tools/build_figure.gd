extends SceneTree
## Builds an animated figure scene (e.g. fig2/fig2.tscn) from a glb that Blender
## skinned in tools/rig_figure.py. Rebuilds the skeleton in the project's convention
## (identity rest bases, facing -Z, her left at -X) so poses read the same as the
## cyborg's (tools/build_person.gd), and generates the animation library.
## Run from the project root (after the editor has imported the glb), naming a figure:
##     godot --headless --path . --script tools/build_figure.gd -- fig2
##
## Pose rotations are in the parent's axes: +X bends forward, Z swings sideways,
## Y twists; written for the left side and mirrored. The models were sculpted in
## their own stances (fig1 with a leg angled out, fig2 in a T-pose), so every pose
## starts from a computed neutral stance (legs straight under her, arms hanging) and
## animates on top of it. Ground clips are seated per keyframe so the lowest sole
## touches the floor: no floating, no sinking.

const DEG := PI / 180.0

## Per figure: source glb, outputs, and the directions its limbs are straightened to
## for the neutral stance (model space, left side; mirrored for the right). Bones not
## listed keep their rest direction relative to their parent.
const FIGURES := {
	"fig1": {
		"source": "res://fig1/woman_rigged.glb",
		"dir": "res://fig1/",
		"name": "Fig1",
		"scene": "fig1.tscn",
		"anims": "fig1_animations.tres",
		"material": "woman_material.tres",
		"neutral": {
			"UpperLeg": Vector3(-0.035, -1.0, 0.0),
			"LowerLeg": Vector3(-0.02, -1.0, 0.02),
			"UpperArm": Vector3(-0.16, -1.0, 0.02),
			"LowerArm": Vector3(-0.08, -1.0, -0.12),
		},
		# Her neutral arms already hang close to her body; the idle draws them in less.
		"idle_arm_in": 2.0,
	},
	"fig2": {
		"source": "res://fig2/fig2_rigged.glb",
		"dir": "res://fig2/",
		"name": "Fig2",
		"scene": "fig2.tscn",
		"anims": "fig2_animations.tres",
		"material": "fig2_material.tres",
		"neutral": {
			"UpperLeg": Vector3(-0.02, -1.0, 0.0),
			"LowerLeg": Vector3(-0.01, -1.0, 0.02),
			# T-pose arms down to her sides, clear of the flared skirt.
			"UpperArm": Vector3(-0.26, -1.0, 0.03),
			"LowerArm": Vector3(-0.12, -1.0, -0.12),
		},
		# Face shading: skin normals on the front of the head are blended toward an
		# ellipsoid round the head (model space), so the jaw and the area under the
		# nose stop facing the ground and shade evenly, as anime faces do. A dim light
		# that follows the head lights only her (render layer 2).
		"face": {
			"center": Vector3(0.0, 1.575, -0.02),
			"radii": Vector3(0.10, 0.13, 0.12),
			"blend": 0.7,
			"light_energy": 0.45,
		},
		# Spring bones (the chains tools/rig_figure.py added): per name prefix,
		# stiffness, drag, gravity, joint radius and whether it collides with the body.
		"springs": {
			"Hair": [2.2, 0.55, 0.25, 0.025, true],
			"Skirt": [3.0, 0.6, 0.15, 0.03, true],
			# Soft with very little drag: a lively bounce that settles in about a second,
			# without the steady backward lag that higher drag gives at a run (4.0 / 0.22
			# leaned ~-12° on average). Measured pitch: -25°..+11° running (mean -0.5°),
			# -29°..+11° on a jump. Its root sits inside the chest capsule, so it skips
			# collisions.
			"Breast": [3.0, 0.04, 0.0, 0.02, false],
		},
		# Capsules the springs collide with: [attached bone, from bone head, to bone
		# head, radius]. Both sides are added for "Left..." entries.
		"colliders": [
			["Spine", "Spine", "Chest", 0.105],
			["Chest", "Chest", "Neck", 0.115],
			["Neck", "Neck", "Head", 0.055],
			["LeftShoulder", "LeftShoulder", "LeftUpperArm", 0.055],
			["LeftUpperArm", "LeftUpperArm", "LeftLowerArm", 0.05],
			["LeftUpperLeg", "LeftUpperLeg", "LeftLowerLeg", 0.075],
		],
		"lods": true,
	},
}
## Clips seated on the floor keyframe by keyframe (the others use the standing height).
const GROUNDED := ["RESET", "idle", "walk", "run", "land"]

var cfg: Dictionary
var bone_names: Array[String] = []
var bone_parent: Array[int] = []
var bone_head: Array[Vector3] = []   # model-space rest positions (new convention)
var bone_tail: Array[Vector3] = []   # end of each bone (child head, or the glb's tail)
var neutral: Array[Quaternion] = []  # global (model-space) neutral-stance rotation per bone
var stand_lift := 0.0                # hips height change that seats the neutral stance
## Foot vertices (rest position, bones, weights) used to find the lowest sole.
var foot_verts := PackedVector3Array()
var foot_bones := PackedInt32Array()
var foot_weights := PackedFloat32Array()
var foot_per := 4


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not FIGURES.has(args[0]):
		push_error("usage: godot --headless --path . --script tools/build_figure.gd -- <%s>" % "|".join(FIGURES.keys()))
		quit(1)
		return
	cfg = FIGURES[args[0]]
	var src: Node = load(cfg.source).instantiate()
	root.add_child(src)
	var skel: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	# Skeleton space -> model space (the chain of local transforms up to the glb's root;
	# nothing is inside the tree yet during _initialize), then turn her to face -Z.
	var to_model := Transform3D.IDENTITY
	var node: Node = skel
	while node != src:
		if node is Node3D:
			to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	var turn := Basis(Vector3.UP, PI)

	for i in skel.get_bone_count():
		bone_names.append(skel.get_bone_name(i))
		bone_parent.append(skel.get_bone_parent(i))
		bone_head.append(turn * (to_model * skel.get_bone_global_rest(i).origin))
	for i in bone_names.size():
		var children := []
		for j in bone_names.size():
			if bone_parent[j] == i:
				children.append(j)
		if children.size() == 1:
			bone_tail.append(bone_head[children[0]])
		else:
			# End bones (and branching ones): extend along the glb bone's own Y axis.
			var rest := skel.get_bone_global_rest(i)
			var length := 0.12
			if bone_names[i] == "Hips":
				bone_tail.append(bone_head[bone_names.find("Spine")])
				continue
			bone_tail.append(turn * (to_model * (rest.origin + rest.basis.y.normalized() * length)))

	var mesh := rebuild_mesh(mi, skel, to_model, turn)
	compute_neutral()
	save_scene(mesh)
	quit()


# ---------------------------------------------------------------- mesh

func rebuild_mesh(mi: MeshInstance3D, skel: Skeleton3D, to_model: Transform3D, turn: Basis) -> ArrayMesh:
	var src_mesh: Mesh = mi.mesh
	var skin: Skin = mi.skin
	var bind_to_bone := PackedInt32Array()
	var bind_xform: Array[Transform3D] = []
	for k in skin.get_bind_count():
		var b := skin.get_bind_bone(k)
		if b < 0:
			b = skel.find_bone(skin.get_bind_name(k))
		bind_to_bone.append(b)
		bind_xform.append(skel.get_bone_global_rest(b) * skin.get_bind_pose(k))

	var out := ArrayMesh.new()
	for s in src_mesh.get_surface_count():
		var arrays := src_mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var new_bones := PackedInt32Array()
		new_bones.resize(bones.size())
		for v in verts.size():
			# Rest-pose position in model space: the weighted bind transforms agree at rest.
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			var total := 0.0
			for k in per:
				var w := weights[v * per + k]
				var bind := bones[v * per + k]
				new_bones[v * per + k] = bind_to_bone[bind]
				if w <= 0.0:
					continue
				p += bind_xform[bind] * verts[v] * w
				n += bind_xform[bind].basis * normals[v] * w
				total += w
			verts[v] = turn * (to_model * (p / maxf(total, 1e-6)))
			normals[v] = (turn * (to_model.basis * n)).normalized()
			if tangents is PackedFloat32Array and tangents.size() == verts.size() * 4:
				var t := Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2])
				var tb: Transform3D = bind_xform[bones[v * per]]
				t = (turn * (to_model.basis * (tb.basis * t))).normalized()
				tangents[v * 4] = t.x
				tangents[v * 4 + 1] = t.y
				tangents[v * 4 + 2] = t.z
		if cfg.has("face"):
			smooth_face(verts, normals, tangents, arrays[Mesh.ARRAY_TEX_UV], src_mesh.surface_get_material(s))
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_BONES] = new_bones
		# Keep the soles (everything near the floor) for seating the poses.
		foot_per = per
		for v in verts.size():
			if verts[v].y < 0.12:
				foot_verts.append(verts[v])
				for k in per:
					foot_bones.append(new_bones[v * per + k])
					foot_weights.append(weights[v * per + k])
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		var lods := {}
		if cfg.get("lods", false):
			# Simpler versions for when she's small on screen (the face is detailed).
			var im := ImporterMesh.new()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", flags)
			im.generate_lods(25.0, 60.0, [])
			arrays = im.get_surface_arrays(0)
			for l in im.get_surface_lod_count(0):
				lods[im.get_surface_lod_size(0, l)] = im.get_surface_lod_indices(0, l)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods, flags)
		var mat: Material = src_mesh.surface_get_material(s)
		if s == 0 and mat:
			mat = mat.duplicate()
			ResourceSaver.save(mat, cfg.dir + cfg.material, ResourceSaver.FLAG_CHANGE_PATH)
		out.surface_set_material(s, mat)
		var lod_sizes := []
		for l in lods:
			lod_sizes.append(lods[l].size() / 3)
		print("surface %d: %d triangles, LODs %s" % [s, arrays[Mesh.ARRAY_INDEX].size() / 3, str(lod_sizes)])
	print("mesh: %d surfaces, %d vertices (%d near the floor)" % [out.get_surface_count(), out.surface_get_array_len(0), foot_verts.size()])
	return out


## Blends the normals of the face's skin toward an ellipsoid round the head (see the
## figure's "face" settings). Only light, skin-coloured vertices on the front of the
## head change, fading out toward the ears and the neck; tangents are re-orthogonalized
## so the normal map still lines up.
func smooth_face(verts: PackedVector3Array, normals: PackedVector3Array, tangents: Variant,
		uvs: PackedVector2Array, mat: Material) -> void:
	var face: Dictionary = cfg.face
	var image := Image.load_from_file(ProjectSettings.globalize_path((mat as BaseMaterial3D).albedo_texture.resource_path))
	var w := image.get_width()
	var h := image.get_height()
	var c: Vector3 = face.center
	var r: Vector3 = face.radii
	var has_tangents: bool = tangents is PackedFloat32Array and tangents.size() == verts.size() * 4
	var changed := 0
	for v in verts.size():
		var p := verts[v]
		var d := (p - c) / r
		if p.z > 0.02 or p.y < 1.44 or d.length() > 1.6:
			continue
		var uv := uvs[v]
		var col := image.get_pixel(clampi(int(fposmod(uv.x, 1.0) * w), 0, w - 1), clampi(int(fposmod(uv.y, 1.0) * h), 0, h - 1))
		var skin := col.get_luminance() > 0.5 and not (col.r > 0.35 and col.r > 2.0 * col.g and col.r > 2.0 * col.b)
		if not skin:
			continue
		var amount: float = face.blend * smoothstep(0.02, -0.05, p.z) * smoothstep(1.44, 1.48, p.y)
		var round_normal := (d / r).normalized()   # gradient of the ellipsoid
		var n := normals[v].lerp(round_normal, amount).normalized()
		normals[v] = n
		if has_tangents:
			var t := Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2])
			t = (t - n * n.dot(t)).normalized()
			tangents[v * 4] = t.x
			tangents[v * 4 + 1] = t.y
			tangents[v * 4 + 2] = t.z
		changed += 1
	print("face: smoothed %d skin normals" % changed)


# ---------------------------------------------------------------- neutral stance

func b(bone_name: String) -> int:
	return bone_names.find(bone_name)


## Global rotations that straighten the limbs to the figure's neutral directions: for
## a listed bone, the shortest arc from its rest direction to its target; other bones
## inherit their parent's. Poses then act on this stance (see make_clip).
func compute_neutral() -> void:
	var dirs: Dictionary = cfg.neutral
	for i in bone_names.size():
		var parent := bone_parent[i]
		var want := neutral[parent] if parent >= 0 else Quaternion.IDENTITY
		for part in dirs:
			for side in [["Left", 1.0], ["Right", -1.0]]:
				if bone_names[i] == side[0] + part:
					var target: Vector3 = dirs[part]
					target.x *= side[1]
					var rest_dir := (bone_tail[i] - bone_head[i]).normalized()
					want = Quaternion(rest_dir, target.normalized())
		neutral.append(want.normalized())
	stand_lift = -lowest_sole(local_rotations({}), bone_head[0])
	print("neutral stance: hips offset %.3f" % stand_lift)


## Local bone rotations for a pose: N_parent^-1 * pose * N_bone (see make_clip).
func local_rotations(pose: Dictionary) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for i in bone_names.size():
		var q: Quaternion = pose.get(bone_names[i], Quaternion.IDENTITY)
		var parent_neutral := neutral[bone_parent[i]] if bone_parent[i] >= 0 else Quaternion.IDENTITY
		out.append((parent_neutral.inverse() * q * neutral[i]).normalized())
	return out


## Height of the lowest sole vertex with these local rotations and the hips at `hips`
## (identity rest bases: each bone's global basis is its chain of local rotations).
func lowest_sole(local: Array[Quaternion], hips: Vector3) -> float:
	var basis: Array[Basis] = []
	var origin: Array[Vector3] = []
	for i in bone_names.size():
		var parent := bone_parent[i]
		if parent < 0:
			basis.append(Basis(local[i]))
			origin.append(hips)
		else:
			basis.append(basis[parent] * Basis(local[i]))
			origin.append(origin[parent] + basis[parent] * (bone_head[i] - bone_head[parent]))
	var lowest := INF
	for v in foot_verts.size():
		var p := Vector3.ZERO
		for k in foot_per:
			var w := foot_weights[v * foot_per + k]
			if w > 0.0:
				var bi := foot_bones[v * foot_per + k]
				p += (origin[bi] + basis[bi] * (foot_verts[v] - bone_head[bi])) * w
		lowest = minf(lowest, p.y)
	return lowest


# ---------------------------------------------------------------- pose helpers

func e(x: float, y: float, z: float) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z) * DEG)


func mirror(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


func both(pose: Dictionary, bone: String, left: Quaternion, right: Variant = null) -> void:
	pose["Left" + bone] = left
	pose["Right" + bone] = mirror(left if right == null else right)


func bump(x: float, center: float, width: float) -> float:
	var d := fposmod(x - center + 0.5, 1.0) - 0.5
	return exp(-(d * d) / (width * width))


# ---------------------------------------------------------------- clips

## A relaxed contrapposto (an 8 s loop):
## - Weight is on her left leg: her pelvis shifts over that foot and that hip rises.
##   The standing knee stays soft, not locked. The resting right leg eases forward
##   and out with a bent knee. Both feet turn out a little.
## - Her shoulders tilt against her hips and her chest turns back toward the front.
## - The arms hang loose with bent elbows and the hands turned in toward the thighs:
##   the left one a little back by her hip, the right one a little forward.
## - Life without sway: two slow breaths per loop (chest, shoulders, elbows) and a gentle
##   drift of the head. The body never moves side to side.
func pose_idle(t: float) -> Dictionary:
	var breath := sin(2.0 * TAU * t)
	var drift := sin(TAU * t)
	var drift2 := sin(TAU * t + 1.7)
	var p := {}
	p["hips_offset"] = Vector3(-0.03, 0, 0.005)      # over the left (standing) foot
	p["Hips"] = e(1, 6, -5)
	p["Spine"] = e(0.4 * breath, -3, 3)
	p["Chest"] = e(-1.5 + 0.8 * breath, -3, 3)
	p["Neck"] = e(1 - 0.3 * breath, 1.5 * drift, -1)
	p["Head"] = e(3 + 1.0 * drift2, 5 + 2.5 * drift, -5 + 0.8 * drift2)
	# Left shoulder drops over the raised left hip; both rise a little on each breath.
	p["LeftShoulder"] = e(0, 0, 3 + 0.6 * breath)
	p["RightShoulder"] = mirror(e(0, 0, -1.5 + 0.6 * breath))
	# Arms: drawn in from the neutral stance's slight A-shape to hang at the edge of her
	# skirt, elbows bent, forearms turned so the palms face the thighs. The left hangs a
	# little back, by her hip; the right swings a little forward, by her thigh.
	var arm_in: float = cfg.get("idle_arm_in", 9.0)
	p["LeftUpperArm"] = e(-5, 8, arm_in)
	p["LeftLowerArm"] = e(12 + 1.5 * breath, 20, 0)
	p["LeftHand"] = e(6, 0, -8)
	# (A bigger elbow bend combines with the forearm twist and flips the hand palm-up,
	# so the asymmetry is in how far each arm swings, not how much it bends.)
	# (This model's right forearm needs the opposite twist to the left for the palm to
	# face the thigh; mirrored values flared the hand palm-out.)
	p["RightUpperArm"] = mirror(e(6, 8, arm_in + 1.0))
	p["RightLowerArm"] = mirror(e(15 + 1.5 * breath, -25, 0))
	p["RightHand"] = mirror(e(6, 0, 4))
	# Standing leg: under the shifted pelvis, knee soft, toes turned out.
	p["LeftUpperLeg"] = e(2, 7, 5)
	p["LeftLowerLeg"] = e(-5, 0, 0)
	p["LeftFoot"] = e(3, 0, -1)
	# Resting leg: forward and out, knee bent, turned out, weight on the ball of the foot.
	p["RightUpperLeg"] = mirror(e(15, 12, -8))
	p["RightLowerLeg"] = mirror(e(-30, 0, 0))
	p["RightFoot"] = mirror(e(14, 0, 2))
	return p


## Walking (run = 0) to running (run = 1). Left heel strikes at t = 0. In heels: a
## shorter stride with the feet placed near the midline and a swing of the hips.
func gait(p: Dictionary, t: float, run: float) -> void:
	var ph := TAU * t
	for side in [["Left", 0.0], ["Right", 0.5]]:
		var lt := fposmod(t + side[1], 1.0)
		var lph := TAU * lt
		var hip := lerpf(20.0, 40.0, run) * cos(lph) + lerpf(0.0, 10.0, run)
		var knee := -(lerpf(6.0, 12.0, run) + lerpf(12.0, 22.0, run) * bump(lt, 0.12, 0.07)
				+ lerpf(50.0, 100.0, run) * bump(lt, lerpf(0.72, 0.68, run), lerpf(0.12, 0.14, run)))
		var ankle := 6.0 * bump(lt, 0.0, 0.06) - lerpf(12.0, 22.0, run) * bump(lt, lerpf(0.55, 0.45, run), 0.07) \
				+ 6.0 * bump(lt, 0.8, 0.1)
		var cross := lerpf(3.0, 0.0, run)    # catwalk: feet land near the midline
		var arm := -lerpf(12.0, 38.0, run) * cos(lph + PI)
		var elbow := lerpf(12.0, 80.0, run) + lerpf(8.0, 12.0, run) * (0.5 + 0.5 * cos(lph + PI))
		var q_leg := e(hip, 0, cross)
		var q_knee := e(knee, 0, 0)
		var q_foot := e(ankle, 0, 0)
		var q_arm := e(arm + lerpf(0.0, 5.0, run), 0, -lerpf(3.0, 10.0, run))
		var q_elbow := e(elbow, 0, 0)
		if side[0] == "Left":
			p["LeftUpperLeg"] = q_leg
			p["LeftLowerLeg"] = q_knee
			p["LeftFoot"] = q_foot
			p["LeftUpperArm"] = q_arm
			p["LeftLowerArm"] = q_elbow
		else:
			p["RightUpperLeg"] = mirror(q_leg)
			p["RightLowerLeg"] = mirror(q_knee)
			p["RightFoot"] = mirror(q_foot)
			p["RightUpperArm"] = mirror(q_arm)
			p["RightLowerArm"] = mirror(q_elbow)
	var bob_phase := lerpf(0.0, 0.15, run)
	var bob := lerpf(0.015, 0.03, run)
	p["hips_offset"] = Vector3(0, -bob * (0.5 + 0.5 * cos(2.0 * (ph - TAU * bob_phase))) - lerpf(0.0, 0.03, run), 0)
	var yaw := lerpf(7.0, 8.0, run)
	var sway := lerpf(5.0, 2.0, run)       # hip drops on the swinging side
	p["Hips"] = e(0, -yaw * cos(ph), sway * sin(ph))
	p["Spine"] = e(-lerpf(1.0, 10.0, run), yaw * 0.5 * cos(ph), -sway * 0.6 * sin(ph))
	p["Chest"] = e(-lerpf(0.0, 5.0, run), yaw * 0.8 * cos(ph), -sway * 0.3 * sin(ph))
	p["Neck"] = e(lerpf(0.0, 5.0, run), 0, 0)
	p["Head"] = e(lerpf(-1.0, 8.0, run) + cos(2.0 * ph), -yaw * 0.6 * cos(ph), 0)


func pose_walk(t: float) -> Dictionary:
	var p := {}
	gait(p, t, 0.0)
	return p


func pose_run(t: float) -> Dictionary:
	var p := {}
	gait(p, t, 1.0)
	return p


## Rising: knees tucked, toes pointed, arms swung up and forward.
func pose_jump(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["Spine"] = e(-6, 0, 0)
	p["Head"] = e(6, 0, 0)
	p["LeftUpperLeg"] = e(48, 0, 2)
	p["LeftLowerLeg"] = e(-75, 0, 0)
	p["RightUpperLeg"] = mirror(e(25, 0, 2))
	p["RightLowerLeg"] = mirror(e(-45, 0, 0))
	both(p, "Foot", e(-20, 0, 0))
	both(p, "UpperArm", e(55 + 3 * sin(ph), 0, -35))
	both(p, "LowerArm", e(35, 0, 0))
	return p


## Falling: legs reaching down for the ground, arms out for balance.
func pose_fall(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["Spine"] = e(-3, 0, 0)
	p["Head"] = e(-8, 0, 0)
	p["LeftUpperLeg"] = e(18, 0, 3)
	p["LeftLowerLeg"] = e(-25, 0, 0)
	p["RightUpperLeg"] = mirror(e(6, 0, 3))
	p["RightLowerLeg"] = mirror(e(-12, 0, 0))
	both(p, "Foot", e(-8, 0, 0))
	both(p, "UpperArm", e(15, 0, -60 - 6 * sin(ph)))
	both(p, "LowerArm", e(20, 0, 0))
	return p


## Landing (one-shot): absorb the impact by crouching, then stand back up.
func pose_land(t: float) -> Dictionary:
	var dip := sin(PI * clampf(t / 0.9, 0.0, 1.0)) * (1.0 - smoothstep(0.6, 1.0, t))
	var p := {}
	p["hips_offset"] = Vector3(0, -0.13 * dip, 0)
	p["Spine"] = e(-14 * dip, 0, 0)
	p["Head"] = e(10 * dip, 0, 0)
	both(p, "UpperLeg", e(40 * dip, 0, 2))
	both(p, "LowerLeg", e(-70 * dip, 0, 0))
	both(p, "Foot", e(28 * dip, 0, 0))
	both(p, "UpperArm", e(25 * dip, 0, -20 * dip))
	both(p, "LowerArm", e(25 * dip, 0, 0))
	return p


## Samples `pose_fn(t)` into a clip keying every bone; a bone that holds still gets one
## key. Pose rotations act in the neutral stance's axes, as if her rest pose were
## already straight: with N the global neutral rotations, the animated global rotation
## is (pose chain) * N, so a bone's local rotation is N_parent^-1 * pose * N_bone.
## (Multiplying the local neutral instead would bend each joint about an axis twisted
## by the straightening, and the arms would no longer mirror.)
##
## Grounded clips are seated per keyframe: the hips are raised or lowered so that the
## lowest sole vertex is exactly on the floor (y = 0), which also replaces each pose's
## own vertical bob. Air clips keep the standing height plus their pose offset.
func make_clip(clip_name: String, length: float, keys: int, pose_fn: Callable, loop := true) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var samples := keys if loop else keys + 1
	var times := PackedFloat32Array()
	var locals: Array = []
	var hips := PackedVector3Array()
	var grounded := clip_name in GROUNDED
	var worst := 0.0
	for k in samples:
		var t := float(k) / keys
		times.append(t * length)
		var pose: Dictionary = pose_fn.call(t)
		var local := local_rotations(pose)
		var offset: Vector3 = pose.get("hips_offset", Vector3.ZERO)
		var h := bone_head[0] + offset + Vector3(0, stand_lift, 0)
		if grounded:
			h = bone_head[0] + Vector3(offset.x, 0.0, offset.z)
			var lowest := lowest_sole(local, h)
			h.y -= lowest
		worst = maxf(worst, absf(h.y - (bone_head[0].y + offset.y + stand_lift)))
		locals.append(local)
		hips.append(h)
	for i in bone_names.size():
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("Skeleton:" + bone_names[i]))
		var still := true
		for k in samples:
			still = still and locals[k][i].is_equal_approx(locals[0][i])
		for k in (1 if still else samples):
			anim.rotation_track_insert_key(tr, times[k], locals[k][i])
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("Skeleton:Hips"))
	for k in samples:
		anim.position_track_insert_key(pos_track, times[k], hips[k])
	if grounded:
		print("  %-6s seated on the floor (largest correction %.3f m)" % [clip_name, worst])
	return anim


func build_animations() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation("RESET", make_clip("RESET", 0.001, 1, func(_t: float) -> Dictionary: return {}, false))
	lib.add_animation("idle", make_clip("idle", 8.0, 64, pose_idle))
	lib.add_animation("walk", make_clip("walk", 1.0, 24, pose_walk))
	lib.add_animation("run", make_clip("run", 1.0, 24, pose_run))
	lib.add_animation("jump", make_clip("jump", 1.0, 8, pose_jump))
	lib.add_animation("fall", make_clip("fall", 1.2, 12, pose_fall))
	lib.add_animation("land", make_clip("land", 0.4, 12, pose_land, false))
	return lib


# ---------------------------------------------------------------- output

## A SpringBoneSimulator3D with one setting per chain (bones named Prefix<n>_<k>,
## k = 1 at the root), plus capsule colliders on the body. The chains lag behind her
## motion relative to the world, so hair and skirt swing as she walks, runs and turns.
func add_springs(skel: Skeleton3D, scene_root: Node) -> void:
	var sim := SpringBoneSimulator3D.new()
	sim.name = "SpringBones"
	skel.add_child(sim)
	sim.owner = scene_root
	var chains := []   # [prefix, first bone, last bone]
	for prefix in cfg.springs:
		var n := 1
		while b("%s%d_1" % [prefix, n]) >= 0:
			var k := 1
			while b("%s%d_%d" % [prefix, n, k + 1]) >= 0:
				k += 1
			chains.append([prefix, "%s%d_1" % [prefix, n], "%s%d_%d" % [prefix, n, k]])
			n += 1
	sim.setting_count = chains.size()
	for i in chains.size():
		var params: Array = cfg.springs[chains[i][0]]
		var last: int = b(chains[i][2])
		sim.set_root_bone_name(i, chains[i][1])
		sim.set_end_bone_name(i, chains[i][2])
		# The last bone also swings: extend it as long as its parent segment.
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		sim.set_end_bone_length(i, bone_head[last].distance_to(bone_head[bone_parent[last]]))
		sim.set_stiffness(i, params[0])
		sim.set_drag(i, params[1])
		sim.set_gravity(i, params[2])
		sim.set_radius(i, params[3])
		sim.set_enable_all_child_collisions(i, params[4])
	var colliders := []
	for entry in cfg.get("colliders", []):
		colliders.append(entry)
		if entry[0].begins_with("Left"):
			colliders.append(entry.map(func(x): return x.replace("Left", "Right") if x is String else x))
	for entry in colliders:
		var a := bone_head[b(entry[1])]
		var c := bone_head[b(entry[2])]
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = "Collide" + entry[0]
		capsule.bone_name = entry[0]
		capsule.radius = entry[3]
		capsule.height = a.distance_to(c) + 2.0 * entry[3]
		# Bone space is model space shifted to the bone's head (identity rest bases).
		capsule.position_offset = (a + c) * 0.5 - bone_head[b(entry[0])]
		capsule.rotation_offset = Quaternion(Vector3.UP, (c - a).normalized())
		sim.add_child(capsule)
		capsule.owner = scene_root
	print("springs: %d chains, %d colliders" % [chains.size(), colliders.size()])


func save_scene(mesh: ArrayMesh) -> void:
	var mesh_path: String = cfg.dir + "meshes/body.res"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mesh_path.get_base_dir()))
	var err := ResourceSaver.save(mesh, mesh_path, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "failed to save mesh")

	var scene_root := Node3D.new()
	scene_root.name = cfg.name
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	scene_root.add_child(skel)
	skel.owner = scene_root
	for i in bone_names.size():
		skel.add_bone(bone_names[i])
	for i in bone_names.size():
		var parent := bone_parent[i]
		skel.set_bone_parent(i, parent)
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, bone_head[i] - (bone_head[parent] if parent >= 0 else Vector3.ZERO)))
	skel.reset_bone_poses()

	var skin := Skin.new()
	for i in bone_names.size():
		skin.add_named_bind(bone_names[i], Transform3D(Basis.IDENTITY, -bone_head[i]))
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	body.skin = skin
	skel.add_child(body)
	body.owner = scene_root
	body.skeleton = NodePath("..")
	if cfg.has("springs"):
		add_springs(skel, scene_root)
	if cfg.has("face"):
		# The face light lights only render layer 2, which only her body is on.
		body.layers = 1 | 2
		var attach := BoneAttachment3D.new()
		attach.name = "HeadAttachment"
		attach.bone_name = "Head"
		skel.add_child(attach)
		attach.owner = scene_root
		var light := OmniLight3D.new()
		light.name = "FaceLight"
		var face_center: Vector3 = cfg.face.center
		# In front of her face and a little above it (bone space = model offsets).
		light.position = face_center - bone_head[b("Head")] + Vector3(0, 0.08, -0.45)
		light.light_color = Color(1.0, 0.93, 0.86)
		light.light_energy = cfg.face.light_energy
		light.light_specular = 0.0
		light.light_cull_mask = 2
		light.omni_range = 1.3
		light.omni_attenuation = 1.2
		attach.add_child(light)
		light.owner = scene_root

	var lib := build_animations()
	err = ResourceSaver.save(lib, cfg.dir + cfg.anims, ResourceSaver.FLAG_CHANGE_PATH)
	assert(err == OK, "failed to save animations")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	scene_root.add_child(player)
	player.owner = scene_root
	player.add_animation_library("", lib)

	var packed := PackedScene.new()
	packed.pack(scene_root)
	err = ResourceSaver.save(packed, cfg.dir + cfg.scene)
	assert(err == OK, "failed to save scene")
	print("saved %s (%d bones)" % [cfg.dir + cfg.scene, bone_names.size()])
	scene_root.free()
