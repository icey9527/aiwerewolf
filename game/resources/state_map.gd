extends RefCounted

# 角色配置只支持一层嵌套的 YAML 子集：
#   name: ChatGPT
#   color: "#8fa9ff"
#   memorial: 11
#   focus: 0.11
#   states:
#     0: 常态.png
# 不支持列表、多行字符串、锚点等完整 YAML 特性。
# focus 是脸部（眼睛）在立绘画布中的高度比例，从画布顶部往下数；
# 用于镜头锚点，让坐姿、半身等不同构图都能按实际画面取景。
static func parse(text: String) -> Dictionary:
	var result: Dictionary = {"name": "", "color": "", "memorial": -1, "seat": -1, "focus": -1.0, "states": {}, "error": ""}
	var section: String = ""
	var line_number: int = 0
	for raw: String in text.trim_prefix("﻿").split("\n"):
		line_number += 1
		var expanded: String = raw.replace("\t", "  ")
		var line: String = expanded.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var indented: bool = expanded.length() > 0 and expanded[0] == " "
		var colon: int = line.find(":")
		if colon <= 0:
			return _error(line_number, "需要 key: value")
		var key: String = line.left(colon).strip_edges()
		var value: String = _value(line.substr(colon + 1))
		if indented:
			if section != "states":
				return _error(line_number, "缩进行必须位于 states: 之下")
			if not key.is_valid_int() or int(key) < 0:
				return _error(line_number, "状态 ID 必须是非负整数")
			var id: int = int(key)
			if result.states.has(id):
				return _error(line_number, "状态 ID 重复")
			if value.is_empty() or value.get_file() != value or value.contains("\\") or value.contains(":") or value.get_extension().to_lower() != "png":
				return _error(line_number, "状态只能引用当前目录的 PNG 文件名")
			result.states[id] = value
		else:
			if value.is_empty():
				section = key
				if section != "states":
					return _error(line_number, "只允许 states: 作为嵌套段")
				continue
			section = ""
			match key:
				"name":
					result.name = value
				"color":
					if not value.begins_with("#") or not (value.length() == 7 or value.length() == 9):
						return _error(line_number, "color 需要 #RRGGBB 或 #RRGGBBAA")
					result.color = value
				"memorial":
					if not value.is_valid_int() or int(value) < 0:
						return _error(line_number, "memorial 必须是非负整数")
					result.memorial = int(value)
				"seat":
					if not value.is_valid_int() or int(value) < 1:
						return _error(line_number, "seat 必须是正整数")
					result.seat = int(value)
				"focus":
					if not value.is_valid_float():
						return _error(line_number, "focus 必须是 0..1 之间的小数")
					var focus_value: float = float(value)
					if focus_value < 0.0 or focus_value > 1.0:
						return _error(line_number, "focus 必须是 0..1 之间的小数")
					result.focus = focus_value
				_:
					return _error(line_number, "未知字段：" + key)
	if result.states.is_empty() or not result.states.has(0):
		return _error(0, "必须定义默认状态 0")
	return result

static func _value(raw: String) -> String:
	var text: String = raw.strip_edges()
	if text.begins_with('"'):
		var decoded: Variant = JSON.parse_string(text)
		return decoded if decoded is String else ""
	if text.begins_with("'"):
		if not text.ends_with("'") or text.length() < 2:
			return ""
		return text.substr(1, text.length() - 2).replace("''", "'")
	var comment: int = text.find(" #")
	return text.left(comment).strip_edges() if comment >= 0 else text

static func _error(line: int, message: String) -> Dictionary:
	return {"name": "", "color": "", "memorial": -1, "seat": -1, "focus": -1.0, "states": {}, "error": "第 %d 行：%s" % [line, message]}
