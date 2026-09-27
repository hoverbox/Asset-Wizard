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
var create_new_button: Button
var use_existing_button: Button
var existing_assets_view: VBoxContainer
var new_nodes_view: VBoxContainer

# New Node Setup tab
var setup_option: OptionButton
var setup_collision_option: OptionButton
var setup_mesh_option: OptionButton
var setup_add_area_check: CheckBox
var setup_name_edit: LineEdit
var setup_status_label: Label


func setup(editor_plugin: EditorPlugin) -> void:
	# Configure native/transparency flags before this Window is ever displayed.
	# Godot rejects force_native changes on an already-visible window.
	visible = false
	plugin = editor_plugin
	title = "Asset Wizard"
	min_size = Vector2i(1120, 760)
	size = Vector2i(1180, 820)
	unresizable = true
	_enable_window_transparency()
	force_native = true
	borderless = true
	transparent_bg = true
	transparent = true
	visibility_changed.connect(_on_window_visibility_changed)
	close_requested.connect(hide)
	_apply_editor_theme()
	_build_ui()
	_load_settings()


func _enable_window_transparency() -> void:
	# Native per-pixel transparency needs both the project permission and the window flag.
	const TRANSPARENCY_SETTING := "display/window/per_pixel_transparency/allowed"
	if not ProjectSettings.get_setting(TRANSPARENCY_SETTING, false):
		ProjectSettings.set_setting(TRANSPARENCY_SETTING, true)
		ProjectSettings.save()


func _on_window_visibility_changed() -> void:
	if visible:
		# The native window ID is guaranteed to exist once the Window is visible. Applying
		# the flag here fixes the black clear area seen around the rounded card in the editor.
		call_deferred("_apply_native_transparency")


func _apply_native_transparency() -> void:
	transparent_bg = true
	transparent = true
	if DisplayServer.is_window_transparency_available():
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, get_window_id())


func _apply_editor_theme() -> void:
	if plugin == null:
		return
	var editor_base := plugin.get_editor_interface().get_base_control()
	if editor_base != null and editor_base.theme != null:
		theme = editor_base.theme


func _apply_theme_accents() -> void:
	pass


func _build_ui() -> void:
	# The mockup is the layout: a floating rounded card, custom title bar,
	# overlapping mascot, image title, pill mode buttons, and no inner box.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var body := PanelContainer.new()
	body.position = Vector2(72, 54)
	body.size = Vector2(size.x - 92, size.y - 74)
	body.add_theme_stylebox_override("panel", _make_window_style())
	root.add_child(body)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 56)
	body_margin.add_theme_constant_override("margin_right", 48)
	body_margin.add_theme_constant_override("margin_top", 72)
	body_margin.add_theme_constant_override("margin_bottom", 30)
	body.add_child(body_margin)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)
	body_margin.add_child(main)

	# Header content is offset so the mascot can overlap it without covering controls.
	var hero_margin := MarginContainer.new()
	hero_margin.add_theme_constant_override("margin_left", 170)
	main.add_child(hero_margin)

	var hero := VBoxContainer.new()
	hero.add_theme_constant_override("separation", 10)
	hero_margin.add_child(hero)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 10)
	hero.add_child(title_row)

	var star_left := Label.new()
	star_left.text = "★"
	star_left.add_theme_color_override("font_color", Color("ffd21f"))
	star_left.add_theme_font_size_override("font_size", 34)
	title_row.add_child(star_left)

	var title_image := TextureRect.new()
	title_image.custom_minimum_size = Vector2(610, 88)
	title_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_image.texture = load("res://addons/asset_wizard/asset_wizard_title.png") as Texture2D
	title_row.add_child(title_image)

	var star_right := Label.new()
	star_right.text = "★"
	star_right.add_theme_color_override("font_color", Color("ffd21f"))
	star_right.add_theme_font_size_override("font_size", 34)
	title_row.add_child(star_right)

	var mode_buttons := HBoxContainer.new()
	mode_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_buttons.add_theme_constant_override("separation", 34)
	hero.add_child(mode_buttons)

	create_new_button = Button.new()
	create_new_button.text = "✚   Create New"
	create_new_button.custom_minimum_size = Vector2(330, 62)
	create_new_button.add_theme_font_size_override("font_size", 22)
	create_new_button.pressed.connect(_show_new_nodes)
	mode_buttons.add_child(create_new_button)

	use_existing_button = Button.new()
	use_existing_button.text = "▣   Use Existing Assets"
	use_existing_button.custom_minimum_size = Vector2(390, 62)
	use_existing_button.add_theme_font_size_override("font_size", 22)
	use_existing_button.pressed.connect(_show_existing_assets)
	mode_buttons.add_child(use_existing_button)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	main.add_child(content)

	_build_existing_assets_tab(content)
	_build_new_nodes_tab(content)
	_apply_clean_content_theme(content)
	_show_new_nodes()

	# Custom chrome lets the actual window participate in the mockup instead of
	# sitting inside a native OS title bar.
	var title_bar := PanelContainer.new()
	title_bar.position = Vector2(210, 54)
	title_bar.size = Vector2(size.x - 230, 46)
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	var title_style := _make_panel_style(Color("fbfdff"), Color("fbfdff"), 0, 20)
	title_style.corner_radius_bottom_left = 0
	title_style.corner_radius_bottom_right = 0
	title_bar.add_theme_stylebox_override("panel", title_style)
	root.add_child(title_bar)

	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 16)
	title_margin.add_theme_constant_override("margin_right", 10)
	title_margin.add_theme_constant_override("margin_top", 5)
	title_margin.add_theme_constant_override("margin_bottom", 5)
	title_bar.add_child(title_margin)

	var title_controls := HBoxContainer.new()
	title_controls.add_theme_constant_override("separation", 8)
	title_margin.add_child(title_controls)

	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_controls.add_child(title_spacer)

	var minimize_button := Button.new()
	minimize_button.text = "—"
	minimize_button.flat = true
	minimize_button.custom_minimum_size = Vector2(42, 32)
	minimize_button.add_theme_color_override("font_color", Color("18314f"))
	minimize_button.add_theme_color_override("font_hover_color", Color("2e73ad"))
	minimize_button.add_theme_font_size_override("font_size", 20)
	minimize_button.pressed.connect(_minimize_window)
	title_controls.add_child(minimize_button)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.flat = true
	close_button.custom_minimum_size = Vector2(42, 32)
	close_button.add_theme_color_override("font_color", Color("18314f"))
	close_button.add_theme_color_override("font_hover_color", Color("d83a4e"))
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.pressed.connect(hide)
	title_controls.add_child(close_button)

	# Mascot is intentionally last so it draws over the card and title bar.
	var wizard := TextureRect.new()
	wizard.position = Vector2(4, 0)
	wizard.size = Vector2(300, 300)
	wizard.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wizard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wizard.texture = load("res://addons/asset_wizard/wizard.png") as Texture2D
	wizard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wizard)

	folder_dialog = EditorFileDialog.new()
	folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	folder_dialog.dir_selected.connect(_on_output_folder_selected)
	add_child(folder_dialog)

	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = "Overwrite existing scenes?"
	overwrite_dialog.confirmed.connect(_create_filesystem_scenes)
	add_child(overwrite_dialog)


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		DisplayServer.window_start_drag(get_window_id())


func _minimize_window() -> void:
	mode = Window.MODE_MINIMIZED


func _make_window_style() -> StyleBoxFlat:
	var style := _make_panel_style(Color("fbfdff"), Color("2599e6"), 4, 28)
	style.shadow_color = Color(0.02, 0.12, 0.25, 0.30)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	return style


func _apply_clean_content_theme(node: Node) -> void:
	if node is Label:
		var label := node as Label
		label.add_theme_color_override("font_color", Color("1f3c63"))
		label.add_theme_font_size_override("font_size", 18)
	elif node is CheckBox:
		var check := node as CheckBox
		check.add_theme_color_override("font_color", Color("1f3c63"))
		check.add_theme_color_override("font_hover_color", Color("1f3c63"))
		check.add_theme_color_override("font_pressed_color", Color("1f3c63"))
		check.add_theme_font_size_override("font_size", 17)
	elif node is OptionButton or node is LineEdit or node is SpinBox:
		_style_input(node as Control)
	elif node is HSeparator:
		var separator := StyleBoxLine.new()
		separator.color = Color("88cef4")
		separator.thickness = 2
		(node as HSeparator).add_theme_stylebox_override("separator", separator)
	for child in node.get_children():
		_apply_clean_content_theme(child)


func _style_input(control: Control) -> void:
	var normal := _make_panel_style(Color("223f65"), Color("223f65"), 0, 16)
	var hover := _make_panel_style(Color("2d527d"), Color("2d527d"), 0, 16)
	var focus := _make_panel_style(Color("223f65"), Color("52c1ff"), 2, 16)
	for style in [normal, hover, focus]:
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 8
		style.content_margin_bottom = 8
	control.custom_minimum_size.y = 44
	control.add_theme_stylebox_override("normal", normal)
	control.add_theme_stylebox_override("hover", hover)
	control.add_theme_stylebox_override("focus", focus)
	control.add_theme_color_override("font_color", Color("ffffff"))
	control.add_theme_color_override("font_hover_color", Color("ffffff"))
	control.add_theme_color_override("font_focus_color", Color("ffffff"))
	control.add_theme_color_override("font_placeholder_color", Color("91a6c2"))
	control.add_theme_font_size_override("font_size", 17)


func _make_panel_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _rounded_button_style(background: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 24) -> StyleBoxFlat:
	var style := _make_panel_style(background, border, border_width, radius)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _button_style(background: Color, border: Color, shadow: Color, radius := 26) -> StyleBoxFlat:
	var style := _rounded_button_style(background, border, 2, radius)
	style.shadow_color = shadow
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 4)
	return style


func _apply_mode_button_styles() -> void:
	if create_new_button == null or use_existing_button == null:
		return

	var purple := Color("7654e8")
	var purple_hover := Color("8869f2")
	var blue := Color("3979b7")
	var blue_hover := Color("478cc9")
	var inactive := Color("d8effc")
	var inactive_hover := Color("c8e8fa")

	var new_selected := new_nodes_view != null and new_nodes_view.visible
	create_new_button.add_theme_stylebox_override("normal", _button_style(purple if new_selected else inactive, Color("a98cff") if new_selected else Color("b8e1f7"), Color(0.25, 0.15, 0.55, 0.25)))
	create_new_button.add_theme_stylebox_override("hover", _button_style(purple_hover if new_selected else inactive_hover, Color("bea8ff") if new_selected else Color("9fd6f5"), Color(0.25, 0.15, 0.55, 0.30)))
	create_new_button.add_theme_stylebox_override("pressed", _button_style(purple_hover, Color("c9b8ff"), Color(0.25, 0.15, 0.55, 0.20)))
	create_new_button.add_theme_color_override("font_color", Color.WHITE if new_selected else Color("24466e"))
	create_new_button.add_theme_color_override("font_hover_color", Color.WHITE if new_selected else Color("24466e"))
	create_new_button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var existing_selected := existing_assets_view != null and existing_assets_view.visible
	use_existing_button.add_theme_stylebox_override("normal", _button_style(blue if existing_selected else inactive, Color("71b7e9") if existing_selected else Color("b8e1f7"), Color(0.08, 0.25, 0.45, 0.22)))
	use_existing_button.add_theme_stylebox_override("hover", _button_style(blue_hover if existing_selected else inactive_hover, Color("8bc9f0") if existing_selected else Color("9fd6f5"), Color(0.08, 0.25, 0.45, 0.28)))
	use_existing_button.add_theme_stylebox_override("pressed", _button_style(blue_hover, Color("9dd3f4"), Color(0.08, 0.25, 0.45, 0.20)))
	use_existing_button.add_theme_color_override("font_color", Color.WHITE if existing_selected else Color("24466e"))
	use_existing_button.add_theme_color_override("font_hover_color", Color.WHITE if existing_selected else Color("24466e"))
	use_existing_button.add_theme_color_override("font_pressed_color", Color.WHITE)


func _style_primary_action(button: Button, purple := true) -> void:
	var base := Color("6848e8") if purple else Color("2e73ad")
	var hover := Color("7e60f2") if purple else Color("3c86c2")
	var border := Color("9d86ff") if purple else Color("6eb9eb")
	var shadow := Color(0.20, 0.12, 0.55, 0.28) if purple else Color(0.05, 0.24, 0.45, 0.25)
	button.custom_minimum_size.y = 56
	button.add_theme_stylebox_override("normal", _button_style(base, border, shadow, 24))
	button.add_theme_stylebox_override("hover", _button_style(hover, border.lightened(0.12), shadow, 24))
	button.add_theme_stylebox_override("pressed", _button_style(hover.darkened(0.05), border, shadow, 24))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 20)

func _show_new_nodes() -> void:
	if new_nodes_view != null:
		new_nodes_view.visible = true
	if existing_assets_view != null:
		existing_assets_view.visible = false
	_apply_mode_button_styles()


func _show_existing_assets() -> void:
	if new_nodes_view != null:
		new_nodes_view.visible = false
	if existing_assets_view != null:
		existing_assets_view.visible = true
	_apply_mode_button_styles()


func _build_existing_assets_tab(parent: Container) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Existing Assets"
	tab.add_theme_constant_override("separation", 12)
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(tab)
	existing_assets_view = tab

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(status_label)

	tab.add_child(HSeparator.new())

	root_option = _add_option_row(tab, "Root node")
	for root_name in ["StaticBody3D", "CharacterBody3D", "RigidBody3D", "Area3D", "AnimatableBody3D", "VehicleBody3D"]:
		root_option.add_item(root_name)
	root_option.item_selected.connect(_on_setting_changed)

	collision_option = _add_option_row(tab, "Collision shape")
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

	collision_mode_option = _add_option_row(tab, "Multiple meshes")
	collision_mode_option.add_item("One combined collision", CollisionMode.COMBINED)
	collision_mode_option.add_item("One collision per mesh", CollisionMode.PER_MESH)
	collision_mode_option.item_selected.connect(_on_setting_changed)

	padding_spin = _add_spin_row(tab, "Padding", 0.0, 1000.0, 0.01, 0.0)
	padding_spin.suffix = " m"
	padding_spin.value_changed.connect(_on_setting_changed)

	size_scale_spin = _add_spin_row(tab, "Size multiplier", 0.01, 100.0, 0.01, 1.0)
	size_scale_spin.value_changed.connect(_on_setting_changed)

	output_row = HBoxContainer.new()
	var output_label := Label.new()
	output_label.text = "Output folder"
	output_label.custom_minimum_size.x = 145
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
	tab.add_child(output_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(spacer)

	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(message_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var refresh_button := Button.new()
	refresh_button.text = "Refresh Selection"
	refresh_button.pressed.connect(refresh_context)
	buttons.add_child(refresh_button)
	create_button = Button.new()
	create_button.text = "Create"
	create_button.pressed.connect(_on_create_pressed)
	_style_primary_action(create_button, false)
	buttons.add_child(create_button)
	tab.add_child(buttons)


func _build_new_nodes_tab(parent: Container) -> void:
	var tab := VBoxContainer.new()
	tab.name = "New Nodes"
	tab.add_theme_constant_override("separation", 12)
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(tab)
	new_nodes_view = tab

	var help := Label.new()
	help.text = "Create a ready-to-use 3D physics setup under the selected node, or under the scene root if nothing is selected."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(help)
	tab.add_child(HSeparator.new())

	setup_option = _add_option_row(tab, "Setup")
	for item in ["CharacterBody3D", "RigidBody3D", "StaticBody3D", "Area3D"]:
		setup_option.add_item(item)

	setup_collision_option = _add_option_row(tab, "Collision Shape")
	for item in ["Capsule", "Box", "Sphere", "Cylinder"]:
		setup_collision_option.add_item(item)

	setup_mesh_option = _add_option_row(tab, "Mesh")
	for item in ["Capsule", "Box", "Sphere", "Cylinder"]:
		setup_mesh_option.add_item(item)

	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Root Name"
	name_label.custom_minimum_size.x = 145
	name_row.add_child(name_label)
	setup_name_edit = LineEdit.new()
	setup_name_edit.placeholder_text = "Leave blank for default"
	setup_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(setup_name_edit)
	tab.add_child(name_row)

	setup_add_area_check = CheckBox.new()
	setup_add_area_check.text = "Add child Area3D + CollisionShape3D for collision detection testing"
	tab.add_child(setup_add_area_check)

	var note := Label.new()
	note.text = "Area3D setups already include their own CollisionShape3D, so the extra detection Area3D option is ignored."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate.a = 0.75
	tab.add_child(note)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(spacer)

	setup_status_label = Label.new()
	setup_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(setup_status_label)

	var button := Button.new()
	button.text = "Create Node Setup"
	button.pressed.connect(_create_node_setup)
	_style_primary_action(button, true)
	tab.add_child(button)


func _add_option_row(parent: VBoxContainer, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 145
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
	label.custom_minimum_size.x = 145
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


func _create_node_setup() -> void:
	var scene_root := plugin.get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		_set_setup_status("Open or create a scene first.", true)
		return

	var parent := _get_node_setup_parent(scene_root)
	var setup_name := setup_option.get_item_text(setup_option.selected)
	var root := _make_setup_root(setup_name)
	if root == null:
		_set_setup_status("Could not create the selected setup.", true)
		return

	var requested_name := setup_name
	if not setup_name_edit.text.strip_edges().is_empty():
		requested_name = setup_name_edit.text.strip_edges()
	root.name = _unique_child_name(parent, requested_name)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = _make_setup_collision_shape(setup_collision_option.get_item_text(setup_collision_option.selected))

	var mesh_instance: MeshInstance3D = null
	if not root is Area3D:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		mesh_instance.mesh = _make_setup_mesh(setup_mesh_option.get_item_text(setup_mesh_option.selected))

	var detection_area: Area3D = null
	var detection_collision: CollisionShape3D = null
	if not root is Area3D and setup_add_area_check.button_pressed:
		detection_area = Area3D.new()
		detection_area.name = "DetectionArea3D"
		detection_collision = CollisionShape3D.new()
		detection_collision.name = "CollisionShape3D"
		detection_collision.shape = _make_setup_collision_shape(setup_collision_option.get_item_text(setup_collision_option.selected))

	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("Create Asset Wizard Node Setup")
	undo_redo.add_do_method(parent, "add_child", root, true)
	undo_redo.add_do_method(root, "set_owner", scene_root)
	undo_redo.add_do_method(root, "add_child", collision, true)
	undo_redo.add_do_method(collision, "set_owner", scene_root)
	if mesh_instance != null:
		undo_redo.add_do_method(root, "add_child", mesh_instance, true)
		undo_redo.add_do_method(mesh_instance, "set_owner", scene_root)
	if detection_area != null:
		undo_redo.add_do_method(root, "add_child", detection_area, true)
		undo_redo.add_do_method(detection_area, "set_owner", scene_root)
		undo_redo.add_do_method(detection_area, "add_child", detection_collision, true)
		undo_redo.add_do_method(detection_collision, "set_owner", scene_root)
	undo_redo.add_do_method(plugin.get_editor_interface().get_selection(), "clear")
	undo_redo.add_do_method(plugin.get_editor_interface().get_selection(), "add_node", root)

	if detection_collision != null:
		undo_redo.add_undo_method(detection_area, "remove_child", detection_collision)
	if detection_area != null:
		undo_redo.add_undo_method(root, "remove_child", detection_area)
	if mesh_instance != null:
		undo_redo.add_undo_method(root, "remove_child", mesh_instance)
	undo_redo.add_undo_method(root, "remove_child", collision)
	undo_redo.add_undo_method(parent, "remove_child", root)
	undo_redo.commit_action()

	_set_setup_status("Created %s under %s. Use Undo to reverse it." % [root.name, parent.name], false)


func _get_node_setup_parent(scene_root: Node) -> Node:
	var selected := plugin.get_editor_interface().get_selection().get_selected_nodes()
	if selected.is_empty():
		return scene_root
	return selected[0]


func _make_setup_root(type_name: String) -> Node3D:
	match type_name:
		"CharacterBody3D": return CharacterBody3D.new()
		"RigidBody3D": return RigidBody3D.new()
		"Area3D": return Area3D.new()
		_: return StaticBody3D.new()


func _make_setup_collision_shape(shape_name: String) -> Shape3D:
	match shape_name:
		"Box": return BoxShape3D.new()
		"Sphere": return SphereShape3D.new()
		"Cylinder": return CylinderShape3D.new()
		_: return CapsuleShape3D.new()


func _make_setup_mesh(mesh_name: String) -> PrimitiveMesh:
	match mesh_name:
		"Box": return BoxMesh.new()
		"Sphere": return SphereMesh.new()
		"Cylinder": return CylinderMesh.new()
		_: return CapsuleMesh.new()


func _set_setup_status(message: String, is_error: bool) -> void:
	setup_status_label.text = message
	setup_status_label.modulate = Color(1.0, 0.45, 0.45) if is_error else Color(0.65, 1.0, 0.65)


func _select_option_text(option: OptionButton, text: String) -> void:
	for index in option.item_count:
		if option.get_item_text(index) == text:
			option.select(index)
			return
