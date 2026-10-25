# ASan evidence for the AudioStreamWAV `loop_end` out-of-bounds read

Deterministic reproduction of the bug reported in [godotengine/godot#124849](https://github.com/godotengine/godot/issues/124849) and fixed in [godotengine/godot#124863](https://github.com/godotengine/godot/pull/124863), without needing a device: the regression test added by the PR is the trigger.

- `unfixed.log` — engine built with `scene/resources/audio/audio_stream_wav.cpp` reverted to the commit before the fix: `AddressSanitizer: heap-buffer-overflow`, `READ of size 2`, `0 bytes after` the sample buffer, in `AudioStreamPlaybackWAV::decode_samples<short,...>` (`audio_stream_wav.cpp:195`) called from `_mix_internal` (`:368`). Exit code 1.
- `fixed.log` — same build configuration with the PR's one-line fix: the test passes (3001 assertions, 0 failures). No ASan report.

Build/run (GitHub Actions, Ubuntu):

```console
$ scons platform=linuxbsd target=editor dev_build=yes use_asan=yes tests=yes -j$(nproc)
$ bin/godot.linuxbsd.editor.dev.x86_64.san --headless --test \
    --test-case="*Forward loop does not read past loop_end*"
```

Workflow: https://github.com/884020583/godot/blob/ci/asan-audio-oob/.github/workflows/asan-audio-oob.yml
Run (step logs + `asan-logs` artifact): https://github.com/884020583/godot/actions/runs/40210208819

Note: use `--test-case`, not `--test-suite`. `tests/scene/test_audio_stream_wav.cpp` defines no `TEST_SUITE`, so `--test-suite="[Audio]"` selects nothing.

The on-device crash (the APK in the repository root) still depends on allocator/page layout — that is exactly why this ASan run is the deterministic evidence.