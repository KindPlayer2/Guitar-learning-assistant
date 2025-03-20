extends Node2D

@onready var freq_label: Label = $FreqLabel
var spectrum: AudioEffectSpectrumAnalyzerInstance

# Audio settings
const SAMPLE_RATE: int = 44100
const FFT_SIZE: int = 4096
var bin_width: float = SAMPLE_RATE / float(FFT_SIZE)

# Audio playback
@export var audio_stream: AudioStreamMP3
@export var audio_player: AudioStreamPlayer2D

# Target frequencies for musical notes
var target_frequencies = {
	"C3": 130.81,
	"D3": 146.83,
	"E3": 164.81,
	"F3": 174.61,
	"G3": 196.00,
	"A3": 220.00,
	"B3": 246.94,
	"C4": 261.63,
	"D4": 293.66,
	"E4": 329.63,
	"F4": 349.23,
	"G4": 392.00,
	"A4": 440.00,
	"B4": 493.88,
	"C5": 523.25,
	"D5": 587.33,
	"E5": 659.25,
	"F5": 698.46
}

# Segmentation
var segment_number := 1
var last_peak_time := 0.0
var min_segment_gap := 0.1  # Minimum time between segments (in seconds)
const FREQ_TOLERANCE := 10.0  # Tolerance for frequency matching (in Hz)
var has_started_segmenting := false  # Flag to track if segmentation has started

func _ready():
	# Initialize spectrum analyzer
	spectrum = AudioServer.get_bus_effect_instance(0, 0)
	
	# Set up audio
	if audio_stream:
		audio_player.stream = audio_stream
		audio_player.play()
	else:
		print("Error: No audio stream provided.")

func _process(delta):
	if audio_player.playing and segment_number <= target_frequencies.size():
		var current_time = audio_player.get_playback_position()
		
		# Check for significant peaks
		var peaks = get_significant_peaks()
		if not peaks.is_empty() and (current_time - last_peak_time) >= min_segment_gap:
			var detected_freq = peaks[0]["freq"]
			
			# If segmentation hasn't started, check for the first frequency (C3: 130.81 Hz ± 10 Hz)
			if not has_started_segmenting:
				if abs(detected_freq - target_frequencies["C3"]) <= FREQ_TOLERANCE:
					has_started_segmenting = true
					analyze_segment(segment_number, "C3", detected_freq)
					segment_number += 1
					last_peak_time = current_time
			else:
				# If segmentation has started, look for the next target frequency in sequence
				var target_note = target_frequencies.keys()[segment_number - 1]
				var target_freq = target_frequencies[target_note]
				
				if abs(detected_freq - target_freq) <= FREQ_TOLERANCE:
					analyze_segment(segment_number, target_note, detected_freq)
					segment_number += 1
					last_peak_time = current_time
				else:
					# If the correct frequency is not detected, mark as undetected and move on
					analyze_segment(segment_number, "undetected", 0.0)
					segment_number += 1
					last_peak_time = current_time

func analyze_segment(segment_number: int, note: String, frequency: float):
	# Update the label with the segment number, note, and frequency
	if freq_label.text.is_empty():
		freq_label.text = "%d: %s (%.1f Hz)" % [segment_number, note, frequency]
	else:
		freq_label.text += ", %d: %s (%.1f Hz)" % [segment_number, note, frequency]

func get_significant_peaks() -> Array:
	var peaks = []
	var noise_floor = calculate_noise_floor()
	
	for bin in range(1, FFT_SIZE / 2):
		var magnitude = get_bin_magnitude(bin)
		var frequency = bin * bin_width
		
		if magnitude > noise_floor && is_local_max(bin):
			peaks.append({
				"bin": bin,
				"freq": frequency,
				"mag": magnitude
			})
	
	# Sort by magnitude descending
	peaks.sort_custom(func(a, b): return a["mag"] > b["mag"])
	return peaks

func is_local_max(bin: int) -> bool:
	var current = get_bin_magnitude(bin)
	var prev = get_bin_magnitude(bin - 1) if bin > 1 else 0.0
	var next = get_bin_magnitude(bin + 1) if bin < (FFT_SIZE / 2 - 1) else 0.0
	return current > prev && current > next

func calculate_noise_floor() -> float:
	var max_magnitude = 0.0
	for bin in range(1, FFT_SIZE / 2):
		max_magnitude = max(max_magnitude, get_bin_magnitude(bin))
	return max_magnitude * 0.2

func get_bin_magnitude(bin: int) -> float:
	var freq_low = bin_width * (bin - 0.5)
	var freq_high = bin_width * (bin + 0.5)
	return spectrum.get_magnitude_for_frequency_range(freq_low, freq_high).length()
