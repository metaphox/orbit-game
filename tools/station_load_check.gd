extends SceneTree
## Headless smoke test: every generated station scene loads and instances with
## its materials resolving. Run:
##   godot --headless --script tools/station_load_check.gd
## Exits non-zero if any scene fails to load/instance.


func _init() -> void:
	var dir := DirAccess.open("res://assets/stations")
	if dir == null:
		push_error("no assets/stations directory")
		quit(1)
		return
	var fails := 0
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		n += 1
		var packed: PackedScene = load("res://assets/stations/" + f)
		if packed == null:
			push_error("FAILED to load: " + f)
			fails += 1
			continue
		var node: Node = packed.instantiate()
		if node == null:
			push_error("FAILED to instance: " + f)
			fails += 1
			continue
		print("  ok  %-34s %d parts" % [f, node.get_child_count()])
		node.free()
	print("station load-check: %d/%d scenes loaded" % [n - fails, n])
	quit(1 if fails else 0)
