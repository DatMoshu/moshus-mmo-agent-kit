// VoxelRenderer3D surface shader: unshaded diorama colours. Ground faces look their colour up per voxel:
// data_tex (per chunk: EGA index, category, AO level) -> pal_tex (category x EGA -> colour, flags; column 16 =
// the category's cliff-side colour). Canopy faces carry a vertex colour. Plus:
// world curvature, water shimmer, glow pulse, optional top-face tile grid, and presentation-only LOS:
// tiles outside line of sight dim to ~15% and desaturate (geometry, i.e. the voxel silhouettes, stays).
// Polish (each behind a uniform the renderer sets from its options): deterministic top-colour variation for
// categories with a palette "vary" amount (column 16 alpha), shore foam on water next to land (data B bits 2-3),
// and distance haze toward the background colour so the curved horizon fades instead of ending in a hard edge.
shader_type spatial;
render_mode unshaded, cull_back, skip_vertex_transform;

uniform vec3 curve_center = vec3(0.0);
uniform float curve_k = 0.0035;
uniform float ao_strength = 1.0;
uniform bool grid_on = false;
uniform bool los_on = true;
uniform sampler2D los_tex : filter_linear, repeat_disable;
uniform vec2 los_origin = vec2(0.0);
uniform float los_size = 1.0;
uniform float dim = 0.15;
uniform float gamma = 1.0;
uniform sampler2D data_tex : filter_nearest, repeat_disable;
uniform sampler2D pal_tex : filter_nearest, repeat_disable;
uniform int data_n = 512;
uniform bool true_black = false;
uniform bool vary_on = true;
uniform bool foam_on = true;
uniform bool fog_on = true;
uniform vec3 fog_color : source_color = vec3(0.36, 0.42, 0.50);
uniform float fog_start = 12.0;
uniform float fog_end = 32.0;
uniform float fog_max = 0.8;
uniform float wrap_span = 4096.0; // world width for the variation hash (256 on the wrapping overworld)

varying vec3 wpos;
varying float vflags;
varying float vao;
varying vec2 vtex;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = w;
	vec2 dd = w.xz - curve_center.xz;
	w.y -= dot(dd, dd) * curve_k;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	vflags = UV.y;
	vao = UV.x;
	vtex = UV2;
}

const float AO_LV[4] = float[4](1.0, 0.8, 0.66, 0.54);

float hash2(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	int f = int(vflags + 0.5);
	vec3 c;
	if ((f & 8) != 0) {
		ivec2 t = clamp(ivec2(floor(vtex)), ivec2(0), ivec2(data_n - 1));
		vec4 d = texelFetch(data_tex, t, 0);
		int e = int(d.r * 255.0 + 0.5);
		int cat = int(d.g * 255.0 + 0.5);
		int ab = int(d.b * 255.0 + 0.5);
		int ao = ab & 3;
		int shore = ab >> 2;
		vec4 p = texelFetch(pal_tex, ivec2(e, cat), 0);
		int pf = int(p.a * 255.0 + 0.5);
		c = p.rgb;
		if (true_black && e == 0 && (pf & 2) == 0) {
			c = vec3(0.0);
		}
		if ((f & 16) != 0) { // cliff side: top colour band, then the category's side colour darkening downward
			if (wpos.y < vao - 0.001) {
				c = texelFetch(pal_tex, ivec2(16, cat), 0).rgb;
				c *= mix(1.0, mix(0.72, 1.0, clamp(1.0 - (vao - wpos.y) / 0.5, 0.0, 1.0)), ao_strength);
			}
			pf &= 4; // sides never shimmer
		} else {
			if (vary_on && (pf & 8) != 0) { // two octaves: 4-pixel clumps and whole tiles, stable in world space
				float amt = texelFetch(pal_tex, ivec2(16, cat), 0).a;
				vec2 q = mod(floor(wpos.xz * 4.0), wrap_span * 4.0);
				vec2 tq = mod(floor(wpos.xz), wrap_span);
				float v = (hash2(q) - 0.5) * 1.2 + (hash2(tq + 17.0) - 0.5) * 0.8;
				c *= 1.0 + amt * v;
				c.g *= 1.0 + amt * 0.4 * (hash2(tq + 91.0) - 0.5);
			}
			c *= mix(1.0, AO_LV[clamp(ao, 0, 3)], ao_strength);
			if (foam_on && shore > 0) {
				float w = shore == 2 ? 0.75 : 0.32;
				float pulse = 0.65 + 0.35 * sin(TIME * 2.1 + (wpos.x + wpos.z) * 2.6);
				c = mix(c, vec3(0.86, 0.94, 1.0), w * pulse);
			}
		}
		f |= pf;
		c *= COLOR.r;
	} else {
		c = COLOR.rgb * mix(1.0, vao, ao_strength);
	}
	if ((f & 2) != 0) {
		float a = sin(wpos.x * 1.9 + wpos.z * 2.7 + TIME * 1.7);
		float b = sin(wpos.x * -2.3 + wpos.z * 1.4 - TIME * 1.2);
		float wv = a * 0.5 + 0.5;
		c *= 0.86 + 0.2 * wv * (b * 0.5 + 0.5);
		c += vec3(0.02, 0.05, 0.08) * pow(wv, 6.0);
	}
	if ((f & 4) != 0) {
		c *= 1.0 + 0.25 * sin(TIME * 3.0 + wpos.x + wpos.z);
	}
	if (grid_on && (f & 1) != 0) {
		vec2 fr = fract(wpos.xz);
		float e = min(min(fr.x, 1.0 - fr.x), min(fr.y, 1.0 - fr.y));
		c *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.03, e));
	}
	if (los_on) {
		vec2 lu = (wpos.xz - los_origin) / los_size;
		float v = 0.0;
		if (lu.x >= 0.0 && lu.y >= 0.0 && lu.x <= 1.0 && lu.y <= 1.0) {
			v = texture(los_tex, lu).r;
		}
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 occ = mix(vec3(lum), c, 0.2) * dim;
		c = mix(occ, c, v);
	}
	if (fog_on) {
		float fd = length(wpos.xz - curve_center.xz);
		c = mix(c, fog_color, smoothstep(fog_start, fog_end, fd) * fog_max);
	}
	ALBEDO = pow(c, vec3(gamma));
}
