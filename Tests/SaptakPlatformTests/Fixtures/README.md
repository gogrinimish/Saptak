Synthetic 440 Hz tone generated for Saptak tests; contains no personal recording.
Covered by the repository MIT license. Reproduce with the development-only tool:

```sh
ffmpeg -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=0.25' -c:a aac -y tone.m4a
```

FFmpeg is not an app or test runtime dependency.
