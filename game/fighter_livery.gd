class_name FighterLivery
extends Node
## Repaints one fighter instance without touching the shared fighter materials:
## each hull/nacelle material is duplicated once and its colour parameters are
## overridden, so other scenes (showcase, turntable) keep the original scheme.

@export var target: Node3D
## Main hull colour.
@export var hull_color: Color = Color(0.2, 0.21, 0.24)
## Colour of the inset plates (which plates are insets comes from the panel texture).
@export var accent_color: Color = Color(1.0, 0.45, 0.08)
## Engine trim bands.
@export var trim_color: Color = Color(1.0, 0.45, 0.08)
## Panel seam colour.
@export var seam_color: Color = Color(0.05, 0.05, 0.06)


func _ready() -> void:
	if target == null:
		return
	var copies := {}
	var nodes: Array[Node] = [target]
	nodes.append_array(target.find_children("*", "", true, false))
	for node in nodes:
		if node is CSGShape3D and "material" in node:
			node.material = _repaint(node.material, copies)
		elif node is MeshInstance3D:
			node.material_override = _repaint(node.material_override, copies)


func _repaint(material: Material, copies: Dictionary) -> Material:
	if not (material is ShaderMaterial) or material.shader == null:
		return material
	if copies.has(material):
		return copies[material]
	var params := {}
	for uniform in material.shader.get_shader_uniform_list():
		params[uniform.name] = true
	if not (params.has("base_color") or params.has("body_color")):
		return material

	var copy: ShaderMaterial = material.duplicate()
	if params.has("base_color"):  # hull plating; the panel texture decides which plates are insets
		copy.set_shader_parameter("base_color", hull_color)
		copy.set_shader_parameter("plate_dark", accent_color)
		copy.set_shader_parameter("line_color", seam_color)
	if params.has("body_color"):  # engine nacelles
		copy.set_shader_parameter("body_color", hull_color)
		copy.set_shader_parameter("inset_color", accent_color)
		copy.set_shader_parameter("band_color", trim_color)
		copy.set_shader_parameter("line_color", seam_color)
	copies[material] = copy
	return copy
