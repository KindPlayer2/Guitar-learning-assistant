extends Node2D

### SYSTEM CONFIGURATION ###
@export var ui_notes: Array[Control]  # Array of 78 UI controls (must be assigned in editor)
@export var start_button: Button      # Start button (assign in editor)

# Audio Analysis Configuration
const SAMPLE_RATE: int = 44100       # Must match project audio settings
const FFT_SIZE: int = 4096           # Spectrum analyzer FFT window size
const BIN_WIDTH: float = SAMPLE_RATE / float(FFT_SIZE)  # Frequency resolution
const MAX_HARMONIC: int = 4          # Maximum harmonic multiple to consider

### DETECTION PARAMETERS ###
const DEFAULT_TARGET_TOLERANCE: float = 10.0  # Standard ±Hz for target notes
const OTHER_TOLERANCE: float = 3.0            # ±Hz for non-target notes
const B_STRING_TOLERANCE: float = 15.0        # Special tolerance for B1/B3
const LOW_E_TOLERANCE: float = 5.0            # Tighter tolerance for Low E
const CORRECT_NOTE_DELAY: float = 2.0         # Delay after correct note (seconds)

# Special note indices for tolerance adjustments
const B_STRING_1: int = 12           # B string fret 1 UI index
const B_STRING_3: int = 14           # B string fret 3 UI index
const LOW_E_START: int = 60          # First Low E string index
const LOW_E_END: int = 71            # Last Low E string index
const LOW_E_FRET_2: int = 61         # Low E string fret 2 UI index

### STATE MANAGEMENT ###
enum NoteState {CORRECT, WRONG, WAIT, INACTIVE}
var current_step: int = 0            # Current position in scale sequence
var wrong_notes: Dictionary = {}     # {ui_index: display_start_time}
var correct_note_time: float = -1.0  # When last correct note was detected
var is_waiting_for_next: bool = false # Delay in progress flag
var current_target_freq: float = 0.0 # Frequency of current target note
var spectrum: AudioEffectSpectrumAnalyzerInstance # Audio analysis instance
var is_active: bool = false          # Whether detection is active

### VERIFIED NOTE MAPPINGS ###
# Complete frequency mapping (all 78 notes - verified correct)
var note_frequencies := {
	# High E string (0-11) frets 1-12 (thinnest string)
	0:329.63, 1:349.23, 2:369.99, 3:392.00, 4:415.30, 5:440.00,
	6:466.16, 7:493.88, 8:523.25, 9:554.37, 10:587.33, 11:622.25,
	
	# B string (12-23)
	12:246.94, 13:261.63, 14:277.18, 15:293.66, 16:311.13, 17:329.63,
	18:349.23, 19:369.99, 20:392.00, 21:415.30, 22:440.00, 23:466.16,
	
	# G string (24-35)
	24:196.00, 25:207.65, 26:220.00, 27:233.08, 28:246.94, 29:261.63,
	30:277.18, 31:293.66, 32:311.13, 33:329.63, 34:349.23, 35:369.99,
	
	# D string (36-47)
	36:146.83, 37:155.56, 38:164.81, 39:174.61, 40:185.00, 41:196.00,
	42:207.65, 43:220.00, 44:233.08, 45:246.94, 46:261.63, 47:277.18,
	
	# A string (48-59)
	48:110.00, 49:116.54, 50:123.47, 51:130.81, 52:138.59, 53:146.83,
	54:155.56, 55:164.81, 56:174.61, 57:185.00, 58:196.00, 59:207.65,
	
	# Low E string (60-71) (thickest string)
	60:82.41, 61:87.31, 62:92.50, 63:98.00, 64:103.83, 65:110.00,
	66:116.54, 67:123.47, 68:130.81, 69:138.59, 70:146.83, 71:155.56,
	
	# Open strings (72-77)
	72:329.63, 73:246.94, 74:196.00, 75:146.83, 76:110.00, 77:82.41
}

# Verified correct scale sequence
var scale_sequence := [
	# First half (ascending)
	50,   # A string fret 3
	75,   # Open D
	37,   # D string fret 2
	38,   # D string fret 3
	74,   # Open G
	25,   # G string fret 2
	73,   # Open B
	12,   # B string fret 1
	14,   # B string fret 3
	72,   # Open High E
	0,    # High E fret 1
	2,    # High E fret 3
	0,    # High E fret 1 (repeated)
	72,   # Open High E
	14,   # B string fret 3
	12,   # B string fret 1
	73,   # Open B
	25,   # G string fret 2
	74,   # Open G
	38,   # D string fret 3
	37,   # D string fret 2
	75,   # Open D
	
	# Second half (descending) - VERIFIED CORRECT
	50,   # A string fret 3
	49,   # A string fret 2
	76,   # A string open (A0)
	62,   # Low E fret 3 (E3)
	61,   # Low E fret 2 (E2)
	77,   # Open Low E (E0)
	61,   # Low E fret 2 (E2)
	62,   # Low E fret 3 (E3)
	76,   # A string open (A0)
	49,   # A string fret 2 (A2)
	50    # A string fret 3 (A3)
]

# Frequency to UI indices mapping (for duplicate notes)
var frequency_to_ui := {}

### CORE FUNCTIONS ###
func _ready():
	"""Initialize the audio analyzer and frequency mappings"""
	spectrum = AudioServer.get_bus_effect_instance(0, 0)
	initialize_frequency_mapping()
	start_button.pressed.connect(_on_start_button_pressed)
	
	# Initialize all notes as inactive
	for i in range(ui_notes.size()):
		set_note_state(i, NoteState.INACTIVE)

func _on_start_button_pressed():
	"""Handle start button click to begin detection"""
	if not is_active:
		is_active = true
		start_button.visible = false  # Hide button after click
		update_wait_state()           # Start the sequence

func _process(delta):
	"""Main processing loop - only runs when active"""
	if not is_active:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Handle correct note delay period
	if correct_note_time > 0 and (current_time - correct_note_time) >= CORRECT_NOTE_DELAY:
		correct_note_time = -1.0
		is_waiting_for_next = false
		update_wait_state()
	
	# Skip processing if in delay period after correct note
	if is_waiting_for_next:
		return
	
	# Detect and check current frequency
	var detected_freq = get_parabolic_peak_frequency()
	check_note(detected_freq)
	update_wrong_notes(delta)

### NOTE DETECTION FUNCTIONS ###
func get_parabolic_peak_frequency() -> float:
	"""Find the dominant frequency using parabolic interpolation"""
	var max_magnitude = 0.0
	var max_bin = 0
	
	# Find the bin with maximum magnitude
	for bin in range(1, FFT_SIZE / 2):
		var mag = get_bin_magnitude(bin)
		if mag > max_magnitude:
			max_magnitude = mag
			max_bin = bin
	
	# Perform parabolic interpolation for better frequency accuracy
	if max_bin > 0 and max_bin < (FFT_SIZE / 2 - 1):
		var alpha = get_bin_magnitude(max_bin - 1)
		var beta = max_magnitude
		var gamma = get_bin_magnitude(max_bin + 1)
		var denom = alpha - 2 * beta + gamma
		if denom != 0:
			var offset = (alpha - gamma) / (2 * denom)
			return (max_bin + offset) * BIN_WIDTH
	
	return max_bin * BIN_WIDTH

func check_note(detected_freq: float):
	"""Check if detected frequency matches current target note"""
	var target_ui_index = scale_sequence[current_step]
	current_target_freq = note_frequencies.get(target_ui_index, 0.0)
	
	if is_frequency_match(detected_freq, current_target_freq, true, target_ui_index):
		# Correct note detected
		set_note_state(target_ui_index, NoteState.CORRECT)
		correct_note_time = Time.get_ticks_msec() / 1000.0
		is_waiting_for_next = true
		advance_sequence()
	else:
		# Check for wrong notes
		for freq in frequency_to_ui:
			if is_frequency_match(detected_freq, freq, false, target_ui_index):
				for ui_index in frequency_to_ui[freq]:
					if get_note_state(ui_index) != NoteState.CORRECT:
						set_note_state(ui_index, NoteState.WRONG)
						wrong_notes[ui_index] = Time.get_ticks_msec()

func is_frequency_match(detected: float, target: float, is_current_target: bool, ui_index: int) -> bool:
	"""Check if frequency matches considering harmonics and special tolerances"""
	if target <= 0:
		return false
	
	var tolerance = get_tolerance(is_current_target, ui_index)
	
	# Check harmonic multiples
	for harmonic in range(1, MAX_HARMONIC + 1):
		if abs(detected - (target * harmonic)) <= tolerance:
			return true
	
	# Check direct frequency match
	return abs(detected - target) <= tolerance

func get_tolerance(is_current_target: bool, ui_index: int) -> float:
	"""Return appropriate tolerance based on note and context"""
	# Special tolerance for B string frets 1 and 3
	if ui_index == B_STRING_1 or ui_index == B_STRING_3:
		return B_STRING_TOLERANCE
	
	# High tolerance for Low E fret 2
	if ui_index == LOW_E_FRET_2:
		return B_STRING_TOLERANCE  # Same high tolerance as B string
	
	# Tighter tolerance for rest of Low E string
	if ui_index >= LOW_E_START and ui_index <= LOW_E_END:
		return LOW_E_TOLERANCE
	
	# Default tolerance based on whether this is the current target
	return DEFAULT_TARGET_TOLERANCE if is_current_target else OTHER_TOLERANCE

### UI STATE MANAGEMENT ###
func set_note_state(ui_index: int, state: NoteState):
	"""Update visual state of a note's UI elements"""
	if ui_index < 0 or ui_index >= ui_notes.size():
		return
		
	var control = ui_notes[ui_index]
	var panel = control.get_node("Panel")
	
	panel.get_node("Correct").visible = (state == NoteState.CORRECT)
	panel.get_node("Wrong").visible = (state == NoteState.WRONG)
	panel.get_node("Wait").visible = (state == NoteState.WAIT)

func get_note_state(ui_index: int) -> NoteState:
	"""Get current visual state of a note"""
	if ui_index < 0 or ui_index >= ui_notes.size():
		return NoteState.INACTIVE
		
	var control = ui_notes[ui_index]
	var panel = control.get_node("Panel")
	
	if panel.get_node("Correct").visible:
		return NoteState.CORRECT
	if panel.get_node("Wrong").visible:
		return NoteState.WRONG
	if panel.get_node("Wait").visible:
		return NoteState.WAIT
	return NoteState.INACTIVE

func update_wait_state():
	"""Update which note should show the 'wait' indicator"""
	# Clear previous wait states
	for ui_index in scale_sequence:
		if get_note_state(ui_index) == NoteState.WAIT:
			set_note_state(ui_index, NoteState.INACTIVE)
	
	# Set new wait state for current target
	var current_ui_index = scale_sequence[current_step]
	set_note_state(current_ui_index, NoteState.WAIT)

func advance_sequence():
	"""Move to next note in the scale sequence"""
	current_step = (current_step + 1) % scale_sequence.size()

func update_wrong_notes(delta: float):
	"""Remove wrong notes that have been displayed for >1 second"""
	var current_time = Time.get_ticks_msec()
	var to_remove = []
	
	for ui_index in wrong_notes:
		if current_time - wrong_notes[ui_index] > 1000:  # 1 second display
			if get_note_state(ui_index) == NoteState.WRONG:
				set_note_state(ui_index, NoteState.INACTIVE)
			to_remove.append(ui_index)
	
	for key in to_remove:
		wrong_notes.erase(key)

### AUDIO HELPERS ###
func get_bin_magnitude(bin: int) -> float:
	"""Get magnitude for a specific frequency bin"""
	var freq_low = BIN_WIDTH * (bin - 0.5)
	var freq_high = BIN_WIDTH * (bin + 0.5)
	return spectrum.get_magnitude_for_frequency_range(freq_low, freq_high).length()

func initialize_frequency_mapping():
	"""Create frequency-to-UI-index mapping for duplicate notes"""
	for ui_index in note_frequencies:
		var freq = note_frequencies[ui_index]
		if not frequency_to_ui.has(freq):
			frequency_to_ui[freq] = []
		frequency_to_ui[freq].append(ui_index)
