# MRP: AudioStreamWAV forward loop reads one frame past `loop_end`

Minimal reproduction project for [godotengine/godot#124849](https://github.com/godotengine/godot/issues/124849).

`AudioStreamPlaybackWAV::_mix_internal()` derives the size of a decode batch from
`end_limit`, which is `loop_end` for looping streams. `loop_end` is exclusive, but
`limit` is used as an inclusive upper bound (`aux = (limit - offset) / increment + 1`),
so the engine decodes frame index `loop_end` on every forward loop iteration. When
`loop_end` equals the number of frames in the stream (which happens when a stream is
built from code), that is an out-of-bounds read of two bytes past the PCM data.

## What this project does

`main.gd` builds `AudioStreamWAV` instances at runtime:

- mono, 16-bit PCM, 22050 Hz, 8 seconds = 176400 frames (plus three players with one,
  three and seven extra frames, so the crash does not depend on one exact allocation size);
- `loop_mode = LOOP_FORWARD`, `loop_begin = 0`, `loop_end = frame count`;
- the PCM buffer is grown with `append()` one frame at a time, like code-generated music;
- plays them with `AudioStreamPlayer`s and prints a heartbeat every five seconds.

On the device where this bug was first reported the app died with `SIGSEGV` /
`SEGV_ACCERR` a few seconds after the music started looping, with the `loop_end` frame
index in `rsi` and the fault address two bytes past the end of the PCM buffer (tombstone
and symbolized stack are in godotengine/godot#124849).

Whether the two-byte overrun turns into a hard fault depends on where the allocator put
the PCM buffer: it faults only when the mapping ends right after it, otherwise the read
lands in adjacent (mapped) heap memory and playback just keeps going. If the prebuilt APK
does not crash on your device, run a build with AddressSanitizer (or the MRP test in
`tests/scene/test_audio_stream_wav.cpp`) to see the out-of-bounds access deterministically.

Every loop iteration reads frame 176400, i.e. 2 bytes past the end of the sample data.

## Reproducing the crash

**Android release build** (the crash from the issue): export the project as a release
APK (it is enough to enable one ABI matching your device/emulator, e.g. `arm64-v8a`
or `x86_64`), install it and launch it. On the affected engine the process dies with
`SIGSEGV` / `SEGV_ACCERR` a few seconds after playback starts (the out-of-bounds read
hits an unmapped page). `adb logcat` shows the tombstone; the top frames are
`AudioStreamPlaybackWAV::decode_samples()` and
`AudioStreamPlaybackWAV::_mix_internal()`.

**Desktop** (no crash, but the bug is still there): the read usually lands inside
mapped heap memory, so the app keeps running, but one frame of unrelated memory is
mixed into the output once per loop. Build the engine with AddressSanitizer and run
`godot --path .` to get a heap-buffer-overflow report pointing at the same
`decode_samples()` call.

With the fix from
[the PR](https://github.com/884020583/godot/tree/fix/audio-stream-wav-loop-end-oob)
the app keeps playing on every platform.

## Files

- `project.godot` / `main.tscn` — project and scene;
- `main.gd` — builds the looping stream and plays it;
- `export_presets.cfg` — Android export preset (arm64-v8a + x86_64).