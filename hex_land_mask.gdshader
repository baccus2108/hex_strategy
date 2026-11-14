shader_type canvas_item;
// Hex dolgularını ve ülke sınırlarını GERÇEK KARA MASKESİNE kırpar.
// land_mask: assets/relief/relief_<proje>_4096.png (RGBA; alfa = kara). rect: dokunun kapladığı düzlem dikdörtgeni (x, y, w, h).
// Düğüm yerel koordinatı = dünya (düzlem) koordinatıdır; wrap_x açıkken x, kopya düğümler için de dönerek örneklenir.

uniform sampler2D land_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 rect = vec4(-2000.0, -1000.0, 4000.0, 2000.0);
uniform bool wrap_x = true;

varying vec2 plane_pos;

void vertex() {
	plane_pos = VERTEX;
}

void fragment() {
	vec2 uv = (plane_pos - rect.xy) / rect.zw;
	if (wrap_x) {
		uv.x = fract(uv.x);
	}
	float m = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		m = texture(land_mask, uv).a;
	}
	COLOR.a *= smoothstep(0.30, 0.70, m);
}
