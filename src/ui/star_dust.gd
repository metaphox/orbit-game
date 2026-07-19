class_name StarDust
extends GPUParticles3D
## Dust motes streaking past the ship, their speed proportional to the real
## orbital speed (full 1:1 proved overwhelming). Short lifetimes keep the
## field refilled around the floating-origin ship (emitter pinned at the
## render origin).

const SPEED_FACTOR := 0.2

var _mat: ParticleProcessMaterial


func build() -> void:
	_mat = ParticleProcessMaterial.new()
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mat.emission_box_extents = Vector3(140, 140, 140)
	_mat.spread = 2.0
	_mat.gravity = Vector3.ZERO
	_mat.particle_flag_align_y = true  # streaks align with their velocity
	process_material = _mat

	var streak := BoxMesh.new()
	streak.size = Vector3(0.03, 4.0, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.65, 0.8, 1.0, 0.16)
	streak.material = mat
	draw_pass_1 = streak

	amount = 800
	lifetime = 0.45
	local_coords = false
	emitting = true


## v_dir is the ship's velocity direction in render space; dust flows the
## opposite way, scaled by SPEED_FACTOR. Only newly spawned particles pick
## up a velocity change, which reads as a natural lag.
func update_motion(v_dir: Vector3, speed: float) -> void:
	_mat.direction = -v_dir
	var dust_speed := speed * SPEED_FACTOR
	_mat.initial_velocity_min = maxf(dust_speed * 0.97, 1.0)
	_mat.initial_velocity_max = maxf(dust_speed * 1.03, 1.0)
