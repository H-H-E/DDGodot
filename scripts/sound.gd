class_name DashSound
extends Node
## Original synthesized tones; no downloads, streaming or licensed recordings.
var enabled := true
var volume := 0.35
var voices: Array[AudioStreamPlayer] = []
var tones: Dictionary = {}
var cursor := 0

func _ready() -> void:
	for i in range(4):
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
	for key in ["correct", "wrong", "jump", "beat", "finish"]:
		tones[key] = _synth(key)

func play_tone(key: String) -> void:
	if not enabled or voices.is_empty() or not tones.has(key):
		return
	var p := voices[cursor % voices.size()]
	cursor += 1
	p.stream = tones[key]
	p.volume_db = linear_to_db(maxf(volume * (0.22 if key == "beat" else 0.65), 0.001))
	p.play()

func hush() -> void:
	for p in voices:
		p.stop()

func _synth(key: String) -> AudioStreamWAV:
	var hz: float = {"correct": 660.0, "wrong": 180.0, "jump": 440.0, "beat": 220.0, "finish": 880.0}[key]
	var duration: float = 0.35 if key in ["correct", "finish"] else 0.14
	var bytes := PackedByteArray()
	var count := int(22050 * duration)
	bytes.resize(count * 2)
	for i in range(count):
		var t := float(i) / 22050.0
		var env := minf(1, t * 100) * pow(1 - t / duration, 2)
		var signal_value := sin(TAU * hz * t) * 0.5 + sin(TAU * hz * 1.5 * t) * 0.15
		bytes.encode_s16(i * 2, int(signal_value * env * 24000))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.data = bytes
	return wav
