# DSBrain — Agent Guide

macOS menu bar app that runs and controls a local `ds4-server` process from the ds4 tree.

This file is the source of truth for product behavior and engineering norms.
Keep it aligned with the code. Prefer deleting obsolete guidance over documenting
legacy paths.

---

## Engineering norms

- Do not preserve backward compatibility. Remove obsolete paths; do not add
  compatibility layers, fallbacks, or migrations.
- Prefer the simplest implementation that fully meets current requirements.
- Keep modules focused. Separate AppKit chrome, process lifecycle, config,
  and SwiftUI views.
- Prefer established libraries already in the project (Yams) before inventing
  parsers or helpers.

---

## Tech stack

| Item | Choice |
|------|--------|
| Language | Swift 5.9+ |
| UI | AppKit status item + SwiftUI popover / preferences |
| Minimum OS | macOS 13 (Ventura) |
| Build | Swift Package Manager + `Makefile` → `DSBrain.app` |
| Config | YAML via [Yams](https://github.com/jpsim/Yams) |
| Server binary | `ds4-server` from ds4 tree (via launch command) |

There is no `.xcodeproj` in-tree. Open `Package.swift` or run `make xcode`.

---

## Product behavior

### Status item

- `NSStatusItem` with SF Symbol `brain` and a colored activity badge.
- Badge states: stopped · loading · ready · busy · error.
- Trailing compact metrics (togglable): vertical GPU/MEM mini-bars +
  `P: {n}tk/s` / `T: {n}tk/s` from a live ~3s rolling window +
  `C: {used}/{n_ctx}` / `S: {hit}%` from ds4-server log lines
  (context fill + SSD expert-cache hit rate).
- During prefill, the `T:` slot becomes `%:` + a horizontal accent bar
  (same thickness as the GPU/MEM tracks); after prefill, `T:` tk/s returns.
- Click opens a transient `NSPopover` anchored under the icon (closes on outside click).

### Popover

1. **Header** — app name, short version, Running/Stopped badge, Preferences.
2. **Projects** (accordion, default expanded) — recent folders opened with
   Pi / Codex / Cursor. Header `+` picks a directory then an agent; row click
   reopens with the last agent; trailing icon is Open with…. Persisted in
   `~/Library/Application Support/DSBrain/projects.yaml` (separate from config).
   Pi/Codex require ds4-server running; Cursor opens the folder in the IDE.
   Pi/Codex open a temp `.command` script via `open -a <terminal_app>` (no Apple
   Events). Default terminal is iTerm if installed, else Terminal — set in Preferences.
3. **Fans** (accordion) — fan RPM, temps, manual/rules control.
   When fan monitoring is enabled and `smc-helper` is not setuid-root,
   the collapsed header shows a short **Authorize** link (same flow as Preferences).
4. **Activity** (accordion, default expanded) — prefill % progress bar, context fill,
   SSD/KV cache lines, P/T speed chips, Last error.
5. **Server Log** (accordion, starts collapsed) — last N lines, selectable
   monospace text, sticky auto-scroll.
6. **Actions** — Start · Restart · Quit.
   Restart kills the running server (owned or adopted) then relaunches.
   Quit / Stop: owned → SIGTERM/SIGKILL; adopted → detach only.

### Server lifecycle

- `ServerManager` spawns the configured launch command via `bash -lc`.
- Cwd is the directory of the binary: absolute first token, or a PATH name
  (`ds4-server`) resolved with `bash -lc 'command -v …'`. Relative paths
  (`./eko.sh`) are rejected with a clear error.
- Default launch command: `ds4-server …` with typical flags, including
  `--host` / `--port` (edit model path in Preferences before first real start).
- Host/port for adopt detection and HTTP metrics are parsed from `--host` / `--port`
  in the launch command (defaults `127.0.0.1` / `8080` if missing).
- If `ds4-server` is already listening on that host/port, the app **adopts**
  that instance instead of spawning a second process.
- Port held by a non-`ds4-server` process: start aborts with a clear error.
- Restart (popover / Save & Restart): SIGTERM/SIGKILL owned **or adopted**, then start.
- Quit / stop owned server: SIGTERM, then SIGKILL after ~3s if still alive.
- Quit / stop adopted server: detach only — external `ds4-server` keeps running.
- Launch auto-starts when `auto_start` is true (default).

### Metrics

- Prefill / generation speeds from ds4-server logs (`LogParser`):
  `prefill chunk … chunk=N t/s` → P; `decoding chunk=N t/s` → T.
- Prefill progress % from `prefill chunk X/Y (Z%)` lines; sticky until
  `prompt done` / decode / stop (not cleared between slow chunk logs).
- SSD streaming expert-cache size from startup
  `SSD streaming total expert budget … dynamic cache (N experts, …)` plus live
  `streaming expert cache … hit_rate=` telemetry → Activity “SSD cache: …” line
  and tray `S: {hit}%` when `show_ssd_hit` is on.
- KV disk cache from `KV disk cache … (budget=… MiB)` and
  `kv cache hit … tokens=N … load=X ms` → Activity “KV cache: …” line
  (last hit size/latency + session hit count + budget).
- Context fill from logs: `context buffers … (ctx=N)` for window size and
  `ctx=cached..prompt:suffix` (+ optional `gen=N`) for tokens used → Activity
  progress + tray `C:`.
- Live ~3s rolling window in `ServerManager`.
- GPU % + GPU-mapped memory from AGXAccelerator (`GPUMetricsSampler`).
  Tray MEM fill is GPU-mapped alloc / physical DRAM — not host RAM.
  MEM bar color follows host memory pressure (`kern.memorystatus_vm_pressure_level`):
  green · yellow · red (Activity Monitor bands).
- Fan RPM + SMC temperatures (`FanMetricsSampler`, ~2s poll via `FanController`).
- Tray activity heuristics from log lines (`TrayActivityTracker`):
  `listening on http://` → ready; `prompt start` / prefill / decode → busy;
  `prompt done` / `finish=stop` / `finish=tool_calls` → idle.
- Refresh / fan / adopted-monitor timers run in `.common` run-loop mode so tray
  metrics keep updating while the popover is open.

### Memory watchdog

- Off by default (`enabled: false`). Samples **system** RAM via
  `host_statistics64` (`SystemMemorySampler`) on the 1s tick.
- When enabled and used % ≥ `max_system_memory_percent`, restarts an **owned**
  ds4-server.
- `kill_adopted` (default `false`): when true, also SIGTERM/SIGKILL an adopted
  external server before relaunch; when false, leave adopted alone (log only —
  not shown as Last error). Distinct from Restart, which always kills adopted.
- Cooldown prevents restart loops. Distinct from tray GPU MEM.

### Logging

- Popover ring buffer: `max_lines` (default 20).
- File: `~/Library/Application Support/DSBrain/logs/yyyy-MM-dd-server.log`.

---

## Configuration

Path: `~/Library/Application Support/DSBrain/config.yaml`

```yaml
server:
  launch_command: |
    ds4-server
      --model /path/to/ds4/ds4flash.gguf
      --metal
      --ssd-streaming
      --ssd-streaming-cache-experts 24GB
      --ctx 100000
      --tokens 384000
      --kv-disk-dir "$HOME/.cache/ds4-kv"
      --kv-disk-space-mb 8192
      --host 127.0.0.1
      --port 8080

max_lines: 20
auto_start: true
# Absolute .app path for Pi/Codex; empty → iTerm if installed, else Terminal
terminal_app: "/Applications/iTerm.app"

memory_watchdog:
  enabled: false
  max_system_memory_percent: 90
  cooldown_sec: 180
  kill_adopted: false

tray:
  show_gpu: true
  show_gpu_mem: true
  show_prefill_tps: true
  show_gen_tps: true
  show_ctx: true
  show_ssd_hit: true
  show_fan_rpm: true
  show_gpu_temp: true

fans:
  enabled: true
  poll_interval_sec: 2
  show_temps_in_popover: true
  rules:
    enabled: false
    on_quit_reset: true
    items: []
```

Notes:

- `launch_command` is run via `bash -lc` after newlines (and optional `\`
  continuations) are flattened to spaces; first token is an absolute binary
  path or a PATH name (`ds4-server`); include `--host` / `--port`.
- Cwd is derived from the resolved binary path (needed for relative Metal shader sources).
- Adopt detection uses host/port parsed from those flags.
- Preferences (⌘, from popover) edits the same schema and restarts the server
  (Restart kills adopted; Quit/Stop do not).
- `memory_watchdog` is off by default; when enabled, restarts owned ds4-server when
  host RAM used % crosses the threshold (not tray GPU MEM). Set `kill_adopted: true`
  only if adopted externals should be killed on watchdog trips too.

---

## Layout

```
DSBrain/
├── Makefile
├── Package.swift
├── icon.png
├── AGENTS.md
├── README.md
├── Casks/dsbrain.rb                # Homebrew cask (personal tap)
├── .github/workflows/release.yml
├── Tests/DSBrainTests/             # unit tests for pure logic
└── DSBrain/
    ├── AppEntry.swift
    ├── AppDelegate.swift
    ├── Config/                    # YAML, LaunchCommand, FanConfig, Projects, MemoryWatchdog
    ├── Server/                    # process, log parse, activity, FanController
    ├── Views/                     # SwiftUI + tray status + fan UI + Projects
    ├── SMCKit/                    # SMC IOKit driver + fan models
    ├── Helper/                    # smc-helper CLI (setuid for fan writes)
    └── Utilities/                 # paths, logger, process, GPU/system/fan/agent launchers
```

Fan control uses a bundled **setuid `smc-helper`**. Reads use in-process IOKit;
writes invoke the helper. Manual fan control can affect thermals — use at your own risk.

---

## Releases

- Version string lives in `DSBrain/Info.plist` (`CFBundleShortVersionString`).
- Local zip: `make release` → `DSBrain-<ver>-macos-arm64.zip`.
- GitHub: push tag `v*` → `.github/workflows/release.yml` runs tests,
  stamps plist from the tag, uploads the zip, creates the release, then
  bumps `Casks/dsbrain.rb` (`version` + `sha256`) on `main`.
- Homebrew (personal tap):
  `brew tap derkan/dsbrain https://github.com/derkan/dsbrain && brew trust derkan/dsbrain && brew install --cask dsbrain`

## Out of scope

- Hugging Face model browser / GGUF discovery
- Chat / multi-turn UI
- Global hotkeys
- Windows / Linux
- Code signing / notarization
