extends Node2D

@onready var freq_label: Label = $FreqLabel
var spectrum: AudioEffectSpectrumAnalyzerInstance

# Audio settings (match these to your AudioEffectSpectrumAnalyzer settings!)
const SAMPLE_RATE: int = 44100  # Must match Godot's Audio Server "Mix Rate"
const FFT_SIZE: int = 4096      # Must match the FFT size in AudioEffectSpectrumAnalyzer

# Frequency resolution per FFT bin (calculated)
var bin_width: float = SAMPLE_RATE / float(FFT_SIZE)

func _ready():
	"""Initialize the spectrum analyzer instance."""
	spectrum = AudioServer.get_bus_effect_instance(0, 0)  # Ensure spectrum analyzer is on bus 0

func _process(delta):
	"""Update the frequency label with the first observed peak and all observed peaks."""
	var peaks = get_significant_peaks()
	
	if peaks.is_empty():
		freq_label.text = "No significant peaks detected."
		return
	
	# Always use the first observed peak as the suggested frequency
	var suggested_freq = peaks[0]["freq"]
	
	# Format the peaks for display
	var peaks_text = "Observed Peaks: " + ", ".join(peaks.map(func(peak): return "%.2f Hz" % peak["freq"]))
	
	# Display the suggested frequency and observed peaks
	freq_label.text = "Suggested Frequency: %.2f Hz\n%s" % [suggested_freq, peaks_text]

func get_significant_peaks() -> Array:
	"""
	Find all significant peaks in the spectrum.
	A peak is significant if it is above the noise floor and is a local maximum.
	Returns an array of peaks sorted by frequency (lowest first).
	"""
	var peaks = []
	var noise_floor = calculate_noise_floor()

	for bin in range(1, FFT_SIZE / 2):  # Skip DC offset (bin 0)
		var magnitude = get_bin_magnitude(bin)
		if magnitude > noise_floor && is_local_max(bin):
			peaks.append({
				"bin": bin,
				"freq": bin * bin_width,
				"mag": magnitude
			})

	# Sort peaks by frequency (lowest first)
	peaks.sort_custom(func(a, b): return a["freq"] < b["freq"])
	return peaks

func is_local_max(bin: int) -> bool:
	"""
	Check if the given bin is a local maximum.
	"""
	var current = get_bin_magnitude(bin)
	var prev = get_bin_magnitude(bin - 1) if bin > 1 else 0.0
	var next = get_bin_magnitude(bin + 1) if bin < (FFT_SIZE / 2 - 1) else 0.0
	return current > prev && current > next

func calculate_noise_floor() -> float:
	"""
	Calculate the noise floor as 20% of the maximum magnitude in the spectrum.
	"""
	var max_magnitude = 0.0
	for bin in range(1, FFT_SIZE / 2):
		max_magnitude = max(max_magnitude, get_bin_magnitude(bin))
	return max_magnitude * 0.2  # 20% of max magnitude as noise floor

func get_bin_magnitude(bin: int) -> float:
	"""
	Get the magnitude of a specific FFT bin.
	"""
	var freq_low = bin_width * (bin - 0.5)
	var freq_high = bin_width * (bin + 0.5)
	return spectrum.get_magnitude_for_frequency_range(freq_low, freq_high).length()
