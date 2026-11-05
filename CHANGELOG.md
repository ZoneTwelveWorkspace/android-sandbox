# Changelog

## 2026-11-05

### AI View Browser

`./avm mcp view` starts a local page that explains an AI's MCP calls in plain Traditional Chinese, with a wireframe of what it sees, the spot it touched, and the screen before and after each action. See `viewer/` and the README.

**Tested on Android 16, with a script and the Google search below:** tap, swipe, scroll, element clicks, typing Chinese, failed calls, updates within about 2 seconds of each action, and refusing requests with no token or from other sites.

**Not tested:** Android 14, a client connected with `VIEW=1 ./avm mcp add`, and the file, camera and clipboard tools.

**Found while using it for a real Google search on Android 16:**

- `android_press_key` with `ENTER` failed with `No focused node` in a web page. Tapping the on-screen key worked.
- Google showed a reCAPTCHA, which a person has to solve in WebVNC.
- The WebView test browser returned to the home screen when opening a Threads post, and can't open `intent://` links. Firefox, installed by hand, opened the same post.

### Android 16 runs in a separate VM

`AVM_NAME=android-16 ./avm init` creates a second Lima VM with Android 16, on ports 6016 and 8716. The Android 14 VM keeps its own kernel and image.

Android 16 needed three kernel changes that Android 14 does not, all in the Android 16 kernel only:

| Boot failure | Cause | Fix |
|---|---|---|
| `bootstrap-apexd-failed`, device-mapper errors | Android 16 mounts its APEX packages at boot, and the kernel had no device-mapper | `kernel/android16.fragment`, plus a `/dev/device-mapper` link in `guest/fc-init` |
| `bootstrap-apexd-failed`, `Can't open blockdev` | The kernel refused to mount loop devices that were open for writing | `CONFIG_BLK_DEV_WRITE_MOUNTED=y` |
| `surfaceflinger` aborts with `output buffer not gpu writeable` | Android 16 only uses memfd if it answers ashmem ioctls, which mainline Linux does not provide, so graphics buffers could not be allocated | `kernel/ashmem-memfd-compat.patch` |

**Tested on Android 16:** boot, WebVNC with the cursor, MCP tool calls, and a 384×176 H.264 video in the WebView test browser, which played to the end with the right picture and colours.

**Not tested on Android 16:** a fresh `./avm init` from nothing (the VM was built step by step), and the gralloc shim's `lock_ycbcr`. The shim loads, but that video logged no call to it, so apps that decode through Android's codecs, such as Instagram, are unverified.

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
