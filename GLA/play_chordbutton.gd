extends Button

@export var audio_player: AudioStreamPlayer2D
@export var button_label: Label  # Assign your child Label in the inspector

func _ready() -> void:
	pressed.connect(_on_button_pressed)
	if audio_player:
		audio_player.finished.connect(_on_audio_finished)
	if button_label:
		button_label.text = "Hear Chord"

func _on_button_pressed() -> void:
	if audio_player and not audio_player.playing:
		audio_player.play()
		if button_label:
			button_label.text = "Playing..."
	elif not audio_player:
		push_warning("No AudioStreamPlayer assigned to the button")

func _on_audio_finished() -> void:
	if button_label:
		button_label.text = "Hear Chord"
