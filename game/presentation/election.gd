extends RefCounted

# 独立表现轨道：从剧本重建竞选高度与警长，不改变投票规则。
static func sample(beats: Array[Dictionary], index: int, progress: float, count: int) -> Dictionary:
	var heights: Array[float] = []
	heights.resize(count)
	heights.fill(0.0)
	var sheriff: int = -1
	for i in range(index + 1):
		var beat: Dictionary = beats[i]
		var t: float = smoothstep(0.08, 0.68, progress) if i == index else 1.0
		match str(beat.kind):
			"sheriff_signup":
				for seat: Variant in beat.get("candidates", []):
					heights[int(seat)] = t
			"sheriff_withdraw":
				for seat: Variant in beat.get("withdrawn", []):
					heights[int(seat)] = 1.0 - t
			"sheriff_elected":
				sheriff = int(beat.get("elected", -1))
				for seat in range(count):
					heights[seat] *= 1.0 - t
	return {"heights": heights, "sheriff": sheriff}
