shader_type spatial;

// alpha–blend only, never write depth, back‐face cull, no built-in lighting
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform sampler2D normal_map ;       // for little wave‐normal details

// pick your blue in the inspector:
uniform vec3    water_color   : source_color       = vec3(0.0, 0.3, 0.7);
// control transparency in the inspector:
uniform float   water_alpha   : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // flat‐colored water:
    ALBEDO     = water_color;
    ALPHA      = water_alpha;
    // normal bumps for a little fake wave detail:
    NORMAL_MAP = texture(normal_map, UV).xyz;
}