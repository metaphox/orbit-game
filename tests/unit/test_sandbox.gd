extends GutTest
## SandboxStore tracks community-level progress in a separate string-ID namespace
## (community levels have no integer campaign index and don't participate in the
## next_after unlock chain — they're all unlocked, best result kept per ID).

const PATH := "user://test_sandbox.json"


func before_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_records_and_keeps_best_dv() -> void:
	var s := SandboxStore.new()
	s.record("my-level", "SILVER ★★", 244.0, false)
	assert_eq(s.medal_for("my-level"), "SILVER ★★")
	assert_almost_eq(s.best_dv("my-level"), 244.0, 0.001)
	# A better (lower-dv) run replaces it...
	s.record("my-level", "GOLD ★★★", 118.0, true)
	assert_eq(s.medal_for("my-level"), "GOLD ★★★", "a better run is kept")
	# ...a worse run does not.
	s.record("my-level", "BRONZE ★", 400.0, false)
	assert_eq(s.medal_for("my-level"), "GOLD ★★★", "a worse run is ignored")
	assert_almost_eq(s.best_dv("my-level"), 118.0, 0.001)


func test_unknown_id_is_blank() -> void:
	var s := SandboxStore.new()
	assert_eq(s.medal_for("never-played"), "", "no record => no medal")
	assert_true(s.is_unlocked("anything"), "community levels are always unlocked")


func test_round_trips_through_disk() -> void:
	var s := SandboxStore.new()
	s.record("alpha", "GOLD ★★★", 90.0, true)
	s.record("beta", "SILVER ★★", 210.0, false)
	assert_true(s.save(PATH), "save succeeds")

	var loaded := SandboxStore.load_or_new(PATH)
	assert_eq(loaded.medal_for("alpha"), "GOLD ★★★")
	assert_almost_eq(loaded.best_dv("beta"), 210.0, 0.001)
	assert_eq(loaded.medal_for("gamma"), "", "unknown id after load is blank")


func test_corrupt_file_starts_fresh() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("not json {{{")
	f.close()
	var s := SandboxStore.load_or_new(PATH)  # must not crash
	assert_eq(s.medal_for("x"), "", "a corrupt sandbox file loads as empty")
	assert_engine_error("Variant()", "malformed JSON logs an engine-level parse error")
	assert_push_error("is not valid JSON", "and SandboxStore logs its own detail")
