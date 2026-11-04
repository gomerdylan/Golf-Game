shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// This mesh is visible only to the minimap camera. Its deliberately excessive
// emission compensates for the tiny top-down presentation without changing the
// volumetric fog seen by the main gameplay camera.
uniform float emission_multiplier = 10.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * emission_multiplier;
	ALPHA = COLOR.a;
}
