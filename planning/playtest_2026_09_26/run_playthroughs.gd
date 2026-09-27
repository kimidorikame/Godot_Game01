extends SceneTree

func _initialize() -> void:
	await process_frame
	await load("res://planning/playtest_2026_09_26/playthroughs.gd").new().run(self)
	quit()
