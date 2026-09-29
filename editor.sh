#!/bin/sh
# Launch the Godot editor with a Beckett MCP tool allowlist. This narrows the tools a
# caller can reach directly; it is not a security boundary, since the allowed
# write_script/write_file + play_scene tools still run arbitrary GDScript by design.
# Excluded: tools that read outside the project or call arbitrary methods
# (read_file, list_dir, read_script, search_files, validate_script, call_method,
# batch_execute, build_csharp, logs_read: it reads any path).
# Opening the project any other way (Project Manager, plain `godot -e`) skips the allowlist.
export BECKETT_ALLOWLIST='^apply_template$,^attach_script$,^connect_signal$,^create_node$,^create_resource$,^delete_node$,^describe_class$,^describe_object$,^disconnect_signal$,^doctor$,^duplicate_node$,^find_classes$,^find_methods$,^find_nodes$,^game_logs$,^get_godot_version$,^get_performance_monitors$,^get_play_state$,^get_project_setting$,^get_project_statistics$,^get_remote_tree$,^get_scene_tree$,^help$,^instance_scene$,^list_signals$,^monitor_properties$,^move_node$,^open_scene$,^play_scene$,^rename_node$,^render_probe$,^reparent_node$,^runtime_get_property$,^save_scene$,^screenshot$,^script_patch$,^set_project_setting$,^set_debug_draw$,^set_property$,^set_resource$,^stop_scene$,^ui_snapshot$,^wait_for_node$,^wait_until$,^write_file$,^write_script$'
exec godot --editor --path "$(dirname "$0")" "$@"
