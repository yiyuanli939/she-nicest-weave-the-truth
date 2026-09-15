class_name BackButton
extends RefCounted
## 选关页 / 开发者信息页共用的左上角「返回主界面」文字按钮。
## 两页同一张底图(assets/art/select/bg.png),常量放一处保证位置像素级一致;
## 坐标为 3840×2160 逻辑像素,装饰边框内沿实测 x≈192 / y≈232;美术调位置改常量。
## 文字必须纯汉字(字体缺箭头等符号,tests/test_theme.gd 会扫)。

const RECT := Rect2(232, 262, 340, 92)
const FONT_SIZE := 52
const RECT_EN := Rect2(232, 262, 520, 92)
const FONT_SIZE_EN := 42


static func make(on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = TranslationServer.translate("返回主界面")
	var english := TranslationServer.get_locale().to_lower().begins_with("en")
	b.position = (RECT_EN if english else RECT).position
	b.size = (RECT_EN if english else RECT).size
	b.add_theme_font_size_override("font_size", FONT_SIZE_EN if english else FONT_SIZE)
	b.set_meta(SoundFx.META, &"back")
	b.pressed.connect(on_pressed)
	return b
