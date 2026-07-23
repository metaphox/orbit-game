extends "res://tests/unit/base_orbit_test.gd"
## Celestial-body invariants that must hold for EVERY level (present and future),
## so a new level can't silently reintroduce bugs like the Mare Serenitatis "two
## suns". Each test builds the real BodyRenderer for every campaign level and
## checks an assumption about what ends up in the sky.
##
## The rules:
##   - exactly one sun per level (a real star XOR a decorative one, never both/none);
##   - a decorative body is only added when the system lacks a real one, so no
##     unique body (Sun/Earth/Moon/Mars) is ever rendered twice;
##   - the decorative sun models an infinitely-distant light, so it stays on the
##     sunlight direction from the ship (no parallax split from the sky/lighting).

## Bodies that are a single named object - each may appear at most once across the
## real bodies and the decorative ones. (Generic bodies may legitimately repeat.)
const UNIQUE_KINDS := [
	BodyRenderer.BODY_EARTH, BodyRenderer.BODY_MOON,
	BodyRenderer.BODY_SUN, BodyRenderer.BODY_MARS]


func _renderer_for(index: int) -> BodyRenderer:
	var br := BodyRenderer.new()
	add_child_autofree(br)
	br.build(Campaign.level_at(index), RenderTheme.default())
	return br


## Kinds of the real (gravity-bearing) bodies the level defines.
func _real_kinds(br: BodyRenderer) -> Array:
	var kinds: Array = []
	for body: BodyDef in br._bodies:
		kinds.append(BodyRenderer._body_kind(body.name))
	return kinds


func _count(arr: Array, value: int) -> int:
	var n := 0
	for v: int in arr:
		if v == value:
			n += 1
	return n


func test_every_level_has_exactly_one_sun() -> void:
	for i: int in Campaign.level_count():
		var title: String = Campaign.title(i)
		var br := _renderer_for(i)
		var suns := _count(_real_kinds(br), BodyRenderer.BODY_SUN) \
			+ _count(br._ambient_kinds, BodyRenderer.BODY_SUN)
		assert_eq(suns, 1, "%s: exactly one sun (real or decorative), never two or zero" % title)


func test_decorative_sun_present_exactly_when_the_system_has_no_real_star() -> void:
	for i: int in Campaign.level_count():
		var title: String = Campaign.title(i)
		var br := _renderer_for(i)
		var has_real_sun := _count(_real_kinds(br), BodyRenderer.BODY_SUN) > 0
		assert_eq(br.has_sun, not has_real_sun,
			"%s: a decorative sun is added iff the system lacks a real one" % title)
		assert_eq(br._sun_mesh != null, br.has_sun,
			"%s: the decorative sun mesh exists iff has_sun" % title)


func test_no_unique_body_is_rendered_twice() -> void:
	# Guards the whole class of "decorative X added even though a real X exists"
	# bugs (e.g. a decorative Moon on a level that already has the real Moon).
	for i: int in Campaign.level_count():
		var title: String = Campaign.title(i)
		var br := _renderer_for(i)
		var all_kinds: Array = _real_kinds(br) + br._ambient_kinds
		for kind: int in UNIQUE_KINDS:
			assert_lte(_count(all_kinds, kind), 1,
				"%s: body kind %d appears at most once across real + decorative" % [title, kind])


func test_decorative_sun_tracks_the_light_direction_on_every_level() -> void:
	# The exact Mare Serenitatis fix, generalised: wherever the ship is - even
	# millions of units off the root origin and off the light axis - the sun disc
	# must sit on sun_dir, so it never parallax-splits from the sky wash / light.
	var far_off_axis := DVec3.new(6.0e6, 4.0e6, -5.0e6)
	for i: int in Campaign.level_count():
		var title: String = Campaign.title(i)
		var br := _renderer_for(i)
		if not br.has_sun:
			continue
		br.sync(0.0, far_off_axis, false)  # chase view: ambient bodies shown
		assert_gt(br._sun_mesh.position.normalized().dot(br.sun_dir), 0.9999,
			"%s: decorative sun stays on the light direction, not parallax-shifted" % title)
