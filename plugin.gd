@tool
extends EditorPlugin

const BuilderWindow := preload("res://addons/asset_wizard/builder_window.gd")

var builder_window: Window


func _enter_tree() -> void:
	add_tool_menu_item("Asset Wizard", _open_builder)

	var selection := get_editor_interface().get_selection()
	if selection != null and not selection.selection_changed.is_connected(_on_context_changed):
		selection.selection_changed.connect(_on_context_changed)

	var filesystem := get_editor_interface().get_file_system_dock()
	if filesystem != null and filesystem.has_signal("selection_changed"):
		if not filesystem.selection_changed.is_connected(_on_context_changed):
			filesystem.selection_changed.connect(_on_context_changed)


func _exit_tree() -> void:
	remove_tool_menu_item("Asset Wizard")

	var selection := get_editor_interface().get_selection()
	if selection != null and selection.selection_changed.is_connected(_on_context_changed):
		selection.selection_changed.disconnect(_on_context_changed)

	var filesystem := get_editor_interface().get_file_system_dock()
	if filesystem != null and filesystem.has_signal("selection_changed"):
		if filesystem.selection_changed.is_connected(_on_context_changed):
			filesystem.selection_changed.disconnect(_on_context_changed)

	if is_instance_valid(builder_window):
		builder_window.queue_free()


func _open_builder() -> void:
	if not is_instance_valid(builder_window):
		builder_window = BuilderWindow.new()
		builder_window.setup(self)
		get_editor_interface().get_base_control().add_child(builder_window)
	builder_window.refresh_context()
	builder_window.popup_centered()


func _on_context_changed() -> void:
	if is_instance_valid(builder_window) and builder_window.visible:
		builder_window.call_deferred("refresh_context")
