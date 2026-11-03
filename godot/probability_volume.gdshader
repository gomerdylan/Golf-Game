shader_type fog;

uniform sampler2D probability_map : filter_linear, repeat_disable;
uniform float terrain_min_m = 0.0;
uniform float terrain_max_m = 1.0;
uniform float density_scale = 0.30;
uniform float cloud_height_m = 5.5;
uniform vec3 low_color : source_color = vec3(0.86, 0.06, 1.0);
uniform vec3 mid_color : source_color = vec3(1.0, 0.16, 0.025);
uniform vec3 warm_color : source_color = vec3(1.0, 0.42, 0.025);
uniform vec3 high_color : source_color = vec3(1.0, 0.78, 0.06);
uniform float emission_strength = 1.80;
uniform float disperse_progress : hint_range(0.0, 1.0) = 0.0;

float billow(vec3 position) {
	vec3 p = position * vec3(0.13, 0.30, 0.13);
	float broad = sin(p.x + TIME * 0.11) * sin(p.z - TIME * 0.08);
	float detail = sin(p.x * 2.17 - p.z * 1.31 + p.y * 1.73 + TIME * 0.17);
	return clamp(0.78 + broad * 0.14 + detail * 0.08, 0.50, 1.0);
}

void fog() {
	// The CPU packs the course-space density into R and normalized terrain
	// height into G. Texture axes already match FogVolume UVW.xz.
	vec2 map_data = texture(probability_map, UVW.xz).rg;
	float probability = map_data.r;
	float terrain_height = mix(terrain_min_m, terrain_max_m, map_data.g);
	// During the post-shot flourish, sample the vertical profile from below so
	// the body appears to lift before it evaporates.
	float dispersal_lift_m = disperse_progress * 3.5;
	float above_ground = WORLD_POSITION.y - terrain_height - dispersal_lift_m;

	float ground_fade = smoothstep(-0.15, 0.30, above_ground);
	float height_fade = 1.0 - smoothstep(cloud_height_m * 0.35, cloud_height_m, above_ground);
	// Probability tails need a nonlinear display curve, just like a scientific
	// heatmap. Otherwise their optical depth vanishes when the volume occupies
	// only a few distant froxels. This does not alter the underlying data.
	float display_probability = pow(clamp(probability, 0.0, 1.0), 0.52);
	float evaporate = 1.0 - smoothstep(0.12, 1.0, disperse_progress);
	float breakup = mix(
		1.0,
		smoothstep(0.56, 0.90, billow(WORLD_POSITION * 1.45)),
		disperse_progress
	);
	// Keep the tails legible while preventing the hottest core from becoming
	// an opaque wall. The core retains more color and brightness than its
	// surroundings, but contributes less additional optical depth.
	float core_transparency = mix(
		1.0, 0.68, smoothstep(0.58, 1.0, probability)
	);
	float body = (
		display_probability
		* ground_fade
		* height_fade
		* billow(WORLD_POSITION)
		* evaporate
		* breakup
		* core_transparency
	);
	float heat = pow(clamp(probability, 0.0, 1.0), 0.58);
	vec3 color;
	if (heat < 0.55) {
		color = mix(low_color, mid_color, heat / 0.55);
	} else if (heat < 0.90) {
		color = mix(mid_color, warm_color, (heat - 0.55) / 0.35);
	} else {
		color = mix(warm_color, high_color, smoothstep(0.90, 1.0, heat));
	}

	DENSITY = body * density_scale;
	ALBEDO = color;
	// Emission preserves the probability palette instead of allowing bright
	// terrain and sunlight to wash the single-scattered fog toward gray.
	EMISSION = color * body * emission_strength;
}
