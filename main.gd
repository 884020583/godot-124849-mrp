extends Node

# Minimal reproduction project for godotengine/godot#124849.
#
# AudioStreamPlaybackWAV::_mix_internal() derives the size of a decode batch from
# `loop_end`, but the loop end is exclusive while `limit` is used as an inclusive bound
# (`aux = (limit - offset) / increment + 1`). For a forward loop whose `loop_end` equals
# the frame count, the engine therefore decodes frame index `frame_count`, one frame past
# the end of `data`, on every loop iteration.
#
# On Android release builds that read can land on an unmapped page and the process dies
# with SIGSEGV/SEGV_ACCERR after a few seconds. On desktop the read normally lands in
# mapped heap memory, so the app keeps running; build with ASAN to catch it there.

const RATE := 22050
const SECONDS := 8.0
const AMPLITUDE := 0.25

var _player: AudioStreamPlayer
var _start_msec := 0
var _next_report_sec := 5.0


func _ready() -> void:
	var frames := int(SECONDS * RATE)
	var stream := _build_stream()
	print("MRP: frames=%d loop_begin=%d loop_end=%d format=%d stereo=%s mix_rate=%d" % [
		frames, stream.loop_begin, stream.loop_end, stream.format,
		str(stream.stereo), stream.mix_rate])

	_player = AudioStreamPlayer.new()
	_player.stream = stream
	add_child(_player)
	_player.play()
	_start_msec = Time.get_ticks_msec()
	print("MRP: playing a %.1f s forward loop; a crash after a few seconds means "
		% SECONDS + "the engine read frame index `loop_end`, past the end of the sample data.")


func _build_stream() -> AudioStreamWAV:
	var frames := int(SECONDS * RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in frames:
		var sample := roundi(sin(TAU * 440.0 * float(i) / float(RATE)) * AMPLITUDE * 32767.0)
		bytes.encode_s16(i * 2, clampi(sample, -32768, 32767))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	# The loop end is exclusive, so looping here covers every PCM frame and nothing else.
	# The engine still decodes frame `loop_end`, i.e. one frame past the end of `data`.
	stream.loop_end = frames
	return stream


func _process(_delta: float) -> void:
	var elapsed := (Time.get_ticks_msec() - _start_msec) / 1000.0
	if elapsed >= _next_report_sec:
		print("MRP: still alive after %.0f s of looping playback" % _next_report_sec)
		_next_report_sec += 5.0
