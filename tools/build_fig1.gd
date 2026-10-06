extends SceneTree
## Builds the animated woman figure (fig1/fig1.tscn) from fig1/woman_rigged.glb, the
## mesh Blender skinned in tools/rig_fig1.py. Rebuilds the skeleton in the project's
## convention (identity rest bases, facing -Z, her left at -X) so poses read the same
## as the cyborg's (tools/build_person.gd), and generates the animation library.
## Run from the project root (after the editor or `--import` has imported the glb):
##     godot --headless --path . --script tools/build_fig1.gd
##
## Pose rotations are in the parent's axes: +X bends forward, Z swings sideways,
## Y twists; written for the left side and mirrored. The model was sculpted standing
## with her left leg angled out and arms close to her sides, so every pose starts
## from a computed neutral stance (legs straight under her, arms hanging) and
## animates on top of it.

const SOURCE := "res://fig1/woman_rigged.glb"
const OUT_SCENE := "res://fig1/fig1.tscn"
const OUT_MESH := "res://fig1/meshes/body.res"
const OUT_MATERIAL := "res://fig1/woman_material.tres"
const OUT_ANIMS := "res://fig1/fig1_animations.tres"
const DEG := PI / 180.0

## Directions the limbs are straightened to for the neutral stance (model space,
## left side; mirrored for the right). Bones not listed keep their rest direction
## relative to their parent.
const NEUTRAL_DIRS := {
	"UpperLeg": Vector3(-0.035, -1.0, 0.0),
	"LowerLeg": Vector3(-0.02, -1.0, 0.02),
	"UpperArm": Vector3(-0.16, -1.0, 0.02),
	"LowerArm": Vector3(-0.08, -1.0, -0.12),
}

var bone_names: Array[String] = []
var bone_parent: Array[int] = []
var bone_head: Array[Vector3] = []   # model-space rest positions (new convention)
var bone_tail: Array[Vector3] = []   # end of each bone (child head, or the glb's tail)
var neutral: Array[Quaternion] = []  # global (model-space) neutral-stance rotation per bone
var hips_drop := 0.0                 # how far the neutral stance lowers the hips


func _initialize() -> void:
	var src: Node = load(SOURCE).instantiate()
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
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_BONES] = new_bones
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		var mat: Material = src_mesh.surface_get_material(s)
		if s == 0 and mat:
			mat = mat.duplicate()
			ResourceSaver.save(mat, OUT_MATERIAL, ResourceSaver.FLAG_CHANGE_PATH)
		out.surface_set_material(s, mat)
	print("mesh: %d surfaces, %d vertices" % [out.get_surface_count(), out.surface_get_array_len(0)])
	return out


# ---------------------------------------------------------------- neutral stance

func b(bone_name: String) -> int:
	return bone_names.find(bone_name)


## Global rotations that straighten the limbs to NEUTRAL_DIRS: for a listed bone, the
## shortest arc from its rest direction to its target; other bones inherit their
## parent's. Poses then act on this stance (see make_clip).
func compute_neutral() -> void:
	var global_rot: Array[Quaternion] = []
	for i in bone_names.size():
		var parent := bone_parent[i]
		var parent_rot := global_rot[parent] if parent >= 0 else Quaternion.IDENTITY
		var want := parent_rot
		for part in NEUTRAL_DIRS:
			for side in [["Left", 1.0], ["Right", -1.0]]:
				if bone_names[i] == side[0] + part:
					var target: Vector3 = NEUTRAL_DIRS[part]
					target.x *= side[1]
					var rest_dir := (bone_tail[i] - bone_head[i]).normalized()
					want = Quaternion(rest_dir, target.normalized())
		global_rot.append(want)
		neutral.append(want.normalized())
	# Straightening the legs moves the soles; drop or raise the hips so they meet the floor.
	var lowest := INF
	for side in ["Left", "Right"]:
		var foot := fk_position(b(side + "Toes"), global_rot)
		lowest = minf(lowest, foot.y - 0.02)
	hips_drop = lowest
	print("neutral stance: hips offset %.3f" % -hips_drop)


## Position of bone i's head under the given global rotations (identity rest bases).
func fk_position(i: int, global_rot: Array[Quaternion]) -> Vector3:
	var parent := bone_parent[i]
	if parent < 0:
		return bone_head[i]
	return fk_position(parent, global_rot) + global_rot[parent] * (bone_head[i] - bone_head[parent])


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

func pose_idle(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["hips_offset"] = Vector3(0, -0.004 * (0.5 - 0.5 * cos(ph)), 0)
	p["Hips"] = e(0, 0, 1.5 * sin(ph))
	p["Spine"] = e(1.0 * sin(ph), 0, -1.0 * sin(ph))
	p["Chest"] = e(1.5 * sin(ph + 0.4), 0, 0)
	p["Head"] = e(2, 4 * sin(ph), -1.5 * sin(ph))
	both(p, "UpperArm", e(3, 0, -2 - sin(ph)))
	both(p, "LowerArm", e(10, 0, 0))
	p["LeftUpperLeg"] = e(1, 0, 1.5 * sin(ph))
	p["RightUpperLeg"] = mirror(e(1, 0, -1.5 * sin(ph)))
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
func make_clip(length: float, keys: int, pose_fn: Callable, loop := true) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var samples := keys if loop else keys + 1
	var times := PackedFloat32Array()
	var poses: Array[Dictionary] = []
	for k in samples:
		var t := float(k) / keys
		times.append(t * length)
		poses.append(pose_fn.call(t))
	for i in bone_names.size():
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("Skeleton:" + bone_names[i]))
		var values: Array[Quaternion] = []
		var still := true
		var parent_neutral := neutral[bone_parent[i]] if bone_parent[i] >= 0 else Quaternion.IDENTITY
		for pose in poses:
			var q: Quaternion = pose.get(bone_names[i], Quaternion.IDENTITY)
			values.append((parent_neutral.inverse() * q * neutral[i]).normalized())
			still = still and values[-1].is_equal_approx(values[0])
		for k in (1 if still else samples):
			anim.rotation_track_insert_key(tr, times[k], values[k])
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("Skeleton:Hips"))
	for k in samples:
		var offset: Vector3 = poses[k].get("hips_offset", Vector3.ZERO)
		anim.position_track_insert_key(pos_track, times[k], bone_head[0] + offset + Vector3(0, -hips_drop, 0))
	return anim


func build_animations() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation("RESET", make_clip(0.001, 1, func(_t: float) -> Dictionary: return {}, false))
	lib.add_animation("idle", make_clip(3.0, 24, pose_idle))
	lib.add_animation("walk", make_clip(1.0, 24, pose_walk))
	lib.add_animation("run", make_clip(1.0, 24, pose_run))
	lib.add_animation("jump", make_clip(1.0, 8, pose_jump))
	lib.add_animation("fall", make_clip(1.2, 12, pose_fall))
	lib.add_animation("land", make_clip(0.4, 12, pose_land, false))
	return lib


# ---------------------------------------------------------------- output

func save_scene(mesh: ArrayMesh) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_MESH.get_base_dir()))
	var err := ResourceSaver.save(mesh, OUT_MESH, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "failed to save mesh")

	var scene_root := Node3D.new()
	scene_root.name = "Fig1"
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

	var lib := build_animations()
	err = ResourceSaver.save(lib, OUT_ANIMS, ResourceSaver.FLAG_CHANGE_PATH)
	assert(err == OK, "failed to save animations")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	scene_root.add_child(player)
	player.owner = scene_root
	player.add_animation_library("", lib)

	var packed := PackedScene.new()
	packed.pack(scene_root)
	err = ResourceSaver.save(packed, OUT_SCENE)
	assert(err == OK, "failed to save scene")
	print("saved %s (%d bones)" % [OUT_SCENE, bone_names.size()])
	scene_root.free()
