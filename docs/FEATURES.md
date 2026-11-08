# Feature checklist: omaview 0.1.0 → OmaSee 1.0.0

This was built by reading every file of omaview: its Python collector, the QML UI and the
JavaScript libraries. omaview ships as plain source, so nothing had to be decompiled. Each
row below is one omaview feature and where OmaSee provides it.

## Engine (collector)

| omaview feature | OmaSee |
|---|---|
| One JSON line every 2 s over a Unix socket | `hub.py`, same interval, configurable from 0.5 to 10 s |
| `flock` single instance shared across monitors | Kept, with an `O_NOFOLLOW` lock and a private-directory check |
| `detail on` / `detail off` per client | Kept; detail is now sent only to clients that asked for it, others get the short bar message |
| Wakes early when a report opens | Kept |
| Detects a dead shell with `prctl(PR_SET_PDEATHSIG)` | Kept |
| CPU user, system and total from `/proc/stat` | `kernel.cpu_stat` / `cpu_share`, values never go below zero |
| Per-core load and SMT sibling pairs | Kept (`host.topology`) |
| CPU temperature from k10temp, zenpower or coretemp | Kept, plus `cpu_thermal` and `acpitz` (ARM) |
| CPU power from RAPL | Kept; shows as missing when RAPL is root-only (it is on this laptop) |
| CPU frequency, load average, uptime | Kept, plus the CPU model name |
| Memory breakdown (apps, cache, shared, free), swap, PSI pressure | Kept |
| Network totals over physical interfaces only | Kept |
| Interface list with Wi-Fi/Ethernet and IPv4 | Kept, plus link speed |
| Disk read/write per whole disk, models, volumes (subvolumes folded) | Kept; mount names are unescaped and cleaned |
| Process table (CPU, private memory, I/O) grouped by app | Kept, with a 12-row limit and a total process count |
| Process names from the executable, falling back to `comm` for interpreters | Kept, with more interpreters and names cleaned |
| 0.25 s warm-up for a cold process list | Kept (`WarmTable`) |
| NVIDIA via NVML: load, VRAM, temp, power and limit, clocks, fan, P-state, engines, processes | Kept (`gpu.Nvidia`) |
| AMD/Intel via sysfs and fdinfo: busy, VRAM, hwmon, clocks, energy-based power, engines, processes | Kept (`gpu.Drm`) |
| Doesn't wake a GPU in runtime suspend | Kept; also reports an `asleep` flag |
| GPU ranking: discrete before integrated | Kept |
| vfio-pci passthrough GPUs | Kept; names come from `pci.ids` instead of running `lspci` |
| 120-point history for 15 series | Kept |
| Fake data mode | `--demo`, with smooth waves instead of square spikes |
| `--once` debug dump | Kept |

## UI

| omaview feature | OmaSee |
|---|---|
| Three bar sections: CPU, GPU, network | Kept, plus a heartbeat dot, sparkline and red text when hot; GPU hides when there's no GPU |
| Vertical bar support | Kept (short labels) |
| Hover to open after a delay (System waits longer) | Kept; delays come from config |
| Following the pointer with `hyprctl cursorpos` while a report is open | Kept |
| System closes when crossed without stopping | Kept |
| Click to open, exempt from pass-through closing | Clicking now toggles the report |
| IPC: open, close, edit | Kept, plus `toggle` |
| `summon` / `hide` / `toggle` through the bar | Kept (`opened`, `open()`, `close()`) |
| Popups anchored to their section, click-to-dismiss while editing | Kept (`Sheet.qml`) |
| Layout editor: metric, size, move, add, remove, reset, done | Kept (`Board.qml`, `deck.js`) |
| Only changed layouts saved to `shell.json` | Kept; now saved with an argument list, not a shell string |
| Untrusted saved layouts cleaned on load | Kept; card files come from a fixed list and are capped at 12 per column |
| 13 card types | All present, renamed: graph, dials, cores, vitals, top, engines, gpuApps, passthrough, links, storage, memory, temps, fans |
| Palette read from the theme's `colors.toml` | Kept; now reloads when the theme changes and has fallback colours |
| Fahrenheit setting | Kept |
| `config.json` hover settings | Kept, plus `closeDelayMs`, `animations`, `sparklines` and `heartbeat` |

## New in OmaSee

- **Stale detection:** sections dim and dots turn grey if no sample arrives for 6.5 s.
- **Report header:** shows a live heartbeat with a ripple on every sample, and a subtitle
  (CPU model, GPU vendor, uptime).
- **Animations:** gliding graphs, breathing markers, gauges that sweep, halos and pulses when
  a reading runs hot, staggered card entrances, spinning fans.
- **Tidier display:** cards hide readings this machine doesn't report, such as power, VRAM or
  fans, instead of showing "–".
