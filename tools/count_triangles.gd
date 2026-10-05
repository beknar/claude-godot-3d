extends SceneTree
## Prints the fighter's rendered triangle and vertex counts per top-level part.
## Run from the project root:  godot --headless --path . --script tools/count_triangles.gd

func _initialize() -> void:
	var fighter: Node3D = load("res://fighter/fighter.tscn").instantiate()
	root.add_child(fighter)
	# CSG meshes are built deferred; give them a couple of frames.
	for i in 10:
		await process_frame

	var total_tris := 0
	var total_verts := 0
	var rows := []
	var by_kind := {"CSG": 0, "Primitive": 0}
	for part in fighter.get_children():
		var tris := 0
		var verts := 0
		var nodes: Array = [part]
		nodes.append_array(part.find_children("*", "", true, false))
		for node in nodes:
			var meshes: Array = []
			if node is CSGShape3D and node.is_root_shape():
				# bake_static_mesh() returns the final boolean result; get_meshes() can be stale.
				var baked: ArrayMesh = node.bake_static_mesh()
				if baked:
					meshes.append(baked)
					by_kind["CSG"] += _tris(baked)
			elif node is MeshInstance3D and node.mesh:
				meshes.append(node.mesh)
				by_kind["Primitive"] += _tris(node.mesh)
			for m in meshes:
				tris += _tris(m)
				verts += _verts(m)
		rows.append([part.name, tris, verts])
		total_tris += tris
		total_verts += verts

	for r in rows:
		print("%-10s %6d tris %6d verts" % r)
	print("TOTAL      %6d tris %6d verts" % [total_tris, total_verts])
	print("CSG-built: %d tris, primitive meshes: %d tris" % [by_kind["CSG"], by_kind["Primitive"]])

	var trail_tris := 0
	for n in fighter.find_children("ExhaustTrail", "MeshInstance3D", true, false):
		trail_tris += _tris(n.mesh)
	print("of which exhaust-trail effect cones: %d tris" % trail_tris)
	quit()


func _tris(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			count += idx.size() / 3
		else:
			count += arrays[Mesh.ARRAY_VERTEX].size() / 3
	return count


func _verts(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		count += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
	return count
