shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 low_color : source_color = vec4(0.07, 0.01, 0.24, 1.0);
uniform vec4 high_color : source_color = vec4(1.00, 0.32, 0.025, 1.0);
uniform float animation_speed = 0.10;

varying vec3 world_position;


float hash_2d(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float a = hash_2d(cell);
	float b = hash_2d(cell + vec2(1.0, 0.0));
	float c = hash_2d(cell + vec2(0.0, 1.0));
	float d = hash_2d(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}


float cloud_noise(vec2 point) {
	float result = 0.0;
	result += 0.55 * value_noise(point);
	result += 0.30 * value_noise(point * 2.03 + 13.7);
	result += 0.15 * value_noise(point * 4.11 + 29.2);
	return result;
}


void vertex() {
	// Red stores probability density; alpha stores the opacity of this layer.
	float probability = COLOR.r;
	VERTEX.y += probability * 0.9;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float probability = clamp(COLOR.r, 0.0, 1.0);
	vec2 drift = TIME * animation_speed * vec2(0.45, 0.22);
	float noise_value = cloud_noise(world_position.xz * 0.085 + drift);
	float broken_density = probability * mix(0.58, 1.18, noise_value);
	float soft_shape = smoothstep(0.012, 0.20, broken_density);
	float core = pow(probability, 0.58);
	ALBEDO = mix(low_color.rgb, high_color.rgb, core);
	EMISSION = ALBEDO * mix(0.10, 0.42, core);
	ALPHA = soft_shape * mix(0.09, 0.42, core) * COLOR.a;
}
