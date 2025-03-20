extends Node2D

@export var ui_notes: Array[Control]  # Assign 78 UI elements (72 frets + 6 open strings)
@export var frequency_tolerance: float = 0.03  # 3% tolerance
@export var debug_label: Label  # Detection info display
@export var visibility_timer: Timer  # Timer for incorrect notes

var spectrum: AudioEffectSpectrumAnalyzerInstance
var note_map = []  # Precomputed note data
var active_notes = []  # Currently visible incorrect notes
var scale_sequence = []  # Sequence of notes in the scale
var current_step = 0  # Current step in the scale

# Audio constants
const SAMPLE_RATE = 44100
const FFT_SIZE = 4096
const BASE_NOTES = [329.63, 246.94, 196.0, 146.83, 110.0, 82.41]  # E4 to E2
var bin_width = SAMPLE_RATE / float(FFT_SIZE)

func _ready():
	# Audio initialization
	spectrum = AudioServer.get_bus_effect_instance(0, 0)
	create_note_map()
	initialize_scale_sequence()
	
	# Timer configuration
	visibility_timer.one_shot = true
	visibility_timer.timeout.connect(_on_visibility_timer_timeout)
	
	# Show the first note in the scale as "Wait"
	show_current_note_as_wait()

func create_note_map():
	# Generate all 72 fretted note frequencies
	for string in range(6):
		var base_freq = BASE_NOTES[string]
		for fret in range(12):
			var note_freq = base_freq * pow(2, (fret + 1)/12.0)
			var ui_index = (string * 12) + fret
			note_map.append({
				"frequency": note_freq,
				"ui_index": ui_index,
				"string": string,
				"fret": fret + 1
			})
	
	# Add open string frequencies (last 6 elements)
	for string in range(6):
		var open_freq = BASE_NOTES[string]
		var ui_index = 72 + string  # Open strings start at index 72
		note_map.append({
			"frequency": open_freq,
			"ui_index": ui_index,
			"string": string,
			"fret": 0  # 0 indicates open string
		})

func initialize_scale_sequence():
	# Define the scale sequence as a list of (string, fret) pairs
	scale_sequence = [
		{"string": 4, "fret": 3},  # A string 3rd fret
		{"string": 3, "fret": 0},  # D string open
		{"string": 3, "fret": 2},  # D string 2nd fret
		{"string": 3, "fret": 3},  # D string 3rd fret
		{"string": 2, "fret": 0},  # G open
		{"string": 2, "fret": 2},  # G 2nd fret
		{"string": 1, "fret": 0},  # B open
		{"string": 1, "fret": 1},  # B 1st fret
		{"string": 1, "fret": 3},  # B 3rd fret
		{"string": 0, "fret": 0},  # High E open
		{"string": 0, "fret": 1},  # High E 1st fret
		{"string": 0, "fret": 3},  # High E 3rd fret
		{"string": 0, "fret": 1},  # High E 1st fret
		{"string": 0, "fret": 0},  # High E open
		{"string": 1, "fret": 3},  # B 3rd fret
		{"string": 1, "fret": 1},  # B 1st fret
		{"string": 1, "fret": 0},  # B open
		{"string": 2, "fret": 2},  # G 2nd fret
		{"string": 2, "fret": 0},  # G open
		{"string": 3, "fret": 3},  # D string 3rd fret
		{"string": 3, "fret": 2},  # D string 2nd fret
		{"string": 3, "fret": 0},  # D string open
		{"string": 4, "fret": 3},  # A string 3rd fret
		{"string": 4, "fret": 2},  # A string 2nd fret
		{"string": 4, "fret": 0},  # A string open
		{"string": 5, "fret": 3},  # Low E 3rd fret
		{"string": 5, "fret": 1},  # Low E 1st fret
		{"string": 5, "fret": 0},  # Low E open
		{"string": 5, "fret": 1},  # Low E 1st fret
		{"string": 5, "fret": 3},  # Low E 3rd fret
		{"string": 4, "fret": 0},  # A string open
		{"string": 4, "fret": 2},  # A string 2nd fret
		{"string": 4, "fret": 3}   # A string 3rd fret
	]

func show_current_note_as_wait():
	# Get the current note in the scale
	var current_note = scale_sequence[current_step]
	var ui_index = get_ui_index(current_note["string"], current_note["fret"])
	
	# Show the current note as "Wait"
	set_note_visibility(ui_index, "Wait")

func get_ui_index(string: int, fret: int) -> int:
	# Calculate the UI index for a given string and fret
	if fret == 0:
		return 72 + string  # Open strings are the last 6 elements
	else:
		return (string * 12) + (fret - 1)  # Fretted notes

func _process(_delta):
	# Always process peaks regardless of timer state
	var peaks = get_significant_peaks()
	if peaks.is_empty():
		debug_label.text = "No peaks detected"
		return
	
	process_peak(peaks[0]["freq"])

func process_peak(detected_freq: float):
	# Get the current note in the scale
	var current_note = scale_sequence[current_step]
	var current_freq = BASE_NOTES[current_note["string"]] * pow(2, current_note["fret"] / 12.0)
	
	# Check if the detected frequency matches the target, fret above, or fret below
	if is_correct_note(detected_freq, current_note):
		# Correct note detected
		mark_note_as_correct(current_note)
		move_to_next_step()
	else:
		# Incorrect note detected
		show_incorrect_notes(detected_freq)

func is_correct_note(detected_freq: float, target_note: Dictionary) -> bool:
	# Get the target frequency and its neighboring frets
	var target_freq = BASE_NOTES[target_note["string"]] * pow(2, target_note["fret"] / 12.0)
	var fret_above = target_note["fret"] + 1
	var fret_below = target_note["fret"] - 1
	
	# Calculate frequencies for fret above and below
	var freq_above = BASE_NOTES[target_note["string"]] * pow(2, fret_above / 12.0) if fret_above <= 12 else -1
	var freq_below = BASE_NOTES[target_note["string"]] * pow(2, fret_below / 12.0) if fret_below >= 0 else -1
	
	# Check if detected frequency matches target, fret above, or fret below
	return (
		abs(detected_freq - target_freq) <= (target_freq * frequency_tolerance) ||  # Target
		(freq_above != -1 && abs(detected_freq - freq_above) <= (freq_above * frequency_tolerance)) ||  # Fret above
		(freq_below != -1 && abs(detected_freq - freq_below) <= (freq_below * frequency_tolerance))  # Fret below
	)

func mark_note_as_correct(note):
	var ui_index = get_ui_index(note["string"], note["fret"])
	set_note_visibility(ui_index, "Correct")

func move_to_next_step():
	current_step += 1
	if current_step >= scale_sequence.size():
		current_step = 0  # Loop back to the start of the scale
	show_current_note_as_wait()

func show_incorrect_notes(detected_freq: float):
	# Clear previous incorrect notes
	clear_active_notes()
	
	# Find and show matching incorrect notes
	var matches = get_matching_notes(detected_freq)
	show_notes(matches)
	
	# Start the timer for incorrect notes
	visibility_timer.start()

func get_matching_notes(freq: float) -> Array:
	var matches = []
	var octave = freq / 2.0  # Include lower octave
	
	for note in note_map:
		if is_match(note.frequency, freq) || is_match(note.frequency, octave):
			matches.append(note.ui_index)
	
	return matches

func is_match(note_freq: float, target: float) -> bool:
	return abs(note_freq - target) <= (target * frequency_tolerance)

func show_notes(indices: Array):
	active_notes = indices.duplicate()
	for ui_index in active_notes:
		set_note_visibility(ui_index, "Wrong")

func clear_active_notes():
	for ui_index in active_notes:
		set_note_visibility(ui_index, "None")
	active_notes.clear()

func set_note_visibility(ui_index: int, state: String):
	if ui_index < ui_notes.size():
		var note = ui_notes[ui_index]
		var panel = note.get_node("Panel")
		panel.get_node("Wait").visible = (state == "Wait")
		panel.get_node("Wrong").visible = (state == "Wrong")
		panel.get_node("Correct").visible = (state == "Correct")

func _on_visibility_timer_timeout():
	clear_active_notes()

# Audio analysis functions remain unchanged below
func get_significant_peaks() -> Array:
	var peaks = []
	var noise_floor = calculate_noise_floor()
	for bin in range(1, FFT_SIZE / 2):
		var magnitude = get_bin_magnitude(bin)
		if magnitude > noise_floor && is_local_max(bin):
			peaks.append({"freq": bin * bin_width, "bin": bin, "mag": magnitude})
	peaks.sort_custom(func(a, b): return a["freq"] < b["freq"])
	return peaks

func is_local_max(bin: int) -> bool:
	var current = get_bin_magnitude(bin)
	var prev = get_bin_magnitude(bin - 1) if bin > 1 else 0.0
	var next = get_bin_magnitude(bin + 1) if bin < (FFT_SIZE / 2 - 1) else 0.0
	return current > prev && current > next

func calculate_noise_floor() -> float:
	var max_mag = 0.0
	for bin in range(1, FFT_SIZE / 2):
		max_mag = max(max_mag, get_bin_magnitude(bin))
	return max_mag * 0.2

func get_bin_magnitude(bin: int) -> float:
	var low = bin_width * (bin - 0.5)
	var high = bin_width * (bin + 0.5)
	return spectrum.get_magnitude_for_frequency_range(low, high).length()
