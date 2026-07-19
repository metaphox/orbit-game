extends "res://tests/unit/base_orbit_test.gd"


func test_basic_ops() -> void:
	var a := DVec3.new(1.0, 2.0, 3.0)
	var b := DVec3.new(-4.0, 5.0, 0.5)
	assert_dvec_close(a.add(b), DVec3.new(-3.0, 7.0, 3.5))
	assert_dvec_close(a.sub(b), DVec3.new(5.0, -3.0, 2.5))
	assert_dvec_close(a.scaled(2.0), DVec3.new(2.0, 4.0, 6.0))
	assert_close(a.dot(b), 7.5)
	assert_dvec_close(a.cross(b), DVec3.new(-14.0, -12.5, 13.0))
	assert_close(DVec3.new(3.0, 4.0, 0.0).length(), 5.0)
	assert_close(a.normalized().length(), 1.0)


func test_double_precision_survives_interplanetary_scale() -> void:
	# 2.3e10 m apart, 1 mm resolved — float32 would collapse this to 0.
	var far := DVec3.new(2.3e10, 0.0, 0.0)
	var nudged := DVec3.new(2.3e10 + 0.001, 0.0, 0.0)
	assert_close(nudged.sub(far).x, 0.001, 1e-6)
