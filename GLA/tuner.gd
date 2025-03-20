extends Node2D

@export var ui_notes: Array[Control]  # Assign your 72 UI elements in editor
@export var frequency_tolerance: float = 0.03  # 3% frequency tolerance
@export var debug_label: Label  # Label to display detection info

var spectrum: AudioEffectSpectrumAnalyzerInstance
var note_map = []  # Stores precomputed note data
var note_groups = {}  # Groups equivalent notes together {frequency: [ui_indices]}
var active_notes = {}  # Tracks currently visible notes {ui_index: time_remaining}

# Audio analysis constants
const SAMPLE_RATE: int = 44100
const FFT_SIZE: int = 4096
const BASE_NOTES = [329.63, 246.94, 196.0, 146.83, 110.0, 82.41]  # E4 to E2
var bin_width: float = SAMPLE_RATE / float(FFT_SIZE)

func _ready():
	# Initialize audio analysis
	spectrum = AudioServer.get_bus_effect_instance(0, 0)
	# Create note frequency map and group equivalent notes
	create_note_map()
	group_equivalent_notes()

func create_note_map():
	# Generate frequencies for all 6 strings x 12 frets
	for string in range(6):
		var base_freq = BASE_NOTES[string]
		for fret in range(12):
			var note_freq = base_freq * pow(2, (fret + 1) / 12.0)
			var ui_index = (string * 12) + fret
			note_map.append({
				"frequency": note_freq,
				"ui_index": ui_index,
				"string": string,
				"fret": fret + 1
			})

func group_equivalent_notes():
	# Group notes with the same or very similar frequencies
	for note in note_map:
		var freq_key = snapped(note["frequency"], 0.1)  # Round to 0.1 Hz for grouping
		if not note_groups.has(freq_key):
			note_groups[freq_key] = []
		note_groups[freq_key].append(note["ui_index"])

func _process(delta):
	# Hide all notes at the start of each frame
	hide_all_notes()
	
	# Get frequency peaks from microphone
	var peaks = get_significant_peaks()
	if peaks.is_empty():
		return
	
	# Use the FIRST significant peak (lowest frequency) for detection
	var first_peak = peaks[0]
	var refined_freq = parabolic_interpolation(first_peak["bin"], first_peak["mag"])
	
	# Find the closest note to the refined frequency
	var detected_note = find_closest_note(refined_freq)
	if detected_note:
		activate_note_group(detected_note)
		update_debug_label(detected_note)

func hide_all_notes():
	# Hide all notes at the start of each frame
	for ui_index in active_notes.keys():
		set_note_visibility(ui_index, false)
	active_notes.clear()

func find_closest_note(frequency: float) -> Dictionary:
	# Find the closest note to the given frequency
	var closest_note = null
	var min_diff = INF
	for note in note_map:
		var diff = abs(note["frequency"] - frequency)
		if diff < min_diff:
			min_diff = diff
			closest_note = note
	
	# Check if within tolerance
	if closest_note and min_diff <= closest_note["frequency"] * frequency_tolerance:
		return closest_note
	return {}

func parabolic_interpolation(bin: int, magnitude: float) -> float:
	# Get magnitudes of neighboring bins
	var prev_mag = get_bin_magnitude(bin - 1) if bin > 1 else 0.0
	var next_mag = get_bin_magnitude(bin + 1) if bin < (FFT_SIZE / 2 - 1) else 0.0
	
	# Parabolic interpolation formula
	var delta = 0.5 * (prev_mag - next_mag) / (prev_mag - 2.0 * magnitude + next_mag)
	var refined_bin = bin + delta
	return refined_bin * bin_width

func activate_note_group(note_data):
	# Find all equivalent notes
	var freq_key = snapped(note_data["frequency"], 0.1)
	if note_groups.has(freq_key):
		for ui_index in note_groups[freq_key]:
			active_notes[ui_index] = 1.0
			set_note_visibility(ui_index, true)

func set_note_visibility(ui_index: int, visible: bool):
	if ui_index >= ui_notes.size():
		return
	
	var note_control = ui_notes[ui_index]
	var correct_sprite = note_control.get_node("Panel/Correct") as Sprite2D
	if correct_sprite:
		correct_sprite.visible = visible

func update_debug_label(note_data):
	if debug_label:
		var string_names = ["High E", "B", "G", "D", "A", "Low E"]
		var freq_key = snapped(note_data["frequency"], 0.1)
		var detected_notes = []
		
		# Get all equivalent notes for the detected frequency
		if note_groups.has(freq_key):
			for ui_index in note_groups[freq_key]:
				var note = note_map[ui_index]
				var string_name = string_names[note["string"]]
				detected_notes.append("Fret %d (%s)" % [note["fret"], string_name])
		
		# Update the label with all detected notes
		debug_label.text = "Detected Notes:\n" + "\n".join(detected_notes)

# Audio analysis functions
func get_significant_peaks() -> Array:
	var peaks = []
	var noise_floor = calculate_noise_floor()
	for bin in range(1, FFT_SIZE / 2):
		var magnitude = get_bin_magnitude(bin)
		if magnitude > noise_floor and is_local_max(bin):
			peaks.append({
				"bin": bin,
				"freq": bin * bin_width,
				"mag": magnitude
			})
	# Sort peaks by frequency (lowest first)
	peaks.sort_custom(func(a, b): return a["freq"] < b["freq"])
	return peaks

func is_local_max(bin: int) -> bool:
	var current = get_bin_magnitude(bin)
	var prev = get_bin_magnitude(bin - 1) if bin > 1 else 0.0
	var next = get_bin_magnitude(bin + 1) if bin < (FFT_SIZE / 2 - 1) else 0.0
	return current > prev and current > next

func calculate_noise_floor() -> float:
	var max_magnitude = 0.0
	for bin in range(1, FFT_SIZE / 2):
		max_magnitude = max(max_magnitude, get_bin_magnitude(bin))
	return max_magnitude * 0.2

func get_bin_magnitude(bin: int) -> float:
	var freq_low = bin_width * (bin - 0.5)
	var freq_high = bin_width * (bin + 0.5)
	return spectrum.get_magnitude_for_frequency_range(freq_low, freq_high).length()
