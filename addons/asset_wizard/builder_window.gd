@tool
extends Window

const SETTINGS_PATH := "user://asset_wizard.cfg"
const LEGACY_SETTINGS_PATH := "user://physics_scene_builder.cfg"
const MODEL_EXTENSIONS := ["glb", "gltf", "obj", "fbx", "dae", "blend"]

enum ContextMode { NONE, SCENE, FILESYSTEM }
enum CollisionMode { COMBINED, PER_MESH }

var plugin: EditorPlugin
var context_mode := ContextMode.NONE
var selected_meshes: Array[MeshInstance3D] = []
var selected_files := PackedStringArray()
var pending_output_paths := PackedStringArray()

var status_label: Label
var root_option: OptionButton
var collision_option: OptionButton
var collision_mode_option: OptionButton
var padding_spin: SpinBox
var size_scale_spin: SpinBox
var output_row: HBoxContainer
var output_edit: LineEdit
var browse_button: Button
var create_button: Button
var message_label: Label
var folder_dialog: EditorFileDialog
var overwrite_dialog: ConfirmationDialog
var heading_label: Label


func setup(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin
	title = "Asset Wizard"
	min_size = Vector2i(520, 500)
	size = Vector2i(560, 620)
	unresizable = false
	close_requested.connect(hide)
	_apply_editor_theme()
	_build_ui()
	_load_settings()


func _apply_editor_theme() -> void:
	if plugin == null:
		return
	var editor_base := plugin.get_editor_interface().get_base_control()
	if editor_base != null and editor_base.theme != null:
		theme = editor_base.theme


func _apply_theme_accents() -> void:
	if plugin == null or heading_label == null:
		return
	var editor_base := plugin.get_editor_interface().get_base_control()
	if editor_base != null and editor_base.has_theme_color("accent_color", "Editor"):
		heading_label.add_theme_color_override("font_color", editor_base.get_theme_color("accent_color", "Editor"))


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	margin.add_child(main)

	heading_label = Label.new()
	heading_label.text = "Asset Wizard"
	heading_label.add_theme_font_size_override("font_size", 22)
	_apply_theme_accents()
	main.add_child(heading_label)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(status_label)

	main.add_child(HSeparator.new())

	root_option = _add_option_row(main, "Root node")
	for root_name in ["StaticBody3D", "CharacterBody3D", "RigidBody3D", "Area3D", "AnimatableBody3D", "VehicleBody3D"]:
		root_option.add_item(root_name)
	root_option.item_selected.connect(_on_setting_changed)

	collision_option = _add_option_row(main, "Collision shape")
	for shape_name in [
		"BoxShape3D",
		"SphereShape3D",
		"CapsuleShape3D",
		"CylinderShape3D",
		"SeparationRayShape3D",
		"HeightMapShape3D",
		"WorldBoundaryShape3D",
		"ConvexPolygonShape3D",
		"ConcavePolygonShape3D"
	]:
		collision_option.add_item(shape_name)
	collision_option.item_selected.connect(_on_collision_changed)

	collision_mode_option = _add_option_row(main, "Multiple meshes")
	collision_mode_option.add_item("One combined collision", CollisionMode.COMBINED)
	collision_mode_option.add_item("One collision per mesh", CollisionMode.PER_MESH)
	collision_mode_option.item_selected.connect(_on_setting_changed)

	padding_spin = _add_spin_row(main, "Padding", 0.0, 1000.0, 0.01, 0.0)
	padding_spin.suffix = " m"
	padding_spin.value_changed.connect(_on_setting_changed)

	size_scale_spin = _add_spin_row(main, "Size multiplier", 0.01, 100.0, 0.01, 1.0)
	size_scale_spin.value_changed.connect(_on_setting_changed)

	output_row = HBoxContainer.new()
	var output_label := Label.new()
	output_label.text = "Output folder"
	output_label.custom_minimum_size.x = 150
	output_row.add_child(output_label)
	output_edit = LineEdit.new()
	output_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_edit.placeholder_text = "res://generated/"
	output_edit.text_changed.connect(_on_output_changed)
	output_row.add_child(output_edit)
	browse_button = Button.new()
	browse_button.text = "Browse"
	browse_button.pressed.connect(_browse_output)
	output_row.add_child(browse_button)
	main.add_child(output_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(spacer)

	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(message_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var refresh_button := Button.new()
	refresh_button.text = "Refresh Selection"
	refresh_button.pressed.connect(refresh_context)
	buttons.add_child(refresh_button)
	create_button = Button.new()
	create_button.text = "Create"
	create_button.pressed.connect(_on_create_pressed)
	buttons.add_child(create_button)
	main.add_child(buttons)

	folder_dialog = EditorFileDialog.new()
	folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	folder_dialog.dir_selected.connect(_on_output_folder_selected)
	add_child(folder_dialog)

	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = "Overwrite existing scenes?"
	overwrite_dialog.confirmed.connect(_create_filesystem_scenes)
	add_child(overwrite_dialog)


func _add_option_row(parent: VBoxContainer, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	parent.add_child(row)
	return option


func _add_spin_row(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float, default_value: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = default_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	parent.add_child(row)
	return spin


func refresh_context() -> void:
	if plugin == null:
		return

	selected_meshes.clear()
	selected_files.clear()
	message_label.text = ""

	var selection := plugin.get_editor_interface().get_selection()
	if selection != null:
		for node in selection.get_selected_nodes():
			if node is MeshInstance3D:
				selected_meshes.append(node as MeshInstance3D)

	if not selected_meshes.is_empty():
		context_mode = ContextMode.SCENE
		status_label.text = "Mode: Scene nodes\n%d MeshInstance3D node(s) selected. The existing scene will be modified." % selected_meshes.size()
		output_row.visible = false
		create_button.text = "Set Up Selected Meshes"
		create_button.disabled = false
		return

	if plugin.get_editor_interface().has_method("get_selected_paths"):
		var paths: PackedStringArray = plugin.get_editor_interface().get_selected_paths()
		for path in paths:
			if _is_supported_model(path):
				selected_files.append(path)

	if not selected_files.is_empty():
		context_mode = ContextMode.FILESYSTEM
		status_label.text = "Mode: FileSystem assets\n%d model file(s) selected. One .tscn will be created for each model." % selected_files.size()
		output_row.visible = true
		create_button.text = "Create Scenes"
		create_button.disabled = not _valid_output_folder()
		return

	context_mode = ContextMode.NONE
	status_label.text = "Select one or more MeshInstance3D nodes in the Scene dock, or model files in the FileSystem dock. Scene-node selection takes priority."
	output_row.visible = false
	create_button.text = "Create"
	create_button.disabled = true


func _is_supported_model(path: String) -> bool:
	return path.get_extension().to_lower() in MODEL_EXTENSIONS


func _on_create_pressed() -> void:
	_save_settings()
	message_label.text = ""
	match context_mode:
		ContextMode.SCENE:
			_setup_scene_nodes()
		ContextMode.FILESYSTEM:
			_prepare_filesystem_creation()


func _setup_scene_nodes() -> void:
	var valid_meshes: Array[MeshInstance3D] = []
	for mesh_instance in selected_meshes:
		if is_instance_valid(mesh_instance) and mesh_instance.get_parent() != null and mesh_instance.mesh != null:
			valid_meshes.append(mesh_instance)

	if valid_meshes.is_empty():
		message_label.text = "No valid MeshInstance3D nodes are selected."
		return

	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("Set Up Physics Roots and Collisions")

	for mesh_instance in valid_meshes:
		var old_parent := mesh_instance.get_parent()
		var old_index := mesh_instance.get_index()
		var old_transform := mesh_instance.transform
		var physics_root := _make_root_node()
		physics_root.name = _unique_child_name(old_parent, _base_name(mesh_instance.name) + "_physics")
		physics_root.transform = old_transform

		var collisions := _create_collision_nodes_for_meshes([mesh_instance], Transform3D.IDENTITY)

		undo_redo.add_do_method(old_parent, "add_child", physics_root)
		undo_redo.add_do_method(physics_root, "set_owner", mesh_instance.owner)
		undo_redo.add_do_method(old_parent, "move_child", physics_root, old_index)
		undo_redo.add_do_method(mesh_instance, "reparent", physics_root, false)
		undo_redo.add_do_property(mesh_instance, "transform", Transform3D.IDENTITY)
		for collision in collisions:
			undo_redo.add_do_method(physics_root, "add_child", collision)
			undo_redo.add_do_method(collision, "set_owner", mesh_instance.owner)

		for collision in collisions:
			undo_redo.add_undo_method(physics_root, "remove_child", collision)
		undo_redo.add_undo_method(mesh_instance, "reparent", old_parent, false)
		undo_redo.add_undo_property(mesh_instance, "transform", old_transform)
		undo_redo.add_undo_method(old_parent, "move_child", mesh_instance, old_index)
		undo_redo.add_undo_method(old_parent, "remove_child", physics_root)

	undo_redo.commit_action()
	message_label.text = "Set up %d mesh node(s). Use Undo to reverse the entire operation." % valid_meshes.size()
	refresh_context.call_deferred()


func _prepare_filesystem_creation() -> void:
	if not _valid_output_folder():
		message_label.text = "Choose a valid res:// output folder first."
		return

	pending_output_paths.clear()
	var existing := PackedStringArray()
	for source_path in selected_files:
		var output_path := _output_path_for(source_path)
		pending_output_paths.append(output_path)
		if FileAccess.file_exists(output_path):
			existing.append(output_path)

	if not existing.is_empty():
		overwrite_dialog.dialog_text = "%d scene(s) already exist and will be overwritten:\n\n%s" % [existing.size(), "\n".join(existing)]
		overwrite_dialog.popup_centered(Vector2i(520, 300))
	else:
		_create_filesystem_scenes()


func _create_filesystem_scenes() -> void:
	var output_dir := output_edit.text.strip_edges().trim_suffix("/")
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		message_label.text = "Could not create output folder: %s" % error_string(mkdir_error)
		return

	var created := 0
	var errors: Array[String] = []
	for source_path in selected_files:
		var resource := ResourceLoader.load(source_path)
		if resource == null:
			errors.append("Could not load %s" % source_path)
			continue

		var model_root: Node3D
		if resource is PackedScene:
			var instance := (resource as PackedScene).instantiate()
			if instance is Node3D:
				model_root = instance as Node3D
			else:
				model_root = Node3D.new()
				model_root.name = _base_name(source_path.get_file().get_basename())
				model_root.add_child(instance)
		elif resource is Mesh:
			model_root = MeshInstance3D.new()
			(model_root as MeshInstance3D).mesh = resource as Mesh
			model_root.name = _base_name(source_path.get_file().get_basename())
		else:
			errors.append("Unsupported imported resource: %s" % source_path)
			continue

		var physics_root := _make_root_node()
		physics_root.name = _base_name(source_path.get_file().get_basename())
		physics_root.add_child(model_root)
		# Keep imported PackedScene descendants owned by their original scene.
		# Recursively assigning ownership here flattens nested imported instances and
		# can create duplicate node paths when the generated scene is loaded.
		model_root.owner = physics_root

		var meshes := _find_meshes(model_root)
		if meshes.is_empty():
			errors.append("No mesh geometry found in %s" % source_path)
			physics_root.free()
			continue

		var collisions := _create_collision_nodes_for_meshes(meshes, Transform3D.IDENTITY, physics_root)
		for collision in collisions:
			physics_root.add_child(collision)
			collision.owner = physics_root

		var packed := PackedScene.new()
		var pack_error := packed.pack(physics_root)
		if pack_error != OK:
			errors.append("Could not pack scene for %s: %s" % [source_path, error_string(pack_error)])
			physics_root.free()
			continue

		var output_path := _output_path_for(source_path)
		var save_error := ResourceSaver.save(packed, output_path)
		physics_root.free()
		if save_error == OK:
			created += 1
		else:
			errors.append("Could not save %s: %s" % [output_path, error_string(save_error)])

	plugin.get_editor_interface().get_resource_filesystem().scan()
	message_label.text = "Created %d scene(s)." % created
	if not errors.is_empty():
		message_label.text += "\n\n" + "\n".join(errors)


func _make_root_node() -> Node3D:
	match root_option.get_item_text(root_option.selected):
		"CharacterBody3D": return CharacterBody3D.new()
		"RigidBody3D": return RigidBody3D.new()
		"Area3D": return Area3D.new()
		"AnimatableBody3D": return AnimatableBody3D.new()
		"VehicleBody3D": return VehicleBody3D.new()
		_: return StaticBody3D.new()


func _create_collision_nodes_for_meshes(meshes: Array[MeshInstance3D], base_transform := Transform3D.IDENTITY, root: Node3D = null) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	var per_mesh := collision_mode_option.get_selected_id() == CollisionMode.PER_MESH

	if per_mesh:
		for mesh_instance in meshes:
			if mesh_instance.mesh == null:
				continue
			var transform := _transform_relative_to(mesh_instance, root) if root != null else base_transform
			var collision := _collision_from_entries([{ "mesh": mesh_instance.mesh, "transform": transform }])
			if collision != null:
				collision.name = _base_name(mesh_instance.name) + "_collision"
				result.append(collision)
	else:
		var entries: Array[Dictionary] = []
		for mesh_instance in meshes:
			if mesh_instance.mesh == null:
				continue
			var transform := _transform_relative_to(mesh_instance, root) if root != null else base_transform
			entries.append({ "mesh": mesh_instance.mesh, "transform": transform })
		var collision := _collision_from_entries(entries)
		if collision != null:
			collision.name = "CollisionShape3D"
			result.append(collision)

	return result


func _collision_from_entries(entries: Array[Dictionary]) -> CollisionShape3D:
	if entries.is_empty():
		return null

	var collision := CollisionShape3D.new()
	var shape_name := collision_option.get_item_text(collision_option.selected)
	var bounds := _calculate_bounds(entries)
	var padded_size := bounds.size * float(size_scale_spin.value) + Vector3.ONE * float(padding_spin.value) * 2.0
	padded_size = Vector3(maxf(padded_size.x, 0.001), maxf(padded_size.y, 0.001), maxf(padded_size.z, 0.001))
	collision.position = bounds.get_center()

	match shape_name:
		"SphereShape3D":
			var shape := SphereShape3D.new()
			shape.radius = maxf(padded_size.x, maxf(padded_size.y, padded_size.z)) * 0.5
			collision.shape = shape
		"CapsuleShape3D":
			var shape := CapsuleShape3D.new()
			shape.radius = maxf(padded_size.x, padded_size.z) * 0.5
			shape.height = maxf(padded_size.y, shape.radius * 2.0)
			collision.shape = shape
		"CylinderShape3D":
			var shape := CylinderShape3D.new()
			shape.radius = maxf(padded_size.x, padded_size.z) * 0.5
			shape.height = padded_size.y
			collision.shape = shape
		"SeparationRayShape3D":
			var shape := SeparationRayShape3D.new()
			shape.length = padded_size.y
			collision.shape = shape
		"HeightMapShape3D":
			var shape := HeightMapShape3D.new()
			shape.map_width = 2
			shape.map_depth = 2
			shape.map_data = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			collision.scale = Vector3(padded_size.x, 1.0, padded_size.z)
			collision.shape = shape
		"WorldBoundaryShape3D":
			var shape := WorldBoundaryShape3D.new()
			shape.plane = Plane(Vector3.UP, bounds.get_center().y)
			collision.position = Vector3.ZERO
			collision.shape = shape
		"ConvexPolygonShape3D":
			var shape := ConvexPolygonShape3D.new()
			shape.points = _collect_faces(entries, false)
			collision.position = Vector3.ZERO
			collision.shape = shape
		"ConcavePolygonShape3D":
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(_collect_faces(entries, true))
			collision.position = Vector3.ZERO
			collision.shape = shape
		_:
			var shape := BoxShape3D.new()
			shape.size = padded_size
			collision.shape = shape

	return collision


func _calculate_bounds(entries: Array[Dictionary]) -> AABB:
	var has_bounds := false
	var bounds := AABB()
	for entry in entries:
		var mesh: Mesh = entry.mesh
		var transform: Transform3D = entry.transform
		var transformed := _transform_aabb(mesh.get_aabb(), transform)
		if not has_bounds:
			bounds = transformed
			has_bounds = true
		else:
			bounds = bounds.merge(transformed)
	return bounds


func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var points := [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.end
	]
	var result := AABB(transform * points[0], Vector3.ZERO)
	for point in points:
		result = result.expand(transform * point)
	return result


func _collect_faces(entries: Array[Dictionary], triangles_only: bool) -> PackedVector3Array:
	var points := PackedVector3Array()
	for entry in entries:
		var mesh: Mesh = entry.mesh
		var transform: Transform3D = entry.transform
		var faces := mesh.get_faces()
		for point in faces:
			points.append(transform * point)
	if triangles_only:
		return points
	# ConvexPolygonShape3D accepts a point cloud; duplicate triangle vertices are valid.
	return points


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes


func _transform_relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform



func _unique_child_name(parent: Node, desired: String) -> String:
	var candidate := desired
	var number := 2
	while parent.has_node(NodePath(candidate)):
		candidate = "%s_%d" % [desired, number]
		number += 1
	return candidate


func _base_name(value: String) -> String:
	var text := value.strip_edges().to_snake_case()
	return text if not text.is_empty() else "asset"


func _output_path_for(source_path: String) -> String:
	var folder := output_edit.text.strip_edges().trim_suffix("/")
	var scene_name := _base_name(source_path.get_file().get_basename()) + ".tscn"
	return folder.path_join(scene_name)


func _valid_output_folder() -> bool:
	var folder := output_edit.text.strip_edges()
	return folder.begins_with("res://") and folder.length() > 6


func _browse_output() -> void:
	folder_dialog.current_dir = output_edit.text if _valid_output_folder() else "res://"
	folder_dialog.popup_centered_ratio(0.7)


func _on_output_folder_selected(path: String) -> void:
	output_edit.text = path
	_save_settings()
	refresh_context()


func _on_output_changed(_value: String) -> void:
	if context_mode == ContextMode.FILESYSTEM:
		create_button.disabled = not _valid_output_folder()
	_save_settings()


func _on_collision_changed(_index: int) -> void:
	var shape_name := collision_option.get_item_text(collision_option.selected)
	var geometry_shape := shape_name in ["ConvexPolygonShape3D", "ConcavePolygonShape3D"]
	padding_spin.editable = not geometry_shape
	size_scale_spin.editable = not geometry_shape
	if shape_name == "ConcavePolygonShape3D" and root_option.get_item_text(root_option.selected) != "StaticBody3D":
		message_label.text = "Warning: Concave collision is intended for static bodies. Godot does not support it reliably on CharacterBody3D or RigidBody3D."
	else:
		message_label.text = ""
	_save_settings()


func _on_setting_changed(_value = 0) -> void:
	_on_collision_changed(collision_option.selected)


func _load_settings() -> void:
	var config := ConfigFile.new()
	var load_result := config.load(SETTINGS_PATH)
	if load_result != OK:
		load_result = config.load(LEGACY_SETTINGS_PATH)
	if load_result != OK:
		output_edit.text = "res://generated_assets"
		return
	_select_option_text(root_option, str(config.get_value("builder", "root", "StaticBody3D")))
	_select_option_text(collision_option, str(config.get_value("builder", "collision", "BoxShape3D")))
	collision_mode_option.select(int(config.get_value("builder", "collision_mode", 0)))
	padding_spin.value = float(config.get_value("builder", "padding", 0.0))
	size_scale_spin.value = float(config.get_value("builder", "size_scale", 1.0))
	output_edit.text = str(config.get_value("builder", "output", "res://generated_assets"))
	_on_collision_changed(collision_option.selected)


func _save_settings() -> void:
	if root_option == null:
		return
	var config := ConfigFile.new()
	config.set_value("builder", "root", root_option.get_item_text(root_option.selected))
	config.set_value("builder", "collision", collision_option.get_item_text(collision_option.selected))
	config.set_value("builder", "collision_mode", collision_mode_option.selected)
	config.set_value("builder", "padding", padding_spin.value)
	config.set_value("builder", "size_scale", size_scale_spin.value)
	config.set_value("builder", "output", output_edit.text)
	config.save(SETTINGS_PATH)


func _select_option_text(option: OptionButton, text: String) -> void:
	for index in option.item_count:
		if option.get_item_text(index) == text:
			option.select(index)
			return
