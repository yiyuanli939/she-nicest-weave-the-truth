class_name PalettePanel
extends PanelContainer
## 仪器架:按关卡 allowed_rules 列出可用仪器,点击请求放置。
## 只发信号,不碰 GraphEdit;拖放进阶(_get_drag_data)留待美术期。

signal machine_requested(rule_id: StringName)

var _list := VBoxContainer.new()


func _ready() -> void:
	custom_minimum_size.x = 148
	var title := Label.new()
	title.text = "仪器架"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(title)
	add_child(_list)


func set_rules(ids: Array[StringName]) -> void:
	for c in _list.get_children():
		if c is Button:
			c.queue_free()
	for rule_id in ids:
		var info := ProofSession.describe_rule(rule_id)
		if info == null:
			continue
		var btn := Button.new()
		btn.text = info.cn_name
		btn.tooltip_text = "%s:%d 入 %d 出" % [rule_id, info.inputs.size(), info.outputs.size()]
		btn.pressed.connect(machine_requested.emit.bind(rule_id))
		_list.add_child(btn)
