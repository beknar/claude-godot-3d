extends SceneTree
## Builds the winged cyborg from the reference illustration: a skeleton, skinned
## meshes (body, hair, wings), the skin bindings and an animation library, saved as
## res://person/person.tscn plus person/meshes/*.res and person/person_animations.tres.
## Run from the project root:
##     godot --headless --path . --script tools/build_person.gd
##
## Conventions: metres; she stands on the origin facing -Z, so +X is her right and
## -X her left. Every bone's rest basis is the identity, so a pose rotation is a plain
## rotation in the parent's axes: +X bends a limb forward, Z swings it sideways,
## Y twists it. Poses are written for the left side and mirrored for the right.
## Most parts are rigid (one bone each) with ball joints at the articulations, as a
## mechanical body would be; only the torso undersuit blends between spine bones.

const MAT_DIR := "res://person/materials/"
const OUT_SCENE := "res://person/person.tscn"
const OUT_MESHES := "res://person/meshes/"
const OUT_ANIMS := "res://person/person_animations.tres"
const DEG := PI / 180.0

## Head-local frame: the skull ellipsoid's centre and half-axes (front and back depth
## differ). The head and hair are designed in these units, then scaled by HEAD_SCALE;
## the face UVs stay in design units, so skin.gdshader's feature positions hold.
const HEAD_CENTER := Vector3(0.0, 1.556, -0.006)
const HEAD_SCALE := 1.1
const HEAD_A := 0.083
const HEAD_B := 0.106
const HEAD_C_FRONT := 0.091
const HEAD_C_BACK := 0.099

var bone_names: Array[String] = []
var bone_parent: Array[int] = []
var bone_head: Array[Vector3] = []   # global rest positions
var groups := {}                     # mesh group -> {material name -> Surf}
var rng := RandomNumberGenerator.new()
## Left wing feathers: {label, seg, angle (rest, degrees from down), folded (degrees)}.
var feather_meta: Array[Dictionary] = []


class Surf:
	var material: Material
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()

	## bw: up to four [bone index, weight] pairs.
	func add(p: Vector3, n: Vector3, uv: Vector2, bw: Array, uv2 := Vector2.ZERO) -> int:
		verts.append(p)
		normals.append(n.normalized() if n.length() > 1e-9 else Vector3.UP)
		uvs.append(uv)
		uv2s.append(uv2)
		var total := 0.0
		for e in bw:
			total += e[1]
		for i in 4:
			if i < bw.size():
				bones.append(bw[i][0])
				weights.append(bw[i][1] / total)
			else:
				bones.append(0)
				weights.append(0.0)
		return verts.size() - 1

	## Adds a triangle facing `outward`. Godot's front faces wind clockwise, so the
	## geometric normal (b - a) x (c - a) must point away from the viewer.
	func tri(a: int, b: int, c: int, outward: Vector3) -> void:
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if n.length_squared() < 1e-16:
			return
		if n.dot(outward) > 0.0:
			indices.append_array([a, c, b])
		else:
			indices.append_array([a, b, c])


# ---------------------------------------------------------------- entry point

func _initialize() -> void:
	rng.seed = 1408
	build_skeleton()
	build_torso()
	build_neck_and_head()
	build_hair()
	for sx: float in [-1.0, 1.0]:
		build_arm(sx)
		build_leg(sx)
		build_wing(sx)
	save_scene()
	quit()


# ---------------------------------------------------------------- skeleton

func add_bone(bone_name: String, parent: String, head: Vector3) -> void:
	bone_names.append(bone_name)
	bone_parent.append(bone_names.find(parent) if parent != "" else -1)
	bone_head.append(head)


func b(bone_name: String) -> int:
	var i := bone_names.find(bone_name)
	assert(i >= 0, "unknown bone " + bone_name)
	return i


func side_name(sx: float) -> String:
	return "Left" if sx < 0.0 else "Right"


func build_skeleton() -> void:
	add_bone("Hips", "", Vector3(0, 0.93, 0))
	add_bone("Spine", "Hips", Vector3(0, 1.03, 0.005))
	add_bone("Chest", "Spine", Vector3(0, 1.17, 0.0))
	add_bone("Neck", "Chest", Vector3(0, 1.40, 0.012))
	add_bone("Head", "Neck", Vector3(0, 1.47, 0.0))
	for sx: float in [-1.0, 1.0]:
		var s := side_name(sx)
		add_bone(s + "Shoulder", "Chest", Vector3(sx * 0.03, 1.36, 0.0))
		add_bone(s + "UpperArm", s + "Shoulder", Vector3(sx * 0.175, 1.365, 0.01))
		add_bone(s + "LowerArm", s + "UpperArm", Vector3(sx * 0.205, 1.105, 0.02))
		add_bone(s + "Hand", s + "LowerArm", Vector3(sx * 0.225, 0.865, 0.0))
	for sx: float in [-1.0, 1.0]:
		var s := side_name(sx)
		add_bone(s + "UpperLeg", "Hips", Vector3(sx * 0.09, 0.90, 0.0))
		add_bone(s + "LowerLeg", s + "UpperLeg", Vector3(sx * 0.095, 0.50, 0.0))
		add_bone(s + "Foot", s + "LowerLeg", Vector3(sx * 0.098, 0.09, 0.02))
		add_bone(s + "Toes", s + "Foot", Vector3(sx * 0.10, 0.025, -0.10))
	for sx: float in [-1.0, 1.0]:
		var s := side_name(sx)
		var p := wing_points(sx)
		add_bone(s + "Wing1", "Chest", p[0])
		add_bone(s + "Wing2", s + "Wing1", p[1])
		add_bone(s + "Wing3", s + "Wing2", p[2])


## Wing frame joints: root on the back, wing elbow, wing wrist, tip.
func wing_points(sx: float) -> Array[Vector3]:
	return [
		Vector3(sx * 0.06, 1.28, 0.13),
		Vector3(sx * 0.58, 1.46, 0.20),
		Vector3(sx * 1.10, 1.56, 0.17),
		Vector3(sx * 1.62, 1.62, 0.20),
	]


# ---------------------------------------------------------------- mesh helpers

func surf(group: String, mat: String) -> Surf:
	if not groups.has(group):
		groups[group] = {}
	var g: Dictionary = groups[group]
	if not g.has(mat):
		var s := Surf.new()
		s.material = load(MAT_DIR + mat + ".tres")
		g[mat] = s
	return g[mat]


func rigid(bone_name: String) -> Array:
	return [[b(bone_name), 1.0]]


## Right-handed frame whose Y runs along `axis`, with Z as close to `z_hint` as possible.
func frame(axis: Vector3, z_hint := Vector3.BACK) -> Basis:
	var y := axis.normalized()
	if absf(y.dot(z_hint.normalized())) > 0.99:
		z_hint = Vector3.RIGHT
	var x := y.cross(z_hint).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func superellipse(s: float, power: float) -> float:
	return signf(s) * pow(absf(s), 2.0 / power)


## Angle on a ring (see ring_pts) that faces direction `dir`.
func ring_angle(f: Basis, dir: Vector3) -> float:
	return atan2(dir.dot(f.x), -dir.dot(f.z))


## Points around an axis. Angle 0 faces -f.z, +90 degrees faces +f.x. Closed rings
## have n points spread over the full turn; open arcs run from a0 to a1 inclusive.
## `keel` pushes the arc's middle outward (a ridge down the centre of a plate).
func ring_pts(c: Vector3, f: Basis, rx: float, rz: float, n: int, closed := true,
		a0 := -PI, a1 := PI, power := 2.0, keel := 0.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var mid := (a0 + a1) * 0.5
	var half := maxf(absf(a1 - a0) * 0.5, 1e-4)
	for i in n:
		var t := float(i) / n if closed else float(i) / (n - 1)
		var a := a0 + (a1 - a0) * t
		var dir := f.x * superellipse(sin(a), power) * rx - f.z * superellipse(cos(a), power) * rz
		var p := c + dir
		if keel != 0.0:
			var k := 1.0 - absf(a - mid) / half
			p += dir.normalized() * keel * k * k
		pts.append(p)
	return pts


## Builds a grid of rows into a surface. rows: Array of PackedVector3Array (equal
## lengths); bw_rows: per-row skin weights; centers: per-row axis points used to orient
## normals outward (or `hint`, a fixed outward direction, when non-zero). Smooth grids
## share vertices; faceted grids get one flat normal per quad. UVs default to metres
## (u around, v along); `uv_fn(r, j, p) -> Vector2` overrides them.
func grid(s: Surf, rows: Array, closed: bool, smooth: bool, bw_rows: Array, centers: Array,
		hint := Vector3.ZERO, uv_fn := Callable(), uv2_fn := Callable(), inward := false) -> void:
	var nr := rows.size()
	var m: int = rows[0].size()
	var cols := m + 1 if closed else m
	# Metric UVs: u = average arc length to each column, v = average distance between rows.
	var ucoord := PackedFloat32Array()
	ucoord.resize(cols)
	for j in range(1, cols):
		var acc := 0.0
		for r in nr:
			acc += (rows[r][j % m] - rows[r][j - 1]).length()
		ucoord[j] = ucoord[j - 1] + acc / nr
	var vcoord := PackedFloat32Array()
	vcoord.resize(nr)
	for r in range(1, nr):
		var acc := 0.0
		for j in m:
			acc += (rows[r][j] - rows[r - 1][j]).length()
		vcoord[r] = vcoord[r - 1] + acc / m

	var outward_of := func(r: int, p: Vector3) -> Vector3:
		var o: Vector3 = hint if hint != Vector3.ZERO else p - centers[r]
		if o.length_squared() < 1e-12:
			var r0 := maxi(r - 1, 0)
			var r1 := mini(r + 1, nr - 1)
			o = centers[r1] - centers[r0]
			if r == nr - 1:
				o = o
			elif r == 0:
				o = -o
		return -o if inward else o

	var uv_of := func(r: int, j: int, p: Vector3) -> Vector2:
		if uv_fn.is_valid():
			return uv_fn.call(r, j, p)
		return Vector2(ucoord[j], vcoord[r])

	var uv2_of := func(r: int, j: int, p: Vector3) -> Vector2:
		return uv2_fn.call(r, j, p) if uv2_fn.is_valid() else Vector2.ZERO

	if smooth:
		var idx := []
		for r in nr:
			var row_idx := PackedInt32Array()
			for j in cols:
				var jj := j % m
				var p: Vector3 = rows[r][jj]
				var jl := (jj - 1 + m) % m if closed else maxi(jj - 1, 0)
				var jr := (jj + 1) % m if closed else mini(jj + 1, m - 1)
				var tu: Vector3 = rows[r][jr] - rows[r][jl]
				var tv: Vector3 = rows[mini(r + 1, nr - 1)][jj] - rows[maxi(r - 1, 0)][jj]
				var n := tu.cross(tv)
				var o: Vector3 = outward_of.call(r, p)
				if n.length_squared() < 1e-14:
					n = o
				elif n.dot(o) < 0.0:
					n = -n
				row_idx.append(s.add(p, n, uv_of.call(r, j, p), bw_rows[r], uv2_of.call(r, j, p)))
			idx.append(row_idx)
		for r in nr - 1:
			for j in cols - 1:
				var a: int = idx[r][j]
				var bb: int = idx[r][j + 1]
				var c: int = idx[r + 1][j + 1]
				var d: int = idx[r + 1][j]
				var o: Vector3 = s.normals[a] + s.normals[bb] + s.normals[c] + s.normals[d]
				s.tri(a, bb, c, o)
				s.tri(a, c, d, o)
	else:
		for r in nr - 1:
			for j in cols - 1:
				var p0: Vector3 = rows[r][j % m]
				var p1: Vector3 = rows[r][(j + 1) % m]
				var p2: Vector3 = rows[r + 1][(j + 1) % m]
				var p3: Vector3 = rows[r + 1][j % m]
				var n := (p1 - p0).cross(p2 - p0) + (p2 - p0).cross(p3 - p0)
				var mid := (p0 + p1 + p2 + p3) * 0.25
				var o: Vector3 = outward_of.call(r, mid) + outward_of.call(r + 1, mid)
				if hint == Vector3.ZERO:
					o = (mid - (centers[r] + centers[r + 1]) * 0.5) * (-1.0 if inward else 1.0)
					if o.length_squared() < 1e-12:
						o = outward_of.call(r, mid)
				if n.length_squared() < 1e-16:
					continue
				if n.dot(o) < 0.0:
					n = -n
				var w0: Array = bw_rows[r]
				var w1: Array = bw_rows[r + 1]
				var a := s.add(p0, n, uv_of.call(r, j, p0), w0, uv2_of.call(r, j, p0))
				var bb := s.add(p1, n, uv_of.call(r, j + 1, p1), w0, uv2_of.call(r, j + 1, p1))
				var c := s.add(p2, n, uv_of.call(r + 1, j + 1, p2), w1, uv2_of.call(r + 1, j + 1, p2))
				var d := s.add(p3, n, uv_of.call(r + 1, j, p3), w1, uv2_of.call(r + 1, j, p3))
				s.tri(a, bb, c, n)
				s.tri(a, c, d, n)


## Closes a ring with a flat fan facing `outward`.
func cap(s: Surf, ring: PackedVector3Array, outward: Vector3, bw: Array) -> void:
	var center := Vector3.ZERO
	for p in ring:
		center += p
	center /= ring.size()
	var f := frame(outward)
	var ci := s.add(center, outward, Vector2.ZERO, bw)
	var ids := PackedInt32Array()
	for p in ring:
		var d := p - center
		ids.append(s.add(p, outward, Vector2(d.dot(f.x), d.dot(f.z)), bw))
	for i in ring.size():
		s.tri(ci, ids[i], ids[(i + 1) % ring.size()], outward)


func same(value: Variant, count: int) -> Array:
	var a := []
	for i in count:
		a.append(value)
	return a


## A tube along a polyline: stations are [point, rx, rz]; the ring frame follows the
## local direction with Z near `z_hint`.
func tube(s: Surf, stations: Array, n: int, bw: Array, smooth: bool, z_hint := Vector3.BACK,
		power := 2.0, cap_start := true, cap_end := true) -> void:
	var rows := []
	var centers := []
	var count := stations.size()
	for i in count:
		var p: Vector3 = stations[i][0]
		var prev: Vector3 = stations[maxi(i - 1, 0)][0]
		var next: Vector3 = stations[mini(i + 1, count - 1)][0]
		var f := frame(next - prev, z_hint)
		rows.append(ring_pts(p, f, stations[i][1], stations[i][2], n, true, -PI, PI, power))
		centers.append(p)
	var bws: Array = bw if bw.size() == count and bw[0] is Array and bw[0][0] is Array else same(bw, count)
	grid(s, rows, true, smooth, bws, centers)
	var axis: Vector3 = stations[count - 1][0] - stations[0][0]
	if cap_start and stations[0][1] > 1e-4:
		cap(s, rows[0], -axis.normalized(), bws[0])
	if cap_end and stations[count - 1][1] > 1e-4:
		cap(s, rows[count - 1], axis.normalized(), bws[count - 1])


func ellipsoid(s: Surf, c: Vector3, r: Vector3, nu: int, nv: int, bw: Array, smooth := true) -> void:
	var rows := []
	var centers := []
	for i in nv + 1:
		var el := -PI * 0.5 + PI * i / nv
		var row := PackedVector3Array()
		for j in nu:
			var az := TAU * j / nu
			row.append(c + Vector3(r.x * cos(el) * sin(az), r.y * sin(el), -r.z * cos(el) * cos(az)))
		rows.append(row)
		centers.append(c)
	grid(s, rows, true, smooth, same(bw, nv + 1), centers)


## A thick armour plate: `rows` are the outer surface (arcs around `centers`), the
## inner surface sits `thickness` further in, and flat rims close the edges.
func shell(s: Surf, rows: Array, centers: Array, thickness: float, bw: Array, closed := false) -> void:
	var nr := rows.size()
	var m: int = rows[0].size()
	var inner := []
	for r in nr:
		var row := PackedVector3Array()
		for j in m:
			var p: Vector3 = rows[r][j]
			var radial: Vector3 = p - centers[r]
			row.append(p - radial.normalized() * thickness)
		inner.append(row)
	var bws := same(bw, nr)
	grid(s, rows, closed, true, bws, centers)
	grid(s, inner, closed, true, bws, centers, Vector3.ZERO, Callable(), Callable(), true)
	# Rims along the first and last rows.
	for r in [0, nr - 1]:
		var away: Vector3 = centers[r] - centers[1 if r == 0 else nr - 2]
		var strip := [rows[r], inner[r]]
		_rim(s, strip, closed, away, bw)
	if not closed:
		for j in [0, m - 1]:
			var outer_col := PackedVector3Array()
			var inner_col := PackedVector3Array()
			for r in nr:
				outer_col.append(rows[r][j])
				inner_col.append(inner[r][j])
			var away: Vector3 = rows[nr / 2][j] - rows[nr / 2][1 if j == 0 else m - 2]
			_rim(s, [outer_col, inner_col], false, away, bw)


func _rim(s: Surf, strip: Array, closed: bool, away: Vector3, bw: Array) -> void:
	var a: PackedVector3Array = strip[0]
	var c: PackedVector3Array = strip[1]
	var m := a.size()
	var count := m if closed else m - 1
	for j in count:
		var j1 := (j + 1) % m
		var n := away.normalized()
		var i0 := s.add(a[j], n, Vector2(j * 0.02, 0.0), bw)
		var i1 := s.add(a[j1], n, Vector2(j1 * 0.02, 0.0), bw)
		var i2 := s.add(c[j1], n, Vector2(j1 * 0.02, 0.01), bw)
		var i3 := s.add(c[j], n, Vector2(j * 0.02, 0.01), bw)
		s.tri(i0, i1, i2, n)
		s.tri(i0, i2, i3, n)


func torus(s: Surf, c: Vector3, axis: Vector3, radius: float, tube_r: float, nu: int, nv: int, bw: Array) -> void:
	var f := frame(axis)
	var rows := []
	var centers := []
	for i in nu + 1:
		var a := TAU * i / nu
		var dir := f.x * sin(a) - f.z * cos(a)
		var center := c + dir * radius
		var row := PackedVector3Array()
		for j in nv:
			var t := TAU * j / nv
			row.append(center + dir * cos(t) * tube_r + f.y * sin(t) * tube_r)
		rows.append(row)
		centers.append(center)
	grid(s, rows, true, false, same(bw, nu + 1), centers)


# ---------------------------------------------------------------- torso

## Torso cross-sections: [y, half width, half depth, centre z].
const TORSO := [
	[0.80, 0.125, 0.085, 0.005],
	[0.85, 0.158, 0.098, 0.008],
	[0.91, 0.165, 0.102, 0.010],
	[0.97, 0.150, 0.095, 0.006],
	[1.03, 0.124, 0.083, 0.004],
	[1.09, 0.122, 0.082, 0.002],
	[1.15, 0.135, 0.090, 0.000],
	[1.21, 0.150, 0.098, -0.004],
	[1.27, 0.158, 0.100, -0.004],
	[1.32, 0.160, 0.094, 0.000],
	[1.36, 0.150, 0.080, 0.006],
	[1.39, 0.115, 0.060, 0.010],
	[1.41, 0.055, 0.045, 0.012],
]


## Interpolated torso section at height y: Vector3(half width, half depth, centre z).
func torso_at(y: float) -> Vector3:
	for i in TORSO.size() - 1:
		var a: Array = TORSO[i]
		var c: Array = TORSO[i + 1]
		if y <= c[0] or i == TORSO.size() - 2:
			var t := clampf((y - a[0]) / (c[0] - a[0]), 0.0, 1.0)
			return Vector3(lerpf(a[1], c[1], t), lerpf(a[2], c[2], t), lerpf(a[3], c[3], t))
	return Vector3.ZERO


func torso_weights(y: float) -> Array:
	if y <= 0.97:
		return rigid("Hips")
	if y < 1.06:
		var t := (y - 0.97) / 0.09
		return [[b("Hips"), 1.0 - t], [b("Spine"), t]]
	if y <= 1.13:
		return rigid("Spine")
	if y < 1.20:
		var t := (y - 1.13) / 0.07
		return [[b("Spine"), 1.0 - t], [b("Chest"), t]]
	return rigid("Chest")


## Rows of an armour arc following the torso: ys are heights, `grow` is how far it
## stands off the undersuit, a0..a1 the arc (0 = front, +90 = her right).
func torso_arc_rows(ys: Array, grow: float, a0: float, a1: float, n: int, keel := 0.0, flare := 0.0) -> Array:
	var rows := []
	var centers := []
	for i in ys.size():
		var y: float = ys[i]
		var t := torso_at(y)
		var extra := grow + flare * float(i) / maxf(ys.size() - 1, 1)
		var c := Vector3(0, y, t.z)
		rows.append(ring_pts(c, Basis.IDENTITY, t.x + extra, t.y + extra, n, false, a0, a1, 2.4, keel))
		centers.append(c)
	return [rows, centers]


func build_torso() -> void:
	var under := surf("body", "undersuit")
	var rows := []
	var centers := []
	var bws := []
	for sec in TORSO:
		var c := Vector3(0, sec[0], sec[3])
		rows.append(ring_pts(c, Basis.IDENTITY, sec[1], sec[2], 24, true, -PI, PI, 2.2))
		centers.append(c)
		bws.append(torso_weights(sec[0]))
	grid(under, rows, true, true, bws, centers)
	cap(under, rows[0], Vector3.DOWN, bws[0])
	cap(under, rows[rows.size() - 1], Vector3.UP, bws[bws.size() - 1])

	var blue := surf("body", "armor_blue")
	var dark := surf("body", "armor_dark")
	var bronze := surf("body", "bronze")
	# Breastplate with a centre ridge, and the back plate.
	var bp := torso_arc_rows([1.15, 1.20, 1.25, 1.30, 1.345], 0.018, -105 * DEG, 105 * DEG, 21, 0.010)
	shell(blue, bp[0], bp[1], 0.012, rigid("Chest"))
	var back := torso_arc_rows([1.14, 1.20, 1.26, 1.32, 1.37], 0.016, 112 * DEG, 248 * DEG, 15, 0.006)
	shell(blue, back[0], back[1], 0.012, rigid("Chest"))
	# Overlapping abdomen bands, each flaring at its lower edge like scales.
	for band in [[1.115, 1.155], [1.07, 1.115], [1.025, 1.07]]:
		var ab := torso_arc_rows([band[1], band[0]], 0.012, -100 * DEG, 100 * DEG, 17, 0.004, 0.008)
		shell(blue, ab[0], ab[1], 0.008, rigid("Spine"))
	# Belt and hip plates.
	var belt := torso_arc_rows([0.915, 0.86], 0.014, -PI, PI, 33)
	for r in belt[0].size():
		var ring: PackedVector3Array = belt[0][r]
		ring.remove_at(ring.size() - 1)   # closed ring: drop the duplicated end point
		belt[0][r] = ring
	shell(dark, belt[0], belt[1], 0.012, rigid("Hips"), true)
	for sx: float in [-1.0, 1.0]:
		var mid := 90.0 * sx
		var tas := torso_arc_rows([0.905, 0.86, 0.81], 0.026, (mid - 32) * DEG, (mid + 32) * DEG, 9, 0.0, 0.03)
		shell(blue, tas[0], tas[1], 0.01, rigid("Hips"))
	var rear := torso_arc_rows([0.905, 0.86, 0.80], 0.024, 140 * DEG, 220 * DEG, 9, 0.0, 0.02)
	shell(blue, rear[0], rear[1], 0.01, rigid("Hips"))

	# Chest core: bronze housing, ring and glowing centre.
	var core_y := 1.245
	var front_z := torso_at(core_y).z - torso_at(core_y).y - 0.018 - 0.010
	tube(bronze, [[Vector3(0, core_y, front_z + 0.012), 0.033, 0.033], [Vector3(0, core_y, front_z - 0.006), 0.031, 0.031]],
			12, rigid("Chest"), false, Vector3.UP)
	torus(bronze, Vector3(0, core_y, front_z - 0.002), Vector3.FORWARD, 0.045, 0.006, 16, 6, rigid("Chest"))
	tube(surf("body", "core_glow"), [[Vector3(0, core_y, front_z - 0.005), 0.016, 0.016], [Vector3(0, core_y, front_z - 0.010), 0.014, 0.014]],
			12, rigid("Chest"), false, Vector3.UP)
	# Bronze filigree: ribs sweeping up from the core toward the shoulders.
	for sx: float in [-1.0, 1.0]:
		var pts := []
		for k in 6:
			var t := k / 5.0
			var y := core_y + 0.03 + 0.085 * t
			var x := sx * (0.03 + 0.085 * t)
			var sec := torso_at(y)
			var ang := asin(clampf(x / (sec.x + 0.03), -1.0, 1.0))
			var z := sec.z - (sec.y + 0.026) * cos(ang)
			pts.append([Vector3(x, y, z), 0.005, 0.005])
		tube(bronze, pts, 6, rigid("Chest"), false)
	# Wing mounts on the back.
	for sx: float in [-1.0, 1.0]:
		var root := wing_points(sx)[0]
		tube(bronze, [[root + Vector3(0, 0, -0.05), 0.04, 0.032], [root + Vector3(0, 0, 0.0), 0.034, 0.028]],
				8, rigid("Chest"), false, Vector3.UP)


# ---------------------------------------------------------------- neck and head

func build_neck_and_head() -> void:
	var under := surf("body", "undersuit")
	tube(under, [[Vector3(0, 1.38, 0.012), 0.038, 0.036], [Vector3(0, 1.50, 0.0), 0.034, 0.032]],
			14, rigid("Neck"), true, Vector3.BACK, 2.0, false, false)
	var dark := surf("body", "armor_dark")
	for ring in [[1.395, 0.058, 0.018, "Chest"], [1.425, 0.051, 0.015, "Neck"], [1.452, 0.045, 0.012, "Neck"]]:
		var y: float = ring[0]
		tube(dark, [[Vector3(0, y - ring[2] * 0.5, 0.01), ring[1], ring[1] * 0.92], [Vector3(0, y + ring[2] * 0.5, 0.008), ring[1] * 0.95, ring[1] * 0.88]],
				12, rigid(ring[3]), false)
	var bronze := surf("body", "bronze")
	for sx: float in [-1.0, 1.0]:
		tube(bronze, [[Vector3(sx * 0.016, 1.40, -0.048), 0.0045, 0.0045], [Vector3(sx * 0.014, 1.44, -0.040), 0.0045, 0.0045],
				[Vector3(sx * 0.012, 1.47, -0.03), 0.004, 0.004]], 6, rigid("Neck"), false)

	# Head: a shaped ellipsoid. UV = rest head-local (x, y) for the painted face.
	var skin := surf("body", "skin")
	var rows := []
	var centers := []
	var nv := 32
	var nu := 48
	for i in nv + 1:
		var el := -PI * 0.5 + PI * i / nv
		var row := PackedVector3Array()
		for j in nu:
			var az := TAU * j / nu
			row.append(HEAD_CENTER + shape_head(el, az) * HEAD_SCALE)
		rows.append(row)
		centers.append(HEAD_CENTER)
	var face_uv := func(_r: int, _j: int, p: Vector3) -> Vector2:
		var l := (p - HEAD_CENTER) / HEAD_SCALE
		return Vector2(l.x, l.y)
	var face_uv2 := func(_r: int, _j: int, p: Vector3) -> Vector2:
		return Vector2((p.z - HEAD_CENTER.z) / HEAD_SCALE, 0.0)
	grid(skin, rows, true, true, same(rigid("Head"), nv + 1), centers, Vector3.ZERO, face_uv, face_uv2)


## Head surface point (head-local) at elevation `el` and azimuth `az` (0 = front).
func shape_head(el: float, az: float) -> Vector3:
	var c := HEAD_C_FRONT if cos(az) > 0.0 else HEAD_C_BACK
	var p := Vector3(HEAD_A * cos(el) * sin(az), HEAD_B * sin(el), -c * cos(el) * cos(az))
	# Jaw: narrows toward a small pointed chin, which sits slightly forward.
	if p.y < 0.0:
		var s := pow(clampf(-p.y / HEAD_B, 0.0, 1.0), 1.3)
		p.x *= lerpf(1.0, 0.5, s)
		if p.z < 0.0:
			p.z *= lerpf(1.0, 0.82, s)
		else:
			p.z *= lerpf(1.0, 0.6, s)
	# Cranium a little fuller at the back, temples slightly in.
	if p.y > 0.0 and p.z > 0.0:
		p.z *= 1.0 + 0.08 * (p.y / HEAD_B)
	# Nose: a small soft bump on the front.
	if p.z < 0.0:
		var nose := exp(-pow(p.x / 0.013, 2.0) - pow((p.y + 0.022) / 0.022, 2.0))
		p.z -= 0.007 * nose
	return p


# ---------------------------------------------------------------- hair

## Point on the hair volume around the skull (head-local), `out` metres outside it.
func sph(az: float, el: float, out := 0.012) -> Vector3:
	var c := HEAD_C_FRONT if cos(az) > 0.0 else HEAD_C_BACK + 0.01
	return Vector3((HEAD_A + out) * cos(el) * sin(az), (HEAD_B + out) * sin(el), -(c + out) * cos(el) * cos(az))


## Pushes a head-local point out of the skull ellipsoid grown by `margin`.
func push_out(p: Vector3, margin: float) -> Vector3:
	var c := (HEAD_C_FRONT if p.z < 0.0 else HEAD_C_BACK + 0.01) + margin
	var e := sqrt(pow(p.x / (HEAD_A + margin), 2.0) + pow(p.y / (HEAD_B + margin), 2.0) + pow(p.z / c, 2.0))
	return p / e if e < 1.0 and e > 1e-6 else p


func build_hair() -> void:
	var s := surf("hair", "hair")
	# Cap over the skull, its hairline high at the front and low at the nape.
	var rows := []
	var centers := []
	var n_rows := 12
	var nu := 32
	for i in n_rows + 1:
		var row := PackedVector3Array()
		for j in nu:
			var az := TAU * j / nu
			var low := lerpf(0.47, -0.62, (1.0 - cos(az)) * 0.5)
			var el := lerpf(PI * 0.5, low, float(i) / n_rows)
			row.append(HEAD_CENTER + sph(az, el, 0.008) * HEAD_SCALE)
		rows.append(row)
		centers.append(HEAD_CENTER)
	rows.reverse()
	grid(s, rows, true, true, same(rigid("Head"), n_rows + 1), centers)

	# Bangs: pointed locks over the forehead; the centre ones reach between the eyes.
	for i in 9:
		var f := float(i) / 8.0 * 2.0 - 1.0
		var az := f * 0.62
		var root := sph(az * 0.55, 1.02)
		var tip_x := sin(az) * HEAD_A * 1.02
		var tip_y := 0.018 + rng.randf_range(-0.004, 0.008)
		if absf(tip_x) < 0.012:
			tip_y = rng.randf_range(-0.016, -0.006)
		elif absf(tip_x) > 0.055:
			tip_y = rng.randf_range(-0.02, 0.0)
		var tip := Vector3(tip_x, tip_y, -HEAD_C_FRONT * cos(az) - 0.012)
		hair_lock(s, root, tip, Vector3(0, 0.015, -0.03), 0.034, 0.009, 0.014)
	# Face-framing side locks down to the jaw.
	for sx: float in [-1.0, 1.0]:
		for i in 4:
			var az: float = sx * lerpf(1.0, 1.75, i / 3.0)
			var root := sph(az, lerpf(0.75, 0.55, i / 3.0))
			var tip := Vector3(sx * (HEAD_A + 0.016 + 0.01 * i), rng.randf_range(-0.10, -0.075), lerpf(-0.045, 0.03, i / 3.0))
			hair_lock(s, root, tip, Vector3(sx * 0.02, 0.0, -0.01), 0.042, 0.011, 0.016)
		var cheek_root := sph(sx * 0.9, 0.85)
		hair_lock(s, cheek_root, Vector3(sx * 0.064, -0.088, -0.06), Vector3(sx * 0.02, 0.0, -0.02), 0.03, 0.008, 0.012)
	# Crown: chunky locks covering the top, sweeping forward and to the sides.
	for i in 9:
		var az := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var root := sph(az * 0.3, 1.42)
		var tip := sph(az, rng.randf_range(0.35, 0.65), 0.03)
		hair_lock(s, root, tip, Vector3(0, 0.025, 0), 0.06, 0.016, 0.02)
	# Back: shaggy locks to the nape, flaring outward at the ends.
	for i in 14:
		var az := lerpf(1.9, TAU - 1.9, i / 13.0) + rng.randf_range(-0.08, 0.08)
		var root := sph(az, rng.randf_range(0.9, 1.25))
		var tip := sph(az + rng.randf_range(-0.15, 0.15), rng.randf_range(-0.85, -0.55), 0.045)
		hair_lock(s, root, tip, Vector3(0, -0.01, 0.0), 0.055, 0.015, 0.022)
	# Windblown tufts flicking up and back, as in the illustration.
	for i in 5:
		var az := lerpf(2.4, TAU - 2.4, i / 4.0)
		var root := sph(az, 1.15)
		var tip := root + Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.03, 0.07), rng.randf_range(0.07, 0.11))
		hair_lock(s, root, tip, Vector3(0, 0.02, 0.0), 0.04, 0.012, 0.02)
	# Side spikes behind the ears.
	for sx: float in [-1.0, 1.0]:
		for i in 2:
			var root := sph(sx * (2.0 + 0.3 * i), 0.5)
			var tip := root + Vector3(sx * rng.randf_range(0.04, 0.07), rng.randf_range(-0.11, -0.07), rng.randf_range(0.02, 0.05))
			hair_lock(s, root, tip, Vector3(sx * 0.02, 0.0, 0.0), 0.04, 0.011, 0.02)


## One lock: a diamond-section blade along a quadratic curve from root to tip
## (head-local), kept `margin` outside the skull, tapering to a point.
func hair_lock(s: Surf, root: Vector3, tip: Vector3, bulge: Vector3, width: float, thick: float, margin: float) -> void:
	var segs := 7
	var ctrl := (root + tip) * 0.5 + bulge
	var path: Array[Vector3] = []
	for k in segs + 1:
		var t := float(k) / segs
		var c := (1.0 - t) * (1.0 - t) * root + 2.0 * t * (1.0 - t) * ctrl + t * t * tip
		path.append(push_out(c, lerpf(0.006, margin, smoothstep(0.0, 0.4, t))))
	var rows := []
	var centers := []
	var twist := rng.randf_range(-0.4, 0.4)
	for k in segs + 1:
		var t := float(k) / segs
		var c := path[k]
		var tangent := path[mini(k + 1, segs)] - path[maxi(k - 1, 0)]
		var outn := c.normalized()
		var side := tangent.cross(outn).normalized()
		side = side.rotated(tangent.normalized(), twist * t)
		var up := side.cross(tangent).normalized()
		if up.dot(outn) < 0.0:
			up = -up
		var w := width * pow(1.0 - t, 0.85) * (0.8 + 0.5 * sin(PI * t)) * 0.5 * HEAD_SCALE
		var th := thick * pow(1.0 - t, 0.6) * 0.5 * HEAD_SCALE
		var g := HEAD_CENTER + c * HEAD_SCALE
		rows.append(PackedVector3Array([g + side * w, g + up * th, g - side * w, g - up * th]))
		centers.append(g)
	var uv := func(r: int, j: int, _p: Vector3) -> Vector2:
		return Vector2(j / 4.0, float(r) / segs)
	grid(s, rows, true, true, same(rigid("Head"), segs + 1), centers, Vector3.ZERO, uv)


# ---------------------------------------------------------------- arms

func build_arm(sx: float) -> void:
	var sn := side_name(sx)
	var up_b := sn + "UpperArm"
	var lo_b := sn + "LowerArm"
	var hand_b := sn + "Hand"
	var shoulder := bone_head[b(up_b)]
	var elbow := bone_head[b(lo_b)]
	var wrist := bone_head[b(hand_b)]
	var knuckles := wrist + Vector3(sx * 0.007, -0.08, -0.002)
	var dark := surf("body", "armor_dark")
	var blue := surf("body", "armor_blue")
	var bronze := surf("body", "bronze")
	var outward := Vector3(sx, 0, 0)

	ellipsoid(dark, shoulder, Vector3.ONE * 0.045, 12, 8, rigid(up_b))
	var ua := (elbow - shoulder).normalized()
	tube(dark, [[shoulder + ua * 0.03, 0.038, 0.038], [elbow - ua * 0.03, 0.032, 0.032]], 12, rigid(up_b), true)
	torus(blue, shoulder + ua * 0.17, ua, 0.037, 0.006, 16, 6, rigid(up_b))
	# Pauldron: a rounded dome over the shoulder.
	var f := frame(ua)
	var ang := ring_angle(f, outward + Vector3(0, 0.2, 0))
	var p_rows := []
	var p_centers := []
	var prof := [[-0.058, 0.006], [-0.046, 0.036], [-0.02, 0.055], [0.02, 0.064], [0.065, 0.064], [0.105, 0.06]]
	for pr in prof:
		var c: Vector3 = shoulder + ua * pr[0]
		p_rows.append(ring_pts(c, f, pr[1], pr[1], 17, false, ang - 115 * DEG, ang + 115 * DEG, 2.0, 0.005))
		p_centers.append(c)
	shell(blue, p_rows, p_centers, 0.008, rigid(up_b))

	ellipsoid(dark, elbow, Vector3.ONE * 0.035, 12, 8, rigid(lo_b))
	var fa := (wrist - elbow).normalized()
	tube(dark, [[elbow + fa * 0.025, 0.032, 0.032], [wrist - fa * 0.02, 0.026, 0.026]], 12, rigid(lo_b), true)
	# Vambrace along the outer forearm.
	var ff := frame(fa)
	var vang := ring_angle(ff, outward + Vector3(0, 0, 0.5))
	var v_rows := []
	var v_centers := []
	for k in 5:
		var t := k / 4.0
		var c := elbow.lerp(wrist, lerpf(0.12, 0.88, t))
		var r := lerpf(0.046, 0.038, t)
		v_rows.append(ring_pts(c, ff, r, r, 13, false, vang - 100 * DEG, vang + 100 * DEG, 2.0, 0.008))
		v_centers.append(c)
	shell(blue, v_rows, v_centers, 0.008, rigid(lo_b))
	tube(bronze, [[wrist - fa * 0.035, 0.032, 0.032], [wrist - fa * 0.012, 0.031, 0.031]], 10, rigid(lo_b), false)

	# Hand: a slim palm and long clawed fingers curling toward the palm.
	var inward := -sx
	tube(dark, [[wrist + Vector3(0, 0.005, 0), 0.013, 0.034], [wrist.lerp(knuckles, 0.6), 0.015, 0.042], [knuckles, 0.013, 0.040]],
			8, rigid(hand_b), false, Vector3.BACK, 2.6)
	for i in 4:
		var z := lerpf(-0.03, 0.03, i / 3.0)
		var length: float = [0.95, 1.05, 1.0, 0.85][i]
		var p0 := knuckles + Vector3(0, 0.004, z)
		var p1 := p0 + Vector3(inward * 0.002, -0.034, -0.002) * length
		var p2 := p1 + Vector3(inward * 0.009, -0.03, -0.003) * length
		var p3 := p2 + Vector3(inward * 0.017, -0.03, -0.004) * length
		tube(dark, [[p0, 0.0075, 0.0075], [p1, 0.0068, 0.0068], [p2, 0.0058, 0.0058], [p3, 0.0, 0.0]], 6, rigid(hand_b), false)
		ellipsoid(bronze, p1, Vector3.ONE * 0.008, 6, 4, rigid(hand_b), false)
	var t0 := wrist + Vector3(inward * 0.012, -0.03, -0.034)
	var t1 := t0 + Vector3(inward * 0.008, -0.026, -0.02)
	var t2 := t1 + Vector3(inward * 0.014, -0.024, -0.012)
	tube(dark, [[t0, 0.008, 0.008], [t1, 0.007, 0.007], [t2, 0.0, 0.0]], 6, rigid(hand_b), false)


# ---------------------------------------------------------------- legs

func build_leg(sx: float) -> void:
	var sn := side_name(sx)
	var up_b := sn + "UpperLeg"
	var lo_b := sn + "LowerLeg"
	var foot_b := sn + "Foot"
	var toe_b := sn + "Toes"
	var hip := bone_head[b(up_b)]
	var knee := bone_head[b(lo_b)]
	var ankle := bone_head[b(foot_b)]
	var x := hip.x
	var under := surf("body", "undersuit")
	var dark := surf("body", "armor_dark")
	var blue := surf("body", "armor_blue")

	tube(under, [[hip + Vector3(0, 0.02, 0), 0.080, 0.080], [Vector3(x, 0.80, 0.002), 0.078, 0.076], [Vector3(x * 1.02, 0.62, 0.004), 0.062, 0.06],
			[knee + Vector3(0, 0.02, 0), 0.052, 0.052]], 16, rigid(up_b), true)
	# Thigh plate over the front and outside.
	var front_out := Vector3(sx * 0.7, 0, -1).normalized()
	var t_rows := []
	var t_centers := []
	for y in [0.85, 0.77, 0.69, 0.61]:
		var r := lerpf(0.052, 0.08, (y - 0.5) / 0.4) + 0.016
		var c := Vector3(lerpf(knee.x, hip.x, (y - 0.5) / 0.4), y, 0.003)
		var a := ring_angle(Basis.IDENTITY, front_out)
		t_rows.append(ring_pts(c, Basis.IDENTITY, r, r, 15, false, a - 82 * DEG, a + 82 * DEG, 2.0, 0.006))
		t_centers.append(c)
	shell(blue, t_rows, t_centers, 0.012, rigid(up_b))

	ellipsoid(dark, knee, Vector3(0.05, 0.05, 0.05), 12, 8, rigid(lo_b))
	# Pointed knee guard.
	var k_rows := []
	var k_centers := []
	for kp in [[0.585, 0.052, 0.0], [0.545, 0.066, 0.02], [0.50, 0.064, 0.012], [0.455, 0.054, 0.0]]:
		var c := Vector3(knee.x, kp[0], 0.0)
		k_rows.append(ring_pts(c, Basis.IDENTITY, kp[1], kp[1], 13, false, -68 * DEG, 68 * DEG, 2.0, kp[2]))
		k_centers.append(c)
	shell(blue, k_rows, k_centers, 0.01, rigid(lo_b))
	tube(under, [[knee + Vector3(0, -0.02, 0), 0.050, 0.052], [Vector3(knee.x, 0.36, 0.008), 0.050, 0.058], [Vector3(ankle.x, 0.17, 0.012), 0.036, 0.04],
			[ankle + Vector3(0, 0.03, 0), 0.034, 0.036]], 14, rigid(lo_b), true)
	# Shin guard (front) and calf plate (back).
	var s_rows := []
	var s_centers := []
	for k in 5:
		var y := lerpf(0.45, 0.13, k / 4.0)
		var c := Vector3(lerpf(knee.x, ankle.x, (0.5 - y) / 0.41), y, lerpf(0.0, 0.012, (0.5 - y) / 0.41))
		var r := lerpf(0.05, 0.036, (0.5 - y) / 0.41) + 0.014
		s_rows.append(ring_pts(c, Basis.IDENTITY, r, r * 1.05, 13, false, -80 * DEG, 80 * DEG, 2.0, 0.012))
		s_centers.append(c)
	shell(blue, s_rows, s_centers, 0.01, rigid(lo_b))
	var c_rows := []
	var c_centers := []
	for y in [0.43, 0.36, 0.29, 0.24]:
		var c := Vector3(knee.x, y, 0.008)
		var r := 0.064 if y > 0.3 else 0.052
		c_rows.append(ring_pts(c, Basis.IDENTITY, r, r, 11, false, 140 * DEG, 220 * DEG, 2.0, 0.0))
		c_centers.append(c)
	shell(dark, c_rows, c_centers, 0.008, rigid(lo_b))

	ellipsoid(dark, ankle, Vector3.ONE * 0.038, 10, 8, rigid(foot_b))
	# Boot: heel to ball on the foot bone, pointed toe cap on the toes bone.
	var boot := [[0.07, 0.065, 0.032, 0.045], [0.035, 0.08, 0.044, 0.07], [-0.01, 0.065, 0.047, 0.055], [-0.06, 0.045, 0.046, 0.037], [-0.10, 0.037, 0.044, 0.03]]
	var stations := []
	for st in boot:
		stations.append([Vector3(x * 1.08, st[1], st[0]), st[2], st[3]])
	tube(blue, stations, 12, rigid(foot_b), true, Vector3.UP, 3.0)
	tube(blue, [[Vector3(x * 1.08, 0.037, -0.10), 0.044, 0.03], [Vector3(x * 1.1, 0.03, -0.15), 0.03, 0.022], [Vector3(x * 1.1, 0.022, -0.195), 0.0, 0.0]],
			12, rigid(toe_b), true, Vector3.UP, 3.0, false, false)


# ---------------------------------------------------------------- wings

func build_wing(sx: float) -> void:
	var sn := side_name(sx)
	var w1 := sn + "Wing1"
	var w2 := sn + "Wing2"
	var w3 := sn + "Wing3"
	var p := wing_points(sx)
	var dark := surf("wings", "armor_dark")
	var blue := surf("wings", "armor_blue")
	var fe := surf("wings", "feather")

	ellipsoid(dark, p[0], Vector3.ONE * 0.042, 12, 8, rigid(w1))
	tube(dark, [[p[0], 0.032, 0.03], [p[1], 0.026, 0.024]], 12, rigid(w1), true, Vector3.UP)
	ellipsoid(dark, p[1], Vector3.ONE * 0.036, 12, 8, rigid(w2))
	tube(dark, [[p[1], 0.026, 0.024], [p[2], 0.02, 0.019]], 12, rigid(w2), true, Vector3.UP)
	ellipsoid(dark, p[2], Vector3.ONE * 0.03, 12, 8, rigid(w3))
	tube(dark, [[p[2], 0.02, 0.019], [p[3], 0.004, 0.004]], 12, rigid(w3), true, Vector3.UP, 2.0, true, false)
	# Armoured leading edge over the inner wing, with a blue stripe.
	var axis := (p[1] - p[0]).normalized()
	var f := frame(axis, Vector3.BACK)
	var a := ring_angle(f, Vector3(0, 1, 0.4))
	var rows := []
	var centers := []
	for k in 4:
		var c := p[0].lerp(p[1], lerpf(0.12, 0.95, k / 3.0))
		var r := lerpf(0.042, 0.034, k / 3.0)
		rows.append(ring_pts(c, f, r, r, 11, false, a - 95 * DEG, a + 95 * DEG, 2.0, 0.01))
		centers.append(c)
	shell(dark, rows, centers, 0.008, rigid(w1))
	torus(blue, p[0].lerp(p[1], 0.08), axis, 0.036, 0.005, 14, 5, rigid(w1))
	torus(blue, p[1].lerp(p[2], 0.06), (p[2] - p[1]).normalized(), 0.03, 0.005, 14, 5, rigid(w2))

	# Feathers hang from the frame (in the rest pose the wing plane is vertical, behind
	# her back, with the feathers pointing down; in flight she pitches forward and
	# they trail behind). Angle 0 = straight down, positive = toward the wing tip.
	# Each feather has its own bone at its root, so folding can turn it independently;
	# the last argument is its angle once the wings are folded (see fold_wings).
	var normal := Vector3.BACK
	var covert := 0
	# Primaries on the hand.
	for i in 9:
		var t := i / 8.0
		var root := p[2].lerp(p[3], t * 0.92) + normal * (0.004 * i)
		var ang := lerpf(12.0, 78.0, pow(t, 1.2))
		var length := 0.72 + 0.24 * sin(PI * (0.25 + 0.6 * t))
		wing_feather(fe, sx, "Primary%d" % (i + 1), 2, root, ang, length, 0.13, normal, lerpf(2.0, 10.0, t))
	# Secondaries on the forearm.
	for i in 8:
		var t := i / 7.0
		var root := p[1].lerp(p[2], t) + normal * (0.002 + 0.003 * i) + Vector3(0, -0.01, 0)
		wing_feather(fe, sx, "Secondary%d" % (i + 1), 1, root, lerpf(-4.0, 9.0, t), lerpf(0.6, 0.7, t), 0.12, normal, lerpf(-4.0, 4.0, t))
	# Tertials on the upper arm, angling in toward her body.
	for i in 6:
		var t := lerpf(0.18, 1.0, i / 5.0)
		var root := p[0].lerp(p[1], t) + normal * (0.003 * i) + Vector3(0, -0.012, 0)
		wing_feather(fe, sx, "Tertial%d" % (i + 1), 0, root, lerpf(-26.0, -6.0, t), lerpf(0.4, 0.56, t), 0.11, normal, lerpf(-12.0, -5.0, t))
	# Two rows of coverts layered over the feather roots.
	for row in 2:
		var out := 0.018 + 0.012 * row
		var length := 0.3 if row == 0 else 0.17
		var spacing := 0.085 if row == 0 else 0.065
		for seg in 3:
			var a0 := p[seg]
			var a1 := p[seg + 1]
			var seg_len := a0.distance_to(a1)
			var count := maxi(2, int(seg_len / spacing))
			for i in count:
				var t := (i + 0.5) / count
				if seg == 0 and t < 0.15:
					continue
				var root := a0.lerp(a1, t) + normal * (out + 0.002 * i) + Vector3(0, 0.012 + 0.012 * row, 0)
				var ang: float = [lerpf(-18.0, -4.0, t), lerpf(-3.0, 9.0, t), lerpf(14.0, 60.0, t)][seg]
				var folded: float = [lerpf(-10.0, -4.0, t), lerpf(-4.0, 2.0, t), lerpf(2.0, 9.0, t)][seg]
				covert += 1
				wing_feather(fe, sx, "Covert%d" % covert, seg, root, ang, length * (0.85 if seg == 2 and t > 0.7 else 1.0),
						0.1 if row == 0 else 0.085, normal, folded)


## A feather on its own bone, parented to wing segment `seg` (0 upper arm, 1 forearm,
## 2 hand). The left wing records each feather's rest and folded angles for the poses.
func wing_feather(s: Surf, sx: float, label: String, seg: int, root: Vector3, angle_deg: float, length: float,
		width: float, normal: Vector3, folded_deg: float) -> void:
	var sn := side_name(sx)
	add_bone(sn + label, sn + "Wing%d" % (seg + 1), root)
	if sx < 0.0:
		feather_meta.append({"label": label, "seg": seg, "angle": angle_deg, "folded": folded_deg})
	feather(s, sx, root, angle_deg, length, width, normal, rigid(sn + label))


## A feather card hanging from `root` at `angle_deg` from straight down (toward the
## wing tip when positive), gently cupped and curving back toward the body.
func feather(s: Surf, sx: float, root: Vector3, angle_deg: float, length: float, width: float, normal: Vector3, bw: Array) -> void:
	var a := angle_deg * DEG
	var dir := Vector3(sx * sin(a), -cos(a), 0.0)
	var across := dir.cross(normal).normalized()
	var curl := Vector3(-sx, 0, 0)
	var variant := rng.randi_range(0, 3)
	var segs := 6
	var rows := []
	var centers := []
	for k in segs + 1:
		var t := float(k) / segs
		var c := root + dir * length * t + curl * length * 0.05 * t * t + normal * length * 0.03 * sin(PI * t)
		# Column 0 is the narrow leading vane, toward the wing tip.
		rows.append(PackedVector3Array([c - across * sx * width * 0.5, c + across * sx * width * 0.5]))
		centers.append(c)
	var uv := func(r: int, j: int, _p: Vector3) -> Vector2:
		return Vector2((variant + j) / 4.0, float(r) / segs)
	grid(s, rows, false, true, same(bw, segs + 1), centers, normal, uv)


# ---------------------------------------------------------------- animation

func e(x: float, y: float, z: float) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z) * DEG)


## Rotations applied in sequence (first listed first), each about the parent's axis.
func seq(steps: Array) -> Quaternion:
	var q := Quaternion.IDENTITY
	for st in steps:
		var axis: Vector3 = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[st[0]]
		q = Quaternion(axis, st[1] * DEG) * q
	return q


## Mirrors a left-side rotation for the right side (reflection across the YZ plane).
func mirror(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


## Sets a left-side bone and, unless `right` is given, the mirrored right one.
func both(pose: Dictionary, bone: String, left: Quaternion, right: Variant = null) -> void:
	pose["Left" + bone] = left
	pose["Right" + bone] = mirror(left if right == null else right)


func bump(x: float, center: float, width: float) -> float:
	var d := fposmod(x - center + 0.5, 1.0) - 0.5
	return exp(-(d * d) / (width * width))


## Wing pose (left side): `flap` swings the wing fore/aft about her vertical axis
## (positive = toward her back), `lift` raises the span, `twist` pitches the wing
## plane, and fold2/fold3 bend the forearm and hand within the wing plane.
func wing_pose(pose: Dictionary, flap: float, lift: float, twist: float, fold2: float, fold3: float,
		right_flap: Variant = null) -> void:
	var w1 := seq([["x", twist], ["z", lift], ["y", flap]])
	var w1r := w1 if right_flap == null else seq([["x", twist], ["z", lift], ["y", right_flap]])
	both(pose, "Wing1", w1, w1r)
	both(pose, "Wing2", seq([["z", fold2]]))
	both(pose, "Wing3", seq([["z", fold3]]))


## Folded frame angles (left wing, degrees about the wing-plane normal): the upper arm
## swings down, the forearm folds back up along it and the hand folds down again, a
## bird's Z-fold. FOLD_TILT then leans the folded wing's lower end back off her legs.
const FOLD_W1 := 78.0
const FOLD_TILT := -25.0
const FOLD_W2 := -165.0
const FOLD_W3 := 160.0


## Wings folding against her back: f = 0 spread (the rest pose), 1 folded. The frame
## folds shoulder first, then forearm, then hand, while each feather turns on its own
## bone so the fan collapses into a stack pointing down her back, ruffling as it
## settles. `bounce` adds a small lift of the folded wings (for gait).
func fold_wings(pose: Dictionary, f: float, bounce := 0.0) -> void:
	var f1 := smoothstep(0.0, 0.6, f)
	var f2 := smoothstep(0.15, 0.8, f)
	var f3 := smoothstep(0.3, 0.95, f)
	var ff := smoothstep(0.25, 1.0, f)
	var settle := 4.0 * sin(PI * clampf((f - 0.8) / 0.2, 0.0, 1.0))
	var z1 := FOLD_W1 * f1
	var z2 := FOLD_W2 * f2
	var z3 := FOLD_W3 * f3
	both(pose, "Wing1", seq([["z", z1], ["x", FOLD_TILT * f1 + bounce]]))
	both(pose, "Wing2", seq([["z", z2]]))
	both(pose, "Wing3", seq([["z", z3]]))
	# A feather's angle from straight down is its rest angle minus the frame's turn
	# minus its own turn; solve for the own turn that gives the wanted angle.
	var chain := [z1, z1 + z2, z1 + z2 + z3]
	for m in feather_meta:
		var wanted: float = lerpf(m.angle, m.folded + settle, ff)
		var own: float = m.angle - chain[m.seg] - wanted
		both(pose, m.label, seq([["z", own]]))


func pose_idle(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["hips_offset"] = Vector3(0, -0.004 * (0.5 - 0.5 * cos(ph)), 0)
	p["Spine"] = e(1.0 * sin(ph), 0, 0)
	p["Chest"] = e(1.5 * sin(ph + 0.4), 0, 0)
	p["Neck"] = e(-2, 0, 0)
	p["Head"] = e(3, 4 * sin(ph), 0)
	both(p, "UpperArm", e(4, 0, -7 - sin(ph)))
	both(p, "LowerArm", e(14, 0, 0))
	both(p, "Hand", e(6, 0, 0))
	both(p, "UpperLeg", e(2, 0, -2))
	both(p, "LowerLeg", e(-4, 0, 0))
	both(p, "Foot", e(2, 0, 2))
	fold_wings(p, 1.0, 1.5 * sin(ph))
	return p


func gait(p: Dictionary, t: float, run: float) -> void:
	# run = 0 for walking, 1 for running. Left heel strikes at t = 0.
	var ph := TAU * t
	for side in [["Left", 0.0], ["Right", 0.5]]:
		var lt := fposmod(t + side[1], 1.0)
		var lph := TAU * lt
		var hip := lerpf(22.0, 38.0, run) * cos(lph) + lerpf(0.0, 10.0, run)
		var knee := -(lerpf(5.0, 12.0, run) + lerpf(14.0, 22.0, run) * bump(lt, 0.12, 0.07)
				+ lerpf(58.0, 100.0, run) * bump(lt, lerpf(0.72, 0.68, run), lerpf(0.12, 0.14, run)))
		var ankle := 12.0 * bump(lt, 0.0, 0.06) - lerpf(18.0, 30.0, run) * bump(lt, lerpf(0.55, 0.45, run), 0.07) \
				+ 8.0 * bump(lt, 0.8, 0.1)
		var toes := 25.0 * bump(lt, lerpf(0.55, 0.45, run), 0.06)
		var arm := -lerpf(14.0, 38.0, run) * cos(lph + PI)
		var elbow := lerpf(15.0, 80.0, run) + lerpf(10.0, 12.0, run) * (0.5 + 0.5 * cos(lph + PI))
		var q_leg := e(hip, 0, -2)
		var q_knee := e(knee, 0, 0)
		var q_foot := e(ankle, 0, 0)
		var q_toes := e(toes, 0, 0)
		var q_arm := e(arm + lerpf(0.0, 5.0, run), 0, -lerpf(7.0, 10.0, run))
		var q_elbow := e(elbow, 0, 0)
		if side[0] == "Left":
			p["LeftUpperLeg"] = q_leg
			p["LeftLowerLeg"] = q_knee
			p["LeftFoot"] = q_foot
			p["LeftToes"] = q_toes
			p["LeftUpperArm"] = q_arm
			p["LeftLowerArm"] = q_elbow
			p["LeftHand"] = e(lerpf(5.0, 10.0, run), 0, 0)
		else:
			p["RightUpperLeg"] = mirror(q_leg)
			p["RightLowerLeg"] = mirror(q_knee)
			p["RightFoot"] = mirror(q_foot)
			p["RightToes"] = mirror(q_toes)
			p["RightUpperArm"] = mirror(q_arm)
			p["RightLowerArm"] = mirror(q_elbow)
			p["RightHand"] = mirror(e(lerpf(5.0, 10.0, run), 0, 0))
	var bob_phase := lerpf(0.0, 0.15, run)
	var bob := lerpf(0.018, 0.03, run)
	p["hips_offset"] = Vector3(0, -bob * (0.5 + 0.5 * cos(2.0 * (ph - TAU * bob_phase))) - lerpf(0.0, 0.03, run), 0)
	var yaw := lerpf(5.0, 8.0, run)
	p["Hips"] = e(0, -yaw * cos(ph), 2.0 * sin(ph))
	p["Spine"] = e(-lerpf(2.0, 12.0, run), yaw * 0.5 * cos(ph), 0)
	p["Chest"] = e(-lerpf(0.0, 6.0, run), yaw * 0.8 * cos(ph), -1.5 * sin(ph))
	p["Neck"] = e(lerpf(0.0, 6.0, run), 0, 0)
	p["Head"] = e(lerpf(-1.0, 9.0, run) + cos(2.0 * ph), -yaw * 0.6 * cos(ph), 0)
	fold_wings(p, 1.0, lerpf(1.5, 4.0, run) * cos(2.0 * ph))


func pose_walk(t: float) -> Dictionary:
	var p := {}
	gait(p, t, 0.0)
	return p


func pose_run(t: float) -> Dictionary:
	var p := {}
	gait(p, t, 1.0)
	return p


func pose_fall(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["Spine"] = e(-3, 0, 0)
	p["Head"] = e(-6, 0, 0)
	p["LeftUpperLeg"] = e(28, 0, -4)
	p["LeftLowerLeg"] = e(-45, 0, 0)
	p["RightUpperLeg"] = mirror(e(-4, 0, -4))
	p["RightLowerLeg"] = mirror(e(-22, 0, 0))
	both(p, "Foot", e(-15, 0, 0))
	both(p, "UpperArm", e(12, 0, -55 - 4 * sin(ph)))
	both(p, "LowerArm", e(25, 0, 0))
	fold_wings(p, 1.0, 3.0 * sin(ph))
	return p


## Spread to folded over the clip (played backwards to unfold). Only the wing and
## feather tracks matter in game, where a wing-only layer scrubs it; the body idles.
func pose_fold(t: float) -> Dictionary:
	var p := pose_idle(0.0)
	fold_wings(p, t)
	return p


## Flapping: downstroke drives the wing toward her front, the forearm and hand fold
## in on the upstroke, and the wing plane pitches through the stroke.
func flap_wings(p: Dictionary, t: float, amplitude: float, center: float, twist_amp: float) -> void:
	var ph := TAU * t
	var stroke := cos(ph)                 # +1 top of upstroke at t = 0
	var flap := center + amplitude * stroke
	var fold := maxf(0.0, sin(ph))        # folding while the wing comes up
	var twist := twist_amp * sin(ph)
	wing_pose(p, flap, 8.0 + 10.0 * stroke, twist, 30.0 * fold, 35.0 * fold)


func pose_hover(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["hips_offset"] = Vector3(0, 0.03 * sin(ph - 0.6), 0)
	p["Spine"] = e(-4, 0, 0)
	p["Chest"] = e(2 * sin(ph), 0, 0)
	p["Head"] = e(4, 0, 0)
	p["LeftUpperLeg"] = e(14, 0, -3)
	p["LeftLowerLeg"] = e(-28, 0, 0)
	p["RightUpperLeg"] = mirror(e(4, 0, -3))
	p["RightLowerLeg"] = mirror(e(-16, 0, 0))
	both(p, "Foot", e(-35, 0, 0))
	both(p, "UpperArm", e(14, 0, -38 + 4 * sin(ph)))
	both(p, "LowerArm", e(25, 0, 0))
	both(p, "Hand", e(10, 0, 0))
	flap_wings(p, t, 48.0, 5.0, 18.0)
	return p


func pose_fly(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["hips_offset"] = Vector3(0, 0, 0.025 * sin(ph - 0.6))
	p["Spine"] = e(7, 0, 0)
	p["Chest"] = e(6 + 2 * sin(ph), 0, 0)
	p["Neck"] = e(18, 0, 0)
	p["Head"] = e(32, 0, 0)
	p["LeftUpperLeg"] = e(-6, 0, -3)
	p["LeftLowerLeg"] = e(-14, 0, 0)
	p["RightUpperLeg"] = mirror(e(4, 0, -3))
	p["RightLowerLeg"] = mirror(e(-30, 0, 0))
	both(p, "Foot", e(-45, 0, 0))
	both(p, "UpperArm", e(25, 0, -48 + 5 * sin(ph)))
	both(p, "LowerArm", e(20, 0, 0))
	both(p, "Hand", e(15, 0, 0))
	flap_wings(p, t, 42.0, 0.0, 14.0)
	return p


## The illustration's pose: wings spread, one arm reaching ahead, one leg drawn up.
func pose_glide(t: float) -> Dictionary:
	var ph := TAU * t
	var p := {}
	p["Spine"] = e(8, 0, 0)
	p["Chest"] = e(5, 0, 2 * sin(ph))
	p["Neck"] = e(16, 0, 0)
	p["Head"] = e(30, -6, 0)
	p["LeftUpperArm"] = e(75, 0, -70)
	p["LeftLowerArm"] = e(12, 0, 0)
	p["LeftHand"] = e(-10, 0, 0)
	p["RightUpperArm"] = mirror(e(30, 0, -28))
	p["RightLowerArm"] = mirror(e(35, 0, 0))
	p["RightHand"] = mirror(e(20, 0, 0))
	p["LeftUpperLeg"] = e(30, 0, -6)
	p["LeftLowerLeg"] = e(-70, 0, 0)
	p["RightUpperLeg"] = mirror(e(-4, 0, -3))
	p["RightLowerLeg"] = mirror(e(-8, 0, 0))
	both(p, "Foot", e(-45, 0, 0))
	var sway := 4.0 * sin(ph)
	wing_pose(p, -6.0 + sway, 14.0 - sway, 4.0, 0.0, -4.0, -6.0 - sway)
	return p


## Samples `pose_fn(t)` for t in [0, 1) (looping) or [0, 1] (one-shot) into a clip that
## keys every bone. A bone that holds still through the clip gets a single key.
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
	for bone_name in bone_names:
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("Skeleton:" + bone_name))
		var values: Array[Quaternion] = []
		var still := true
		for pose in poses:
			var q: Quaternion = pose.get(bone_name, Quaternion.IDENTITY)
			values.append(q.normalized())
			still = still and values[-1].is_equal_approx(values[0])
		for k in (1 if still else samples):
			anim.rotation_track_insert_key(tr, times[k], values[k])
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("Skeleton:Hips"))
	for k in samples:
		anim.position_track_insert_key(pos_track, times[k], bone_head[0] + poses[k].get("hips_offset", Vector3.ZERO))
	return anim


func build_animations() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var reset := make_clip(0.001, 1, func(_t: float) -> Dictionary: return {}, false)
	lib.add_animation("RESET", reset)
	lib.add_animation("fold_wings", make_clip(1.0, 30, pose_fold, false))
	lib.add_animation("idle", make_clip(2.4, 24, pose_idle))
	lib.add_animation("walk", make_clip(1.0, 24, pose_walk))
	lib.add_animation("run", make_clip(1.0, 24, pose_run))
	lib.add_animation("fall", make_clip(1.2, 12, pose_fall))
	lib.add_animation("hover", make_clip(0.7, 20, pose_hover))
	lib.add_animation("fly", make_clip(0.8, 20, pose_fly))
	lib.add_animation("glide", make_clip(2.0, 16, pose_glide))
	return lib


# ---------------------------------------------------------------- output

func build_mesh(group: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var g: Dictionary = groups[group]
	for mat_name in g:
		var s: Surf = g[mat_name]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.verts
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_TEX_UV2] = s.uv2s
		arrays[Mesh.ARRAY_BONES] = s.bones
		arrays[Mesh.ARRAY_WEIGHTS] = s.weights
		arrays[Mesh.ARRAY_INDEX] = s.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var si := mesh.get_surface_count() - 1
		mesh.surface_set_material(si, s.material)
		mesh.surface_set_name(si, mat_name)
	return mesh


func save_scene() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_MESHES))
	var root := Node3D.new()
	root.name = "Person"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	root.add_child(skel)
	skel.owner = root
	for i in bone_names.size():
		skel.add_bone(bone_names[i])
	for i in bone_names.size():
		var parent := bone_parent[i]
		skel.set_bone_parent(i, parent)
		var local := bone_head[i] - (bone_head[parent] if parent >= 0 else Vector3.ZERO)
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
	skel.reset_bone_poses()

	var skin := Skin.new()
	for i in bone_names.size():
		skin.add_named_bind(bone_names[i], Transform3D(Basis.IDENTITY, -bone_head[i]))

	var total_tris := 0
	for group: String in ["body", "hair", "wings"]:
		var mesh := build_mesh(group)
		var path := OUT_MESHES + group + ".res"
		var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
		assert(err == OK, "failed to save " + path)
		var mi := MeshInstance3D.new()
		mi.name = group.capitalize()
		mi.mesh = mesh
		mi.skin = skin
		skel.add_child(mi)
		mi.owner = root
		mi.skeleton = NodePath("..")
		var tris := 0
		for si in mesh.get_surface_count():
			tris += mesh.surface_get_array_index_len(si) / 3
		total_tris += tris
		print("%-6s %6d tris  %d surfaces" % [group, tris, mesh.get_surface_count()])
	print("total  %6d tris, %d bones" % [total_tris, bone_names.size()])

	var lib := build_animations()
	var err := ResourceSaver.save(lib, OUT_ANIMS, ResourceSaver.FLAG_CHANGE_PATH)
	assert(err == OK, "failed to save animations")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	player.add_animation_library("", lib)

	var packed := PackedScene.new()
	packed.pack(root)
	err = ResourceSaver.save(packed, OUT_SCENE)
	assert(err == OK, "failed to save scene")
	print("saved ", OUT_SCENE)
	root.free()
