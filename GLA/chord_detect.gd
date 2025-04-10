extends Node2D

@export var ui_notes: Array[Control] # Must be set in the Inspector to all 78 note UI controls.
@export var start_button: Button # Button to start detection
@export var chord_to_detect: String # (A, Am, B, Bm, C, D, Dm, D7, E, Em, F, G, G7)
@export var buttontext: Label # label for the button

const SAMPLE_RATE = 44100
const FFT_SIZE = 4096
const BIN_WIDTH = SAMPLE_RATE / float(FFT_SIZE)
const MAX_HARMONIC = 4

# States
enum NoteState {CORRECT, WRONG, WAIT, INACTIVE}

# Tolerances
const DEFAULT_TOLERANCE = 10.0
const B_STRING_TOLERANCE = 15.0
const LOW_E_TOLERANCE = 5.0

# Special Note Indices
const B_STRING_1 = 12
const B_STRING_3 = 14
const LOW_E_START = 60
const LOW_E_END = 71
const LOW_E_FRET_2 = 61

# Note frequencies (UI index → Hz)
var note_frequencies = {
	# High E string (0-11) frets 1-12 (thinnest string)
	0:349.23, 1:369.99, 2:392.00, 3:415.30, 4:440.00, 5:466.16,
	6:493.88, 7:523.25, 8:523.25, 9:554.37, 10:587.33, 11:622.25,
	
	# B string (12-23)
	12:261.63, 13:277.18, 14:293.66, 15:311.13, 16:329.63, 17:349.23,
	18:369.99, 19:392.00, 20:392.00, 21:415.30, 22:440.00, 23:466.16,
	
	# G string (24-35)
	24:207.65, 25:220.00, 26:233.08, 27:246.94, 28:261.63, 29:277.18,
	30:293.66, 31:311.13, 32:311.13, 33:329.63, 34:349.23, 35:369.99,
	
	# D string (36-47)
	36:155.56, 37:164.81, 38:174.61, 39:185.00, 40:196.00, 41:207.65,
	42:220.00, 43:233.08, 44:233.08, 45:246.94, 46:261.63, 47:277.18,
	
	# A string (48-59)
	48:116.54, 49:123.47, 50:130.81, 51:138.59, 52:146.83, 53:155.56,
	54:164.81, 55:174.61, 56:174.61, 57:185.00, 58:196.00, 59:207.65,
	
	# Low E string (60-71) (thickest string)
	60:87.31, 61:92.50, 62:98.00, 63:103.83, 64:110.00, 65:116.54,
	66:123.47, 67:130.81, 68:130.81, 69:138.59, 70:146.83, 71:155.56,
	
	# Open strings (72-77)
	72:329.63, 73:246.94, 74:196.00, 75:146.83, 76:110.00, 77:82.41
}

# Chord definitions (UI indices of notes to detect)
var chord_definitions = {
	"A": [76, 27, 37, 13, 72],          # A Major
	"Am": [12, 25, 37],         # A minor
	"B": [1, 15, 27, 39, 49, 61],      # B Major (barre chord)
	"Bm": [1, 14, 27, 39, 49, 61],     # B minor (barre chord)
	"C": [50, 37, 74, 12, 72],  # C Major
	"D": [1, 25, 14, 75],          # D Major
	"Dm": [0, 25, 14, 75],         # D minor
	"D7": [1, 25, 12, 75],         # D7
	"E": [77, 61, 49, 36, 73, 72],          # E Major
	"Em": [77, 61, 49, 74, 73, 72],             # E minor
	"F": [0, 12, 25, 38, 50, 60],      # F Major (barre chord)
	"G": [62, 49, 75, 2, 74, 73],  # G Major
	"G7": [62, 49, 75, 0, 74, 73]          # G7
}

# Runtime variables
var spectrum: AudioEffectSpectrumAnalyzerInstance
var is_active := false
var current_target_freqs := {}  # UI Index → Frequency
var wrong_notes := {}

func _ready():
	# Get spectrum analyzer instance from bus 0, effect slot 0
	spectrum = AudioServer.get_bus_effect_instance(0, 0)
	
	# Initialize UI
	reset_ui()
	
	# Connect button signal
	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)

func _on_start_button_pressed():
	if not is_active:
		start_detection()
	else:
		stop_detection()

func start_detection():
	if chord_to_detect.is_empty():
		push_warning("No chord selected for detection!")
		return
	
	reset_ui()
	
	# Get the chord notes based on the selected chord
	var chord_notes = chord_definitions.get(chord_to_detect, [])
	if chord_notes.is_empty():
		push_error("Unknown chord selected: %s" % chord_to_detect)
		return
	
	# Only show target chord notes as waiting
	for index in chord_notes:
		set_note_state(index, NoteState.WAIT)
		current_target_freqs[index] = note_frequencies[index]
	
	is_active = true
	if start_button:
		buttontext.text = "Stop Detection"

func stop_detection():
	is_active = false
	reset_ui()
	if start_button:
		buttontext.text = "Start Detection"

func reset_ui():
	# Mark everything inactive first
	for i in range(ui_notes.size()):
		set_note_state(i, NoteState.INACTIVE)
	current_target_freqs.clear()
	wrong_notes.clear()

func _process(_delta):
	if not is_active:
		return

	var detected_freq = get_dominant_frequency()
	if detected_freq <= 0:
		return

	var matched = false
	for index in current_target_freqs:
		var target_freq = current_target_freqs[index]
		if is_frequency_match(detected_freq, target_freq, index):
			if get_note_state(index) == NoteState.WAIT:
				set_note_state(index, NoteState.CORRECT)
			matched = true

	# If not matched to target, check if it's wrong
	if not matched:
		# Try to find closest note
		var closest_index = find_closest_note_index(detected_freq)
		if closest_index != null and get_note_state(closest_index) != NoteState.CORRECT:
			set_note_state(closest_index, NoteState.WRONG)
			wrong_notes[closest_index] = Time.get_ticks_msec()

	update_wrong_notes()

func get_dominant_frequency() -> float:
	var max_mag = 0.0
	var max_bin = 0

	for bin in range(1, FFT_SIZE / 2 - 1):
		var mag = get_bin_magnitude(bin)
		if mag > max_mag:
			max_mag = mag
			max_bin = bin

	if max_mag == 0:
		return 0.0

	# Parabolic interpolation
	var alpha = get_bin_magnitude(max_bin - 1)
	var beta = get_bin_magnitude(max_bin)
	var gamma = get_bin_magnitude(max_bin + 1)
	var denom = alpha - 2 * beta + gamma
	var offset = 0.0
	if denom != 0:
		offset = (alpha - gamma) / (2 * denom)

	return (max_bin + offset) * BIN_WIDTH

func get_bin_magnitude(bin: int) -> float:
	var low = BIN_WIDTH * (bin - 0.5)
	var high = BIN_WIDTH * (bin + 0.5)
	return spectrum.get_magnitude_for_frequency_range(low, high).length()

func is_frequency_match(detected: float, target: float, index: int) -> bool:
	var tolerance = DEFAULT_TOLERANCE
	if index == B_STRING_1 or index == B_STRING_3 or index == LOW_E_FRET_2:
		tolerance = B_STRING_TOLERANCE
	elif index >= LOW_E_START and index <= LOW_E_END:
		tolerance = LOW_E_TOLERANCE

	for harmonic in range(1, MAX_HARMONIC + 1):
		if abs(detected - target * harmonic) <= tolerance:
			return true

	return abs(detected - target) <= tolerance

func find_closest_note_index(freq: float) -> int:
	var min_diff = INF
	var closest = null
	for i in note_frequencies:
		var f = note_frequencies[i]
		var diff = abs(freq - f)
		if diff < min_diff:
			min_diff = diff
			closest = i
	return closest

func update_wrong_notes():
	var now = Time.get_ticks_msec()
	var to_remove = []
	for index in wrong_notes:
		if now - wrong_notes[index] > 1000:
			if get_note_state(index) == NoteState.WRONG:
				set_note_state(index, NoteState.INACTIVE)
			to_remove.append(index)
	for index in to_remove:
		wrong_notes.erase(index)

func set_note_state(index: int, state: NoteState):
	if index < 0 or index >= ui_notes.size():
		return

	var panel = ui_notes[index].get_node("Panel")
	panel.get_node("Correct").visible = (state == NoteState.CORRECT)
	panel.get_node("Wrong").visible = (state == NoteState.WRONG)
	panel.get_node("Wait").visible = (state == NoteState.WAIT)

func get_note_state(index: int) -> NoteState:
	var panel = ui_notes[index].get_node("Panel")
	if panel.get_node("Correct").visible:
		return NoteState.CORRECT
	if panel.get_node("Wrong").visible:
		return NoteState.WRONG
	if panel.get_node("Wait").visible:
		return NoteState.WAIT
	return NoteState.INACTIVE
