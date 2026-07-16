shader_type sky;
// Динамическое небо: день/ночь, закаты, диск солнца, луна с «морями», звёзды.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 day_top: source_color = vec3(0.35, 0.55, 0.78);
uniform vec3 day_hor: source_color = vec3(0.7, 0.8, 0.88);
uniform vec3 night_top: source_color = vec3(0.015, 0.025, 0.07);
uniform vec3 night_hor: source_color = vec3(0.05, 0.08, 0.16);
uniform vec3 sunset_color: source_color = vec3(1.0, 0.45, 0.2);
uniform vec3 ground_color: source_color = vec3(0.2, 0.25, 0.2);
uniform float night_k = 0.0;  // 0 — день, 1 — ночь
uniform float sunset_k = 0.0; // сила заката


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


void sky() {
	vec3 d = EYEDIR;
	float h = d.y;

	vec3 day_col = mix(day_hor, day_top, pow(clamp(h, 0.0, 1.0), 0.55));
	vec3 night_col = mix(night_hor, night_top, pow(clamp(h, 0.0, 1.0), 0.5));
	vec3 col = mix(day_col, night_col, night_k);

	// под горизонтом — тёмная «земля»
	if (h < 0.0) {
		col = mix(col, ground_color * (1.0 - night_k * 0.75), clamp(-h * 6.0, 0.0, 1.0));
	}

	float sun_amount = max(dot(d, sun_dir), 0.0);

	// закат окрашивает горизонт в стороне солнца
	col = mix(col, sunset_color, sunset_k * (0.3 + 0.7 * pow(sun_amount, 2.0)) * pow(1.0 - abs(h), 2.5));

	// диск солнца с гало
	float sun_disc = smoothstep(0.99930, 0.99965, sun_amount);
	vec3 sun_col = mix(vec3(1.0, 0.97, 0.85), sunset_color * 1.5, clamp(sunset_k * 1.2, 0.0, 1.0));
	col += sun_col * sun_disc * (1.0 - night_k) * 1.6;
	col += sun_col * pow(sun_amount, 220.0) * 0.55 * (1.0 - night_k);

	// луна: диск с пятнами-«морями» и холодным гало
	float moon_amount = max(dot(d, moon_dir), 0.0);
	float moon_disc = smoothstep(0.99950, 0.99982, moon_amount);
	if (moon_disc > 0.001) {
		vec3 mx = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
		vec3 my = normalize(cross(mx, moon_dir));
		vec2 mp = vec2(dot(d, mx), dot(d, my)) * 220.0;
		float mn = hash12(floor(mp)) * 0.5 + hash12(floor(mp * 0.47) + 11.0) * 0.5;
		vec3 moon_col = vec3(0.86, 0.9, 1.0) * (0.72 + 0.42 * mn);
		col = mix(col, moon_col * 1.35, moon_disc);
	}
	col += vec3(0.45, 0.55, 0.9) * pow(moon_amount, 260.0) * 0.5 * night_k;

	// звёзды (мерцают, видны только ночью)
	if (h > -0.02 && night_k > 0.03) {
		vec2 sc = vec2(atan(d.x, d.z), asin(clamp(h, -1.0, 1.0))) * 46.0;
		vec2 cell = floor(sc);
		vec2 f = fract(sc);
		float rnd = hash12(cell);
		vec2 spos = vec2(hash12(cell + 7.13), hash12(cell + 3.71)) * 0.7 + 0.15;
		float dist = length(f - spos);
		float twinkle = 0.65 + 0.35 * sin(TIME * (1.0 + rnd * 3.0) + rnd * 31.0);
		float star = smoothstep(0.13, 0.0, dist) * step(rnd, 0.32) * twinkle;
		col += vec3(0.9, 0.95, 1.0) * star * night_k * (0.45 + rnd * 0.8);
	}

	COLOR = col;
}
