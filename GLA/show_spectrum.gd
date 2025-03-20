extends Node2D

# Constants
const VU_COUNT: int = 800               # Number of frequency bands (bars) to display.
const FREQ_MAX: float = 11050.0         # Maximum frequency range (in Hz).
const WIDTH: int = 800                  # Width of the visualization (in pixels).
const HEIGHT: int = 250                 # Height of the visualization (in pixels).
const HEIGHT_SCALE: float = 8.0         # Scale factor for the height of the bars (the magnitude).
const MIN_DB: float = 80.0              # Minimum decibel threshold for measurement.
const ANIMATION_SPEED: float = 0.15     # Speed of the animation transition for bars.
const MIN_FREQ_THRESHOLD: float = 80.0  # Minimum frequency to consider.

# Variables
var spectrum: AudioEffectSpectrumAnalyzerInstance  # Instance of the spectrum analyzer.
var min_values: Array[float] = []                  # Minimum values for each frequency band.
var max_values: Array[float] = []                  # Maximum values for each frequency band.
var max_index: int = 0                             # Index of the bar with the highest magnitude.

# Labels
var DbLabel: Label  # Display the highest Db value.
var FreqLabel: Label  # Display the frequency with the highest magnitude.
var StringLabel: Label  # Display the detected guitar string.
var RawFreqLabel: Label  # Display the raw (non-interpolated) frequency.
var ParabolicDiffLabel: Label  # Display the difference between parabolic and raw frequency.

# Guitar string frequencies (in Hz)
const GUITAR_STRINGS: Dictionary = {
	"low e": 82.41,
	"a": 110.00,
	"d": 146.83,
	"g": 196.00,
	"b": 246.94,
	"high e": 329.63
}

func _draw() -> void:
	# Calculate the width of each bar.
	var w: float = WIDTH / VU_COUNT
	
	# Loop through all frequency bands (bars).
	for i in range(VU_COUNT):
		# Interpolated height for animation.
		var height: float = lerp(min_values[i], max_values[i], ANIMATION_SPEED)
		
		# Determine the color of the bar.
		var color: Color = Color.BLUE if i == max_index else Color.RED
		
		# Draw the main frequency bar.
		draw_rect(
			Rect2(w * i, HEIGHT - height, w - 2, height),  # Position and size.
			color  # Color of the bar.
		)

		# Draw the top border of the bar for visualization enhancement.
		draw_line(
			Vector2(w * i, HEIGHT - height),
			Vector2(w * i + w - 2, HEIGHT - height),
			color,  # Border color matches the bar.
			1.0,
			true
		)

func _process(_delta: float) -> void:
	# Array to store magnitudes for each frequency range.
	var spectrum_magnitudes: Array[float] = []
	var spectrum_freqs: Array[float] = []
	
	# Sample the entire spectrum using the audio effect spectrum analyzer
	var min_freq: float = 20.0  # Start from audible range
	var freq_range_max: float = FREQ_MAX
	var step: float = (freq_range_max - min_freq) / 100.0  # Sampling 100 points
	
	var max_raw_magnitude: float = 0.0
	var raw_max_freq: float = 0.0
	
	# Sample spectrum and find raw max frequency
	for i in range(100):
		var freq: float = min_freq + i * step
		var magnitude: float = spectrum.get_magnitude_for_frequency_range(freq, freq + step).length()
		
		spectrum_magnitudes.append(magnitude)
		spectrum_freqs.append(freq + step / 2.0)
		
		# Find raw max frequency
		if magnitude > max_raw_magnitude:
			max_raw_magnitude = magnitude
			raw_max_freq = freq + step / 2.0
	
	# Find max index for parabolic interpolation
	var max_index_para: int = 0
	for i in range(1, spectrum_magnitudes.size() - 1):
		if spectrum_magnitudes[i] > spectrum_magnitudes[max_index_para]:
			max_index_para = i
	
	# Parabolic interpolation
	var alpha: float = spectrum_magnitudes[max_index_para - 1]
	var beta: float = spectrum_magnitudes[max_index_para]
	var gamma: float = spectrum_magnitudes[max_index_para + 1]
	
	var peak_offset: float = 0.5 * (alpha - gamma) / (alpha - 2 * beta + gamma)
	var interpolated_freq: float = spectrum_freqs[max_index_para] + peak_offset * step
	
	# Ignore frequencies below the threshold
	if interpolated_freq < MIN_FREQ_THRESHOLD:
		interpolated_freq = MIN_FREQ_THRESHOLD
		raw_max_freq = MIN_FREQ_THRESHOLD
	
	# Array to store heights for each frequency band.
	var data: Array[float] = []
	var prev_hz: float = 0.0

	# Loop to calculate the magnitude for each frequency band.
	for i in range(1, VU_COUNT + 1):
		var hz: float = i * FREQ_MAX / VU_COUNT
		var magnitude: float = spectrum.get_magnitude_for_frequency_range(prev_hz, hz).length()
		var energy: float = clamp((MIN_DB + linear_to_db(magnitude)) / MIN_DB, 0, 1)
		var height: float = energy * HEIGHT * HEIGHT_SCALE
		data.append(height)
		prev_hz = hz

	# Update min and max values for each band.
	for i in range(VU_COUNT):
		if data[i] > max_values[i]:
			max_values[i] = data[i]
		else:
			max_values[i] = lerp(max_values[i], data[i], ANIMATION_SPEED)
		if data[i] <= 0.0:
			min_values[i] = lerp(min_values[i], 0.0, ANIMATION_SPEED)

	# Find the peak bar index for visualization
	max_index = 0
	for i in range(1, VU_COUNT - 1):
		if data[i] > data[max_index]:
			max_index = i

	# Detect the nearest guitar string
	var closest_string: String = ""
	var closest_diff: float = INF
	if interpolated_freq >= MIN_FREQ_THRESHOLD:
		for string_name in GUITAR_STRINGS.keys():
			var string_freq: float = GUITAR_STRINGS[string_name]
			var diff: float = abs(interpolated_freq - string_freq)
			if diff < closest_diff:
				closest_diff = diff
				closest_string = string_name

	# Update labels
	DbLabel.text = "Db: " + str(linear_to_db(max_raw_magnitude))
	FreqLabel.text = "Parabolic Frequency: " + str(interpolated_freq) + " Hz"
	RawFreqLabel.text = "Raw Frequency: " + str(raw_max_freq) + " Hz"
	ParabolicDiffLabel.text = "Frequency Diff: " + str(abs(interpolated_freq - raw_max_freq)) + " Hz"
	StringLabel.text = "String: " + closest_string

	# Redraw the visualization.
	queue_redraw()

func _ready() -> void:
	# Initialize the spectrum analyzer.
	spectrum = AudioServer.get_bus_effect_instance(1, 1)
	
	# Resize and initialize arrays for frequency bands.
	min_values.resize(VU_COUNT)
	max_values.resize(VU_COUNT)
	min_values.fill(0.0)
	max_values.fill(0.0)

	# Initialize labels.
	DbLabel = $DbLabel
	FreqLabel = $FreqLabel
	StringLabel = $StringLabel
	RawFreqLabel = $RawFreqLabel
	ParabolicDiffLabel = $ParabolicDiffLabel
