extends SceneTree
## Headless smoke test: every generated station scene loads and instances with
## its materials resolving. Run:
##   godot --headless --script tools/station_load_check.gd
## Exits non-zero if any scene fails to load/instance.

const STATION_DIRS: Array[String] = [
	"assets/stations",
	"assets/station_review",
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
			print("  ok  %-68s %d parts" % [scene_path, node.get_child_count()])
			node.free()
	print("station load-check: %d/%d scenes loaded" % [n - fails, n])
	quit(1 if fails else 0)
