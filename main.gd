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
#
# The PCM buffer is grown with append() one frame at a time, which is what a game
# generating its music from code (like the one in the original report) does; the
# allocation layout then makes the two bytes past the end land in an unmapped page.

const RATE := 22050
const SECONDS := 8.0
const AMPLITUDE := 0.25

var _players: Array[AudioStreamPlayer] = []
var _start_msec := 0
var _next_report_sec := 5.0


func _ready() -> void:
	var frames := int(SECONDS * RATE)
	var stream := _build_stream()
	print("MRP: frames=%d loop_begin=%d loop_end=%d format=%d stereo=%s mix_rate=%d" % [
		frames, stream.loop_begin, stream.loop_end, stream.format,
		str(stream.stereo), stream.mix_rate])
	print("MRP: data size=%d bytes" % stream.data.size())

	# One player is enough to hit the bug, but a few independent streams with different
	# lengths make the crash depend less on allocator luck.
	for frame_count in [frames, frames + 1, frames + 3, frames + 7]:
		var player := AudioStreamPlayer.new()
		player.stream = (stream if frame_count == frames else _build_stream(frame_count))
		add_child(player)
		player.play()
		_players.append(player)
	_start_msec = Time.get_ticks_msec()
	print("MRP: playing %.1f s forward loop(s); a crash after a few seconds means "
		% SECONDS + "the engine read frame index `loop_end`, past the end of the sample data.")


func _build_stream(p_frames: int = -1) -> AudioStreamWAV:
	var frames := int(SECONDS * RATE) if p_frames < 0 else p_frames
	var bytes := PackedByteArray()
	bytes.resize(2)
	for i in frames:
		var sample := roundi(sin(TAU * 440.0 * float(i) / float(RATE)) * AMPLITUDE * 32767.0)
		var frame := PackedByteArray()
		frame.resize(2)
		frame.encode_s16(0, clampi(sample, -32768, 32767))
		bytes.append(frame[0])
		bytes.append(frame[1])

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
