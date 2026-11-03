shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D bubble_texture : source_color, filter_linear;
uniform float bob_amplitude_m = 0.75;
uniform float bob_period_s = 7.0;
uniform float emission_strength = 0.55;
uniform float opacity_multiplier = 1.0;
uniform float disperse_progress : hint_range(0.0, 1.0) = 0.0;

float hash_position(vec2 position) {
	return fract(sin(dot(position, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 instance_position = MODEL_MATRIX[3].xyz;
	float random_value = hash_position(instance_position.xz);
	float phase = random_value * TAU;
	float speed_variation = mix(0.78, 1.25, hash_position(instance_position.zx + 19.7));
	float amplitude_variation = mix(0.55, 1.35, random_value);
	float angular_speed = TAU / max(bob_period_s, 0.01);
	float bob = sin(TIME * angular_speed * speed_variation + phase);
	instance_position.y += bob * bob_amplitude_m * amplitude_variation;
	// A brief lava-lamp flourish reveals the final lie: bubbles spiral outward,
	// rise at varied speeds, then evaporate with the continuous volume.
	float spiral_angle = phase + disperse_progress * TAU * mix(0.45, 1.1, random_value);
	float outward_m = disperse_progress * disperse_progress * mix(1.0, 4.0, random_value);
	instance_position.x += cos(spiral_angle) * outward_m;
	instance_position.z += sin(spiral_angle) * outward_m;
	instance_position.y += disperse_progress * mix(2.0, 5.5, random_value);

	// Build a camera-facing transform while preserving each MultiMesh
	// instance's nonuniform scale. Only the center bobs; the quad remains soft
	// and billboarded toward the active camera.
	vec3 instance_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	mat4 billboard_model = mat4(
		INV_VIEW_MATRIX[0] * instance_scale.x,
		INV_VIEW_MATRIX[1] * instance_scale.y,
		INV_VIEW_MATRIX[2] * instance_scale.z,
		vec4(instance_position, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard_model;
}

void fragment() {
	vec4 texture_color = texture(bubble_texture, UV);
	vec3 color = COLOR.rgb * texture_color.rgb;
	ALBEDO = color;
	EMISSION = color * emission_strength;
	float evaporate = 1.0 - smoothstep(0.18, 1.0, disperse_progress);
	ALPHA = COLOR.a * texture_color.a * opacity_multiplier * evaporate;
}
