shader_type spatial;

uniform float height = 64.0;
uniform sampler2D color_gradient;
uniform sampler2D normal_map;
uniform float winter_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 snow_color : source_color = vec3(0.95, 0.95, 1.0);

void fragment() {
	vec4 world_vertex = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 model_vertex = (inverse(MODEL_MATRIX) * world_vertex).xyz;
	float gradient_uv = (model_vertex.y / height) + 0.5;
	
	// Get base terrain color
	vec3 base_color = texture(color_gradient, vec2(gradient_uv)).rgb;
	
	// Blend with snow color based on winter_factor
	// Higher elevations get more snow
	float elevation_factor = clamp(gradient_uv, 0.0, 1.0);
	float snow_intensity = winter_factor * (0.7 + 0.3 * elevation_factor);
	
	ALBEDO = mix(base_color, snow_color, snow_intensity);
	NORMAL_MAP = texture(normal_map, UV).xyz;
}
