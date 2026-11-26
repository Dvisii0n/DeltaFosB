// Bullet time "focus": the edges of the screen close in (dark, cold), the centre stays clear.
// `strength` is animated 0 -> 1 by the player when bullet time starts / ends.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(0.0, 0.03, 0.08, 0.92);  // colour at the very edge
uniform vec4 center_tint : source_color = vec4(0.3, 0.5, 1.0, 0.06);   // faint wash over everything
uniform float inner : hint_range(0.0, 1.0) = 0.22;   // clear area around the centre
uniform float outer : hint_range(0.0, 1.5) = 0.78;   // where the edge is fully dark

void fragment() {
	float d = length(UV - 0.5) * 1.41421;            // 0 centre .. 1 corners
	float edge = smoothstep(inner, outer, d);
	vec4 col = mix(center_tint, edge_color, edge);
	COLOR = vec4(col.rgb, col.a * strength);
}
