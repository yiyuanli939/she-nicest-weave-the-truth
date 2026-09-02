class_name UiStyles
extends RefCounted
## 带底色按钮的样式(v1.1 §4.5/§4.6:节点内「钉纹样」按钮、纹样绘制弹窗的 清空/取消/确认)。
## 主题里的 Button 是纯文字无底(美术要求),需要底色的按钮在脚本里按这里覆盖;
## 悬停/按下用底色变暗区分。圆角/内边距常量给美术调。

const RADIUS := 10
const MARGIN_H := 20.0
const MARGIN_V := 8.0
const HOVER_DARKEN := 0.06
const PRESSED_DARKEN := 0.12


static func filled(bg: Color, darken := 0.0, border_w := 0, border_color := Color.BLACK,
		margin_h := MARGIN_H, margin_v := MARGIN_V) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg.darkened(darken)
	sb.set_corner_radius_all(RADIUS)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_color
	return sb


## 给按钮套一组底色样式(normal / hover / pressed / disabled;焦点框不画);内边距按调用方给(示意图里各处不同)
static func fill_button(b: Button, bg: Color, margin_h := MARGIN_H, margin_v := MARGIN_V) -> void:
	b.add_theme_stylebox_override("normal", filled(bg, 0.0, 0, Color.BLACK, margin_h, margin_v))
	b.add_theme_stylebox_override("hover", filled(bg, HOVER_DARKEN, 0, Color.BLACK, margin_h, margin_v))
	b.add_theme_stylebox_override("pressed", filled(bg, PRESSED_DARKEN, 0, Color.BLACK, margin_h, margin_v))
	b.add_theme_stylebox_override("hover_pressed", filled(bg, PRESSED_DARKEN, 0, Color.BLACK, margin_h, margin_v))
	b.add_theme_stylebox_override("disabled", filled(bg, 0.0, 0, Color.BLACK, margin_h, margin_v))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
