extends Node
func _ready() -> void:
	for f in ["sky", "far", "mid"]:
		var p := "res://assets/backgrounds/grass/%s.png" % f
		print(f, " exists=", ResourceLoader.exists(p), " load=", load(p))
	get_tree().quit()
