// Tilt-shift depth-of-field post effect (screen-space): sharp horizontal band around the focus (the renderer
// moves focus_y to the player's screen row), blur grows above and below it, plus a slight saturation lift for the
// miniature look. 12-tap golden-angle disc; strength = blur radius in pixels at the band's far end.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float focus_y = 0.56;
uniform float band = 0.14;
uniform float strength = 14.0;
uniform float saturation = 1.12;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = clamp((abs(uv.y - focus_y) - band) / (1.0 - band), 0.0, 1.0);
	float r = pow(t, 1.5) * strength;
	vec3 acc = texture(screen_tex, uv).rgb;
	float n = 1.0;
	if (r > 0.05) {
		for (int i = 0; i < 12; i++) {
			float fi = float(i);
			float ang = fi * 2.39996;
			float rad = sqrt((fi + 0.5) / 12.0) * r;
			acc += texture(screen_tex, uv + vec2(cos(ang), sin(ang)) * rad * SCREEN_PIXEL_SIZE).rgb;
			n += 1.0;
		}
	}
	vec3 c = acc / n;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(l), c, saturation), 1.0);
}
