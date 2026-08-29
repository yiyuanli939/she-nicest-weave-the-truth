shader_type canvas_item;
// 标题图表面微弱流光(美术:「如果可以的话给整个标题图片加一个微弱的表面流光」):
// 一条柔和的斜向亮带每 period 秒从左上扫到右下,只提亮不透明像素,alpha 不动。
uniform float period : hint_range(1.0, 10.0) = 4.0;
uniform float band_width : hint_range(0.01, 0.5) = 0.12;
uniform float strength : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec4 base = COLOR;
	float t = fract(TIME / period);
	float d = (UV.x + UV.y) * 0.5;
	float c = mix(-band_width, 1.0 + band_width, t);
	float band = 1.0 - smoothstep(0.0, band_width, abs(d - c));
	base.rgb = min(base.rgb + vec3(band * strength * base.a), vec3(1.0));
	COLOR = base;
}
