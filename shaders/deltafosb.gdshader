// DeltaFosB — the game's look. A grim, clinical office: everything drained under sick
// fluorescent light, crushed blacks, grain and a heavy vignette. Only blood keeps its colour.
// Applied full-screen by scripts/effects/post_fx.gd (toggle in Settings). Every number is a
// uniform, so you can tweak it on the material in the Inspector while the game runs.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

group_uniforms Colour;
uniform float desaturation : hint_range(0.0, 1.0) = 0.72;      // 1 = black and white
uniform vec3 tint : source_color = vec3(0.74, 0.9, 0.84);       // cold fluorescent green-teal
uniform float blood_keep : hint_range(0.0, 1.0) = 0.9;          // how much red survives the drain
uniform float contrast = 1.3;
uniform float black_crush : hint_range(0.0, 0.3) = 0.07;        // darks sink to black
uniform float brightness = 1.08;
uniform float posterize_levels = 28.0;                          // colour banding (lower = more PSX)

group_uniforms Lens;
uniform float vignette : hint_range(0.0, 1.0) = 0.6;
uniform float aberration = 0.003;                               // colour fringe at the edges

group_uniforms Grit;
uniform float grain : hint_range(0.0, 0.3) = 0.07;
uniform float flicker : hint_range(0.0, 0.5) = 0.08;            // occasional fluorescent dip
uniform float scanlines : hint_range(0.0, 0.3) = 0.04;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float dist = length(c);

	// Colour fringe, stronger toward the edges (none in the centre).
	vec2 off = c * aberration * dist * 6.0;
	vec3 col = vec3(
		texture(screen_tex, uv + off).r,
		texture(screen_tex, uv).g,
		texture(screen_tex, uv - off).b);

	// How "blood red" this pixel is: red clearly above green and blue.
	float redness = clamp((col.r - max(col.g, col.b)) * 3.0, 0.0, 1.0) * blood_keep;

	// Drain the colour and bathe it in fluorescent tint (blood is spared).
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 drained = mix(col, vec3(lum), desaturation * (1.0 - redness));
	drained *= mix(tint, vec3(1.0, 0.92, 0.92), redness);

	// Hard, clinical contrast with crushed blacks.
	drained = (drained - 0.5) * contrast + 0.5;
	drained = max(drained - black_crush, vec3(0.0)) / (1.0 - black_crush);
	drained *= brightness;

	// Slight colour banding.
	drained = floor(drained * posterize_levels + 0.5) / posterize_levels;

	// Fluorescent tube flicker: every so often the whole room dips for a moment.
	float slot = floor(TIME * 9.0);
	float dip = step(0.94, hash(vec2(slot, 3.7)));
	drained *= 1.0 - flicker * dip;

	// Faint scanlines.
	drained *= 1.0 - scanlines * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));

	// Heavy vignette.
	drained *= mix(1.0, 1.0 - vignette, smoothstep(0.3, 0.85, dist));

	// Film grain.
	drained += (hash(uv * 1000.0 + fract(TIME) * 37.0) - 0.5) * grain;

	COLOR = vec4(clamp(drained, 0.0, 1.0), 1.0);
}
