extends Button

@export var VisPanel: Panel

@export var InVisPanel1: Panel
@export var InVisPanel2: Panel
@export var InVisPanel3: Panel

func _on_pressed() -> void:
	# Set the visible panel to visible
	VisPanel.visible = true
	
	# Set the invisible panels to invisible
	InVisPanel1.visible = false
	InVisPanel2.visible = false
	InVisPanel3.visible = false
