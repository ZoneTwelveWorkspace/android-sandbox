# Android Sandbox on Firecracker

Run Android 14 in a Firecracker microVM on an Apple Silicon Mac, then operate it two ways:

- **WebVNC:** use the phone in your browser.
- **MCP:** let an AI agent read the screen and tap, through a server running on the phone.

```
Mac → Lima VM (nested KVM) → Firecracker → Android 14 (redroid)
                                            ├─ droidVNC-NG → noVNC  → http://127.0.0.1:6080/
                                            └─ MCP server  → socat  → http://127.0.0.1:8765/mcp
```

## Requirements

- Mac with an M3 chip or newer (nested virtualization isn't available on M1 or M2)
- About 40 GB of free disk space and 8 GB of free memory
- [Lima](https://lima-vm.io): `brew install lima`

## Quick start

```bash
git clone git@github.com:ZoneTwelveWorkspace/android-sandbox.git
cd android-sandbox
./avm init
```

`init` creates the Lima VM, downloads and builds everything, and boots Android. The full run took about 6 minutes on an M4, including a first boot of about 50 seconds. It's safe to rerun if a download fails, because finished steps are skipped.

When it finishes:

- **WebVNC:** open <http://127.0.0.1:6080/>
- **MCP:** run `./avm mcp add` to register the server with Claude Code

After that, `./avm up` boots Android in about 30 seconds.

## Commands

| Command | What it does |
|---|---|
| `./avm init` | Build everything from scratch, then boot |
| `./avm up` | Boot or reboot Android, and start WebVNC and MCP |
| `./avm down` | Stop Android and keep the Lima VM running |
| `./avm status` | Show what is running, and the URLs |
| `./avm fps <1-60>` | Set the screen refresh rate and reboot (default 30) |
| `./avm video-log [-d]` | Follow decoder and graphics logs, or print them and exit with `-d` |
| `./avm shell` | Open a shell in the Lima VM |
| `./avm adb <args>` | Run ADB against Android, for example `./avm adb shell getprop` |
| `./avm mcp info` | Print the MCP URL, token and auth header, and check the server is reachable (`./avm mcp` does the same) |
| `./avm mcp json [file]` | Print a ready-to-use MCP config, or write it to a private file |
| `./avm mcp add [name]` | Register the server with Claude Code (default name: `android`) |

## Android 16

Android 16 runs in its own Lima VM, separate from the default Android 14 VM. Both can run at once.

```bash
AVM_NAME=android-16 ./avm init
```

- WebVNC: http://127.0.0.1:6016/
- MCP: http://127.0.0.1:8716/mcp

Put `AVM_NAME=android-16` before every `./avm` command for this VM, for example `AVM_NAME=android-16 ./avm mcp info`.

To run another Android 16 VM, use a different name that starts with `android-16`, and different ports:

```bash
AVM_NAME=android-16-2 WEB_PORT=6017 MCP_PORT=8717 ./avm init
```

Repeat all three settings on every `./avm` command for that VM.

## Using MCP

The server has 44 tools with the `android_` prefix, including `android_get_screen_state`, `android_tap` and `android_type_append_text`. Camera and location tools appear only if you grant the app those permissions.

Any MCP client can connect using Streamable HTTP and the bearer token:

```bash
./avm mcp info              # URL, token and auth header
./avm mcp json              # print the config below, with your token filled in
./avm mcp json mcp.json     # write it to a file only you can read
./avm mcp add               # or register it directly with Claude Code
```

```json
{
  "mcpServers": {
    "android": {
      "type": "http",
      "url": "http://127.0.0.1:8765/mcp",
      "headers": { "Authorization": "Bearer <your token>" }
    }
  }
}
```

`mcp.json` and `.mcp.json` are ignored by git because they contain the token.

Screen text is untrusted input. An app or web page could show text that tries to steer the agent.

## AI View Browser

A page that explains, in plain Traditional Chinese, everything an AI does on the phone through MCP.

```bash
./avm mcp view
```

Keep it running and open http://127.0.0.1:9765/ (the MCP port plus 1000, or set `VIEW_PORT`). Then connect the AI through it:

```bash
VIEW=1 ./avm mcp add android-view
```

An AI connected to the normal MCP port does not appear in the page.

| Part of the page | What it shows |
|---|---|
| **AI 所見** | The list of screen elements, drawn as a wireframe, with the spot the AI touched marked |
| **截圖** | The screenshot from that moment |
| **即時畫面** | The phone now, through WebVNC, read-only |
| **AI 做了什麼** | Each call as a sentence, with its result and duration |
| **這一步的細節** | What the AI sent and what the phone returned |
| **AI 能做的事** | Every tool on this phone, and how often it was used |

After each action, the viewer reads the screen once more for the 動作後 view. The AI does not receive that copy, and the page says so.

The viewer needs `python3` on the Mac. It listens on `127.0.0.1` only and refuses requests from other sites. It passes the token through without recording it, so an AI still needs the token. Calls and screenshots stay in memory until it stops, and they can include text the AI typed.

## Security

Everything is reachable only from this Mac. Before making anything public:

- **VNC has no password.** Put WebVNC behind authentication first.
- **MCP uses plain HTTP inside the Mac.** Public access needs HTTPS in front of it.
- **Never publish ADB (5555) or raw VNC (5900).** They stay on the private network inside the Lima VM.
- **Leave the MCP app's built-in tunnel off.** It would expose the phone through a third party, so `start-mcp.sh` disables it.
- **Don't sign in to real accounts.** An authenticated MCP client controls the whole device.

The bearer token is created on first boot and stored in `~/fc/mcp-token` inside the Lima VM. To replace it:

```bash
limactl shell android-fc bash -c 'rm ~/fc/mcp-token'
./avm up
```

Then update your clients. For Claude Code, run `claude mcp remove android` and `./avm mcp add`. For a config file, rerun `./avm mcp json`.

## Settings

| Variable | Default | Purpose |
|---|---|---|
| `AVM_NAME` | `android-fc` | Lima VM name. A name starting with `android-16` selects Android 16 |
| `WEB_PORT` | `6080` (Android 16: `6016`) | WebVNC port on the Mac |
| `MCP_PORT` | `8765` (Android 16: `8716`) | MCP port on the Mac |
| `LIMA_CPUS`, `LIMA_MEMORY`, `LIMA_DISK` | `6`, `8`, `40` | Lima VM size |
| `VCPUS`, `MEM_MIB` | `6`, `4096` | Android VM size |
| `KERNEL_MIRROR` | none | Extra Linux kernel mirror to try first (Aliyun, Tsinghua and kernel.org are built in) |
| `REDROID_IMAGE` | pinned digest | A different redroid image |
| `DEBUG` | `0` | Set to `1` when building disks to save boot logs to `/data` |

Downloads are pinned by version and checksum. To start over with a clean phone, run this in `./avm shell` and then `./avm up`:

```bash
~/fc/repo/scripts/down.sh && RESET_DATA=1 ~/fc/repo/scripts/build-rootfs.sh
```

To remove everything: `limactl delete -f android-fc`

## Why it's built this way

If boot slows down or the screen goes black, check these first:

- **Huge pages are essential.** 2 MB pages with 6 vCPUs took cold boot from about 30 minutes to 9 seconds under nested virtualization. Fewer vCPUs was slower, not faster.
- **`/fc-init` passes boot flags to Android.** redroid's `init` reads `androidboot.*` from its arguments rather than `/proc/cmdline`.
- **`psi=1` is required.** Firecracker's kernel config turns PSI off by default, and `lmkd` crash-loops without it.
- **droidVNC-NG replaces redroid's VNC server.** The built-in one fails with `error creating EGLImage: 0x300c` under software rendering.
- **Firecracker runs under `setsid`.** It installs its own SIGHUP handler, so `nohup` alone lets a closing terminal shut the VM down.
- **`gralloc-shim.c` makes video play.** redroid's software graphics module can't lock YUV buffers, so CPU decoders fail with `lockYCbCr` and `graphic view map failed`. The shim adds that function, without a GPU.
- **The page draws its own cursor.** Android sends no pointer shape, so noVNC would hide it. `run-webvnc.sh` adds `novnc-cursor.js` to a copy of noVNC, and `show_touches` draws a mark on the phone at each touch.

## Known limits

- arm64 only, with software rendering. There is no GPU, camera or modem.
- No Google services, so apps that need Play or Play Integrity probably won't work.
- 20 system apps are disabled to reduce load, including Bluetooth, Camera and Contacts. See `scripts/setup-android.sh`.
- Non-fatal `fs-verity` and network statistics errors appear in the Android logs.
- MCP v1.12.0 only binds to `127.0.0.1` or `0.0.0.0`. Here `0.0.0.0` covers only loopback and the private link to the Lima VM.

## Licences

The apps and images are downloaded from their upstream projects when you run `init`, and aren't included in this repo. Each keeps its own licence: [redroid](https://github.com/remote-android/redroid-doc), [droidVNC-NG](https://github.com/bk138/droidVNC-NG), [android-remote-control-mcp](https://github.com/danielealbano/android-remote-control-mcp) (GPL-3.0-or-later, and its README says research and educational use only).
