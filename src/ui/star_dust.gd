class_name StarDust
extends GPUParticles3D
## Stylized dust motes streaking past the ship to sell velocity. Purely
## visual: streak speed is a scaled-down echo of the real orbital speed
## (1:1 would be an invisible blur). Lives in the floating-origin flight
## world, so the emitter sits at the ship's render position (origin).

const SPEED_SCALE := 0.06
const MIN_STREAK_SPEED := 8.0
const MAX_STREAK_SPEED := 120.0

var _mat: ParticleProcessMaterial


func build() -> void:
	_mat = ParticleProcessMaterial.new()
	_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mat.emission_box_extents = Vector3(55, 55, 55)
	_mat.spread = 4.0
	_mat.gravity = Vector3.ZERO
	_mat.particle_flag_align_y = true  # streaks align with their velocity
	process_material = _mat

	var streak := BoxMesh.new()
	streak.size = Vector3(0.05, 2.4, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.65, 0.8, 1.0, 0.35)
	streak.material = mat
	draw_pass_1 = streak

	amount = 240
	lifetime = 2.2
	local_coords = false
	emitting = true


## v_dir is the ship's velocity direction in render space; dust flows the
## opposite way. Only newly spawned particles pick up the change, which
## reads as a pleasant lag rather than a bug.
func update_motion(v_dir: Vector3, speed: float) -> void:
	_mat.direction = -v_dir
	var streak_speed := clampf(
		speed * SPEED_SCALE, MIN_STREAK_SPEED, MAX_STREAK_SPEED)
	_mat.initial_velocity_min = streak_speed * 0.7
	_mat.initial_velocity_max = streak_speed * 1.3
