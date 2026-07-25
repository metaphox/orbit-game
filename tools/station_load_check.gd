extends SceneTree
## Headless smoke test: every generated station scene loads and instances with
## its materials resolving. Run:
##   godot --headless --script tools/station_load_check.gd
## Exits non-zero if any scene fails to load/instance.

const STATION_DIRS: Array[String] = [
	"assets/stations",
	"assets/station_review",
	"assets/station_brand_review",
]


func _init() -> void:
	var fails := 0
	var n := 0
	for station_dir: String in STATION_DIRS:
		var dir := DirAccess.open("res://" + station_dir)
		if dir == null:
			push_error("no " + station_dir + " directory")
			fails += 1
			continue
		for file_name: String in dir.get_files():
			if not file_name.ends_with(".tscn"):
				continue
			n += 1
			var scene_path := "res://" + station_dir + "/" + file_name
			var packed: PackedScene = load(scene_path)
			if packed == null:
				push_error("FAILED to load: " + scene_path)
				fails += 1
				continue
			var node: Node = packed.instantiate()
			if node == null:
				push_error("FAILED to instance: " + scene_path)
				fails += 1
				continue
			var transform_fails := _check_blueprint_transforms(scene_path, node)
			if transform_fails > 0:
				fails += transform_fails
				node.free()
				continue
			print("  ok  %-68s %d parts" % [scene_path, node.get_child_count()])
			node.free()
	print("station load-check: %d/%d scenes loaded" % [n - fails, n])
	quit(1 if fails else 0)


func _check_blueprint_transforms(scene_path: String, node: Node) -> int:
	var blueprint_path := scene_path.trim_suffix(".tscn") + ".json"
	if not FileAccess.file_exists(blueprint_path):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(blueprint_path))
	if not parsed is Dictionary:
		push_error("FAILED to parse blueprint: " + blueprint_path)
		return 1
	var blueprint: Dictionary = parsed
	var parts: Array = blueprint.get("parts", [])
	if parts.is_empty() or not (parts[0] as Dictionary).has("cols"):
		return 0
	if parts.size() != node.get_child_count():
		push_error("BLUEPRINT part count differs: " + scene_path)
		return 1
	var game_scale := float(blueprint.get("game_scale", 1.0))
	for part_index: int in parts.size():
		var part: Dictionary = parts[part_index]
		var cols: Array = part["cols"]
		var x_values: Array = cols[0]
		var y_values: Array = cols[1]
		var z_values: Array = cols[2]
		var pos_values: Array = part["pos"]
		var expected_x := Vector3(float(x_values[0]), float(x_values[1]), float(x_values[2]))
		var expected_y := Vector3(float(y_values[0]), float(y_values[1]), float(y_values[2]))
		var expected_z := Vector3(float(z_values[0]), float(z_values[1]), float(z_values[2]))
		var expected_origin := Vector3(
			float(pos_values[0]), float(pos_values[1]), float(pos_values[2])) * game_scale
		var child := node.get_child(part_index) as Node3D
		if child == null:
			push_error("BLUEPRINT child is not Node3D: " + scene_path)
			return 1
		if child.basis.x.distance_to(expected_x) > 0.001 \
				or child.basis.y.distance_to(expected_y) > 0.001 \
				or child.basis.z.distance_to(expected_z) > 0.001 \
				or child.position.distance_to(expected_origin) > 0.001:
			push_error("BLUEPRINT transform mismatch: %s part %d" % [scene_path, part_index])
			return 1
	return 0
