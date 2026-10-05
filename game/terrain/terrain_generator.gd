@tool
class_name RollingHillsTerrain
extends Node3D
## Procedural rolling-hills landscape. Builds a smooth-shaded ArrayMesh and a matching
## HeightMapShape3D collider from layered simplex noise, and regenerates live in the
## editor whenever an exported parameter changes. The generated children are internal,
## so the (large) mesh is never written into the .tscn; use "Bake Mesh To File" to
## export it as a standalone mesh resource.

@export var size: float = 2400.0:
	set(value):
		size = maxf(value, 10.0)
		_queue_rebuild()
@export_range(16, 512, 1) var resolution: int = 240:
	set(value):
		resolution = value
		_queue_rebuild()
@export var hill_height: float = 140.0:
	set(value):
		hill_height = value
		_queue_rebuild()
@export var noise_seed: int = 1337:
	set(value):
		noise_seed = value
		_queue_rebuild()
@export var hill_frequency: float = 0.0011:
	set(value):
		hill_frequency = value
		_queue_rebuild()
@export_range(1, 8) var octaves: int = 4:
	set(value):
		octaves = value
		_queue_rebuild()
## Exponent applied to the normalized height. Values above 1 widen the valleys and
## round off the hilltops.
@export_range(0.5, 3.0) var valley_shaping: float = 1.6:
	set(value):
		valley_shaping = value
		_queue_rebuild()
@export var material: Material:
	set(value):
		material = value
		if _mesh_instance:
			_mesh_instance.material_override = material
@export var generate_collision: bool = true:
	set(value):
		generate_collision = value
		_queue_rebuild()

@export_group("Bake")
@export_file("*.res", "*.tres") var bake_path: String = "res://game/terrain/rolling_hills_mesh.res"
@export_tool_button("Bake Mesh To File", "Save") var bake_button: Callable = bake_mesh

var _noise := FastNoiseLite.new()
var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


## Terrain surface height under a world-space XZ position. Assumes the terrain node
## itself is not rotated or scaled.
func height_at(world_x: float, world_z: float) -> float:
	var origin := global_position
	return origin.y + _sample(world_x - origin.x, world_z - origin.z)


## Half the terrain's edge length, i.e. how far from its center the ground extends.
func get_half_extent() -> float:
	return size * 0.5


func rebuild() -> void:
	_rebuild_queued = false
	_configure_noise()

	var verts_per_side := resolution + 1
	var vertex_count := verts_per_side * verts_per_side
	var step := size / resolution
	var half := size * 0.5

	var heights := PackedFloat32Array()
	heights.resize(vertex_count)
	for z in verts_per_side:
		for x in verts_per_side:
			heights[z * verts_per_side + x] = _sample(x * step - half, z * step - half)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)
	for z in verts_per_side:
		for x in verts_per_side:
			var i := z * verts_per_side + x
			# Central differences (clamped at the borders) give exact smooth normals.
			var h_left := heights[z * verts_per_side + maxi(x - 1, 0)]
			var h_right := heights[z * verts_per_side + mini(x + 1, resolution)]
			var h_up := heights[maxi(z - 1, 0) * verts_per_side + x]
			var h_down := heights[mini(z + 1, resolution) * verts_per_side + x]
			vertices[i] = Vector3(x * step - half, heights[i], z * step - half)
			normals[i] = Vector3(h_left - h_right, 2.0 * step, h_up - h_down).normalized()
			uvs[i] = Vector2(x, z) / resolution

	# Two clockwise (front-facing, seen from above) triangles per grid cell.
	var indices := PackedInt32Array()
	indices.resize(resolution * resolution * 6)
	var k := 0
	for z in resolution:
		for x in resolution:
			var i := z * verts_per_side + x
			indices[k] = i
			indices[k + 1] = i + 1
			indices[k + 2] = i + verts_per_side
			indices[k + 3] = i + 1
			indices[k + 4] = i + verts_per_side + 1
			indices[k + 5] = i + verts_per_side
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_ensure_children()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = material
	_build_collision(heights, verts_per_side, step)


func bake_mesh() -> void:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		rebuild()
	var err := ResourceSaver.save(_mesh_instance.mesh, bake_path)
	if err == OK:
		print("RollingHillsTerrain: baked mesh to ", bake_path)
	else:
		push_error("RollingHillsTerrain: failed to bake mesh to %s (error %d)" % [bake_path, err])


func _queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _configure_noise() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	_noise.frequency = hill_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves
	_noise.fractal_gain = 0.45


func _sample(local_x: float, local_z: float) -> float:
	var n := clampf(_noise.get_noise_2d(local_x, local_z) * 0.5 + 0.5, 0.0, 1.0)
	return pow(n, valley_shaping) * hill_height


func _ensure_children() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)


func _build_collision(heights: PackedFloat32Array, verts_per_side: int, step: float) -> void:
	if not generate_collision:
		if _collision:
			_collision.get_parent().queue_free()
			_collision = null
		return
	if _collision == null:
		var body := StaticBody3D.new()
		body.name = "TerrainBody"
		add_child(body, false, Node.INTERNAL_MODE_FRONT)
		_collision = CollisionShape3D.new()
		body.add_child(_collision, false, Node.INTERNAL_MODE_FRONT)
	# A uniformly scaled heightmap: one cell per grid step, heights pre-divided by
	# the scale so the collider lines up exactly with the visual mesh.
	var scaled := PackedFloat32Array()
	scaled.resize(heights.size())
	for i in heights.size():
		scaled[i] = heights[i] / step
	var shape := HeightMapShape3D.new()
	shape.map_width = verts_per_side
	shape.map_depth = verts_per_side
	shape.map_data = scaled
	_collision.shape = shape
	_collision.scale = Vector3.ONE * step
