// VoxelRenderer3D town base: the plinth under a town and the table it stands on, so the void past a town's
// edge reads as a miniature on a tabletop. Same curvature and distance haze as voxel.gdshader so it meets the
// town's skirt without a gap. Flat colour with a soft radial falloff; no textures.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

uniform vec3 curve_center = vec3(0.0);
uniform float curve_k = 0.0035;
uniform vec3 albedo : source_color = vec3(0.25, 0.2, 0.16);
uniform float shade = 1.0;
uniform bool fog_on = true;
uniform vec3 fog_color : source_color = vec3(0.36, 0.42, 0.50);
uniform float fog_start = 12.0;
uniform float fog_end = 32.0;
uniform float fog_max = 0.8;

varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = w;
	vec2 dd = w.xz - curve_center.xz;
	w.y -= dot(dd, dd) * curve_k;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo * shade * (NORMAL.y > 0.5 ? 1.0 : 0.72);
	if (fog_on) {
		float fd = length(wpos.xz - curve_center.xz);
		c = mix(c, fog_color, smoothstep(fog_start, fog_end, fd) * fog_max);
	}
	ALBEDO = c;
}
