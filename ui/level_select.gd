class_name LevelSelect
extends Control
## 选关:按章节列出,线性解锁;已通关 = 金印 ✓(占位:文字)。

func _ready() -> void:
	var game := get_node("/root/Game")
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 40)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)

	var top := HBoxContainer.new()
	var title := Label.new()
	title.text = "选关"
	title.add_theme_font_size_override("font_size", 28)
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var back := Button.new()
	back.text = "返回菜单"
	back.pressed.connect(game.goto_menu)
	top.add_child(back)
	box.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var chapters := VBoxContainer.new()
	chapters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(chapters)
	box.add_child(scroll)

	var idx := 0
	for ch: ChapterDef in game.catalog.chapters:
		var ch_lbl := Label.new()
		ch_lbl.text = ch.title
		ch_lbl.add_theme_font_size_override("font_size", 20)
		chapters.add_child(ch_lbl)
		var row := HFlowContainer.new()
		for lv: LevelDef in ch.levels:
			var solved: bool = game.save.is_solved(lv.id)
			var unlocked: bool = game.is_unlocked(idx)
			var b := Button.new()
			b.text = ("✓ " if solved else "") + lv.title + ("" if unlocked else " 🔒")
			b.disabled = not unlocked
			b.custom_minimum_size = Vector2(150, 40)
			b.pressed.connect(game.start_level.bind(lv))
			row.add_child(b)
			idx += 1
		chapters.add_child(row)
