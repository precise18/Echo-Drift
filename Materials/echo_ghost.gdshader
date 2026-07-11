shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_opaque, shadows_disabled;

// The whole "this is supernatural" read, in one cheap material.
// Deliberately unshaded (no lighting math at all) and samples no
// textures — every effect below is a handful of sines/cosines on the
// vertex and fragment, which is what keeps this safe on the GL
// Compatibility renderer this project ships with (see project.godot)
// and cheap enough to run on every ghost every frame. See
// ECHO_VISUAL_GUIDE.md "The distortion shader" for the plain-English
// version of each uniform below.

uniform vec4 base_color : source_color = vec4(0.55, 0.95, 1.0, 0.42);
uniform vec4 rim_color : source_color = vec4(0.75, 1.0, 1.0, 1.0);
uniform float wobble_amount : hint_range(0.0, 0.15) = 0.028;
uniform float wobble_speed : hint_range(0.0, 10.0) = 2.2;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.1;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.16;
uniform float rim_power : hint_range(0.1, 8.0) = 2.2;
uniform float shimmer_speed : hint_range(0.0, 12.0) = 5.5;
// 1.0 = fully materialized, 0.0 = fully dissolved. Driven from
// EchoGhost.gd's spawn-pulse / dissolve tweens — a single float is the
// whole hand-off between script and shader for both effects.
uniform float dissolve : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// A gentle standing-wave waver along the body's height reads as a
	// spectral flicker rather than a mesh glitch — one sine/cosine pair
	// per vertex, nothing per-pixel.
	float wave = sin(TIME * wobble_speed + VERTEX.y * 3.0);
	VERTEX.x += wave * wobble_amount * dissolve;
	VERTEX.z += cos(TIME * wobble_speed * 0.8 + VERTEX.y * 3.0) * wobble_amount * dissolve;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;

	// A narrow, fast-moving bright band travelling up the body — the
	// "reflection shimmer": an intermittent glint rather than a constant
	// glow, like light catching a moving water surface.
	float shimmer = pow(max(sin(TIME * shimmer_speed + VERTEX.y * 9.0), 0.0), 10.0);

	vec3 emission_color = mix(base_color.rgb, rim_color.rgb, fresnel);
	emission_color += rim_color.rgb * shimmer * 0.6;

	ALBEDO = base_color.rgb;
	EMISSION = emission_color * pulse;
	ALPHA = base_color.a * pulse * dissolve;
}
