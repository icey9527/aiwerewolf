extends RefCounted

const Params = preload("res://config/camera_params.gd")
const Catalog = preload("res://resources/character_catalog.gd")

static func stage_state(beat: Dictionary, progress: float) -> Dictionary:
	var kind: String = str(beat.get("kind", "day"))
	var closed: float = 0.0
	var night: float = 0.0
	match kind:
		"closing":
			closed = smoothstep(0.1, 0.85, progress)
			night = smoothstep(0.0, 0.6, progress)
		"sealed", "wolf", "oracle":
			closed = 1.0
			night = 1.0
		"opening":
			closed = 1.0 - smoothstep(0.1, 0.85, progress)
			night = 1.0 - smoothstep(0.0, 0.9, progress)
	var fall: float = smoothstep(0.35, 0.72, progress) if kind == "execution" else 0.0
	return {
		"closed": closed, "night": night,
		"vote": smoothstep(0.0, 0.7, progress) if kind == "vote" else 0.0,
		"exit_seat": int(beat.get("exit_seat", -1)) if kind == "execution" else -1,
		"fall": fall,
		"spotlight": 1.0 if kind == "execution" else 0.0,
		"confetti": clampf((progress - 0.12) / 0.7, 0.0, 1.0) if kind == "execution" else 0.0,
	}

static func character_states(beats: Array[Dictionary], index: int, progress: float, count: int) -> Array[Dictionary]:
	var characters: Array[Dictionary] = []
	for seat in range(count):
		characters.append({"visible": true, "pose": 0, "memorial": false, "drop": 0.0})
	# 从头投影语义标记，seek 不依赖之前播放过哪些片段。
	for i in range(index + 1):
		var beat: Dictionary = beats[i]
		for seat: Variant in beat.get("empty_seats", []):
			characters[int(seat)].visible = false
		for seat: Variant in beat.get("memorial_seats", []):
			characters[int(seat)] = {"visible": true, "pose": Catalog.memorial_id(int(seat)), "memorial": true, "drop": 0.0}
		if str(beat.kind) == "execution":
			var seat: int = int(beat.exit_seat)
			if i < index:
				characters[seat].visible = false
			else:
				characters[seat].drop = Params.FALL_DEPTH * pow(smoothstep(0.35, 0.72, progress), 2.0)
				characters[seat].visible = progress < 0.75
	var current: Dictionary = beats[index]
	var speaker: int = int(current.speaker)
	if speaker >= 0 and not bool(characters[speaker].memorial):
		characters[speaker].pose = current.get("pose", 0)
		# 同一段发言里可以按进度换表情：pose_changes 里每项 {at: 0..1, pose: id}，
		# 取所有已到时间点的最后一项，保证 seek 结果一致。
		for change: Dictionary in current.get("pose_changes", []):
			if progress >= float(change.get("at", 0.0)):
				characters[speaker].pose = int(change.get("pose", characters[speaker].pose))
	# 旁听者的公开反应表情：每段最多写三四个，和台词一起交代谁在质疑、谁在躲。
	for reaction: Dictionary in current.get("reactions", []):
		var seat: int = int(reaction.get("seat", -1))
		if seat < 0 or seat >= count:
			continue
		if bool(characters[seat].memorial) or not bool(characters[seat].visible):
			continue
		characters[seat].pose = int(reaction.get("pose", 0))
	return characters
