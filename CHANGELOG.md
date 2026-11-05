# Changelog

## 2026-11-05

### Video plays without a GPU

**Problem:** video did not play in any app that used Android's decoders. Decoding ran on the CPU, but every frame failed with:

```
C2AllocatorGralloc: failed transaction: lockYCbCr (err=3)
C2SoftAvcDec: graphic view map failed 14
```

**Cause:** redroid's software graphics module, `gralloc.redroid.so`, declares module API 0.1 and has no `lock_ycbcr` function. Decoders use that function to get the memory addresses of a frame's Y, U and V planes, so they could not write frames.

**Fix:** added `guest/gralloc-shim.c`, a small module that replaces `gralloc.redroid.so`:

1. Loads the original module, now `gralloc.redroid-real.so`, and copies its function table.
2. Declares module API 0.2 and adds `lock_ycbcr`.
3. Locks the buffer with the original `lock`, then returns plane addresses in YV12 layout.

`scripts/build-gralloc-shim.sh` builds it, and `scripts/build-rootfs.sh` installs it. The build needs no Android NDK. Run `build-rootfs.sh` to apply it to an existing VM, then `./avm up`.

**Tested in the Android WebView test browser:**

| Video | Result |
|---|---|
| 384×176 H.264 | Picture and colours correct in screenshots, and played to the end |
| 640×360, 1280×720, 1920×1080 H.264 | No decoder errors in about 10 seconds of playback; picture not inspected |

**Not tested:** Instagram and other apps, DRM video, sound, and actual smoothness at each resolution.

**Tried first, did not work:** the `vgem` kernel with the `cros` or `gbm` graphics modules. Android did not boot with either (`No such device`, then `failed to create gbm device`).

### Added

- `./avm video-log [-d]` shows decoder, graphics and shim logs. The shim logs its first 5 frames in each process, every 300th frame after that, and every failure, with the tag `FCGralloc`.
- `./avm fps <1-60>` sets the screen refresh rate and reboots. The default is now 30, up from 10. All drawing still uses the CPU, so the real frame rate can be lower than the setting.
- `./avm mcp info` and `./avm mcp json [file]` give MCP connection details and a ready-to-use config.
- `./avm` covers setup and daily use: `init`, `up`, `down`, `status`, `shell` and `adb`.

### Fixed

- WebVNC showed no cursor. The page now draws its own arrow over the phone screen.
- The VM shut down when the terminal that started it closed. Firecracker handles SIGHUP itself, so it now runs under `setsid`.
- Starting droidVNC-NG could remove the MCP app's accessibility service. Both services now stay enabled.
