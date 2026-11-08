"""GPU telemetry.

NVIDIA comes from the driver's NVML library via ctypes. AMD (amdgpu) and Intel (i915, xe)
come from sysfs and the per-client DRM stats in /proc/<pid>/fdinfo. Any reading may be
missing on a given card or kernel, so every field may be None.
"""
import ctypes
import os
import pathlib
import re
import time

from . import kernel

# ---------------------------------------------------------------- DRM (AMD / Intel)

DRM_DRIVERS = {"amdgpu", "i915", "xe"}
UNIT = {"KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "": 1}
LOCAL_MEM = re.compile(r"^(vram|local)\d*$")

RENDER = {"gfx", "render", "rcs"}
COMPUTE = {"compute", "ccs"}
# Intel video engines encode and decode without saying which, so they count for both.
DECODE = {"dec", "dec_1", "video", "vcs"}
ENCODE = {"enc", "enc_1", "video", "vcs"}
JPEG = {"jpeg"}

ENGINE_FIELDS = (("engine-capacity-", "capacity"), ("total-cycles-", "total"), ("cycles-", "cycles"), ("engine-", "ns"))


def _text(path, limit=4096):
    try:
        with open(path, "rb") as handle:
            return handle.read(limit).decode("utf-8", "replace").strip()
    except OSError:
        return None


def _int(path):
    text = _text(path, 64)
    try:
        return int(text) if text is not None else None
    except ValueError:
        return None


def fdinfo(text):
    """Stats for one DRM client fd, or None when the fd isn't an identifiable DRM client."""
    pdev = client = None
    engines, regions, legacy = {}, {}, {}
    for line in text.splitlines():
        key, _, value = line.partition(":")
        value = value.strip()
        if key == "drm-pdev":
            pdev = value
        elif key == "drm-client-id":
            client = value
        elif key.startswith("drm-"):
            _stat(key[4:], value, engines, regions, legacy)
    if pdev is None or client is None:
        return None
    # amdgpu also prints drm-memory-* as a legacy alias; only fall back to it.
    return {"pdev": pdev, "client": client, "engines": engines, "memory": sum({**legacy, **regions}.values())}


def _stat(key, value, engines, regions, legacy):
    parts = value.split()
    try:
        amount = int(parts[0])
    except (IndexError, ValueError):
        return
    for prefix, field in ENGINE_FIELDS:
        if key.startswith(prefix):
            engines.setdefault(key[len(prefix):], {})[field] = amount
            return
    for prefix, target in (("total-", regions), ("memory-", legacy)):
        if key.startswith(prefix) and LOCAL_MEM.match(key[len(prefix):]):
            target[key[len(prefix):]] = amount * UNIT.get(parts[1] if len(parts) > 1 else "", 1)


def drm_clients():
    """(pid, fdinfo) for every DRM fd we may read, which is only our own processes."""
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            fds = os.listdir(f"/proc/{name}/fd")
        except OSError:
            continue
        for fd in fds:
            try:
                if not os.readlink(f"/proc/{name}/fd/{fd}").startswith("/dev/dri/"):
                    continue
                with open(f"/proc/{name}/fdinfo/{fd}", "rb") as handle:
                    found.append((int(name), handle.read(16384).decode("utf-8", "replace")))
            except OSError:
                continue
    return found


def busy_pct(now, before, span):
    capacity = now.get("capacity") or 1
    if "cycles" in now and "total" in now:
        spent = now["total"] - before.get("total", now["total"])
        busy = now["cycles"] - before.get("cycles", now["cycles"])
        return 100.0 * max(0, busy) / spent / capacity if spent > 0 else 0.0
    if "ns" in now and span > 0:
        busy = now["ns"] - before.get("ns", now["ns"])
        return 100.0 * max(0, busy) / (span * 1e9) / capacity
    return 0.0


def _class_sum(engines, names):
    return sum(pct for name, pct in engines.items() if name in names)


def _finish_rows(rows):
    grouped = kernel.rollup(rows, "memory", 10)
    grouped.sort(key=lambda r: (r["usage"], r["memory"]), reverse=True)
    for r in grouped:
        r["type"] = "C+G" if r["compute"] and r["graphics"] else "C" if r["compute"] else "G"
        del r["compute"], r["graphics"]
    return grouped


class Card:
    def __init__(self, path, driver, address, name):
        self.path, self.driver, self.address, self.name = path, driver, address, name
        self.dev = path / "device"
        mons = sorted((self.dev / "hwmon").glob("hwmon*"))
        self.hwmon = mons[0] if mons else self.dev / "hwmon" / "none"
        self.prev_clients, self.client_time = {}, None
        self.energy, self.energy_time = None, None

    @property
    def amd(self):
        return self.driver == "amdgpu"

    @property
    def vram_total(self):
        return _int(self.dev / "mem_info_vram_total") if self.amd else None

    @property
    def rank(self):
        """Lower first: the card the bar should show. Discrete before integrated."""
        if self.amd:
            return (0, -(self.vram_total or 0))
        return (1 if self.address.startswith("0000:00:02.") else 0, 0)


class Drm:
    @classmethod
    def open(cls, root="/sys/class/drm", names=None, describe=None, clients=drm_clients, clock=time.monotonic, primary=True):
        base = pathlib.Path(root)
        if not base.is_dir():
            return None
        cards = []
        for path in sorted(base.iterdir()):
            if not re.fullmatch(r"card\d+", path.name):
                continue
            try:
                driver = (path / "device" / "driver").resolve().name
                address = (path / "device").resolve().name
            except OSError:
                continue
            if driver in DRM_DRIVERS:
                label = _text(path / "device" / "product_name", 128) or (describe(address) if describe else address)
                cards.append(Card(path, driver, address, kernel.clean_name(label)))
        return cls(sorted(cards, key=lambda c: c.rank), names, clients, clock, primary) if cards else None

    def __init__(self, cards, names, clients, clock, primary=True):
        self._cards, self._names, self._clients, self._clock, self._primary = cards, names or str, clients, clock, primary

    def sample(self, detail):
        now = self._clock()
        # Intel has no global busy file, so the bar number needs a client scan; only pay for
        # it when that Intel card is the one on the bar.
        scan = detail or (self._primary and not self._cards[0].amd)
        clients = self._scan() if scan else {}
        return [self._card(c, clients.get(c.address, {}), scan, now, detail) for c in self._cards]

    def _scan(self):
        by_card = {}
        for pid, text in sorted(self._clients()):
            parsed = fdinfo(text)
            if parsed:
                by_card.setdefault(parsed["pdev"], {}).setdefault(parsed["client"], {**parsed, "pid": pid})
        return by_card

    def _rates(self, card, clients, now):
        if card.client_time is None:
            rates = None
        else:
            span = now - card.client_time
            rates = {cid: {e: busy_pct(st, card.prev_clients.get(cid, {}).get(e, {}), span) for e, st in s["engines"].items()}
                     for cid, s in clients.items()}
        card.prev_clients = {cid: s["engines"] for cid, s in clients.items()}
        card.client_time = now
        return rates

    def _card(self, card, clients, scan, now, detail):
        rates = self._rates(card, clients, now) if scan else None
        engines = self._engine_totals(rates)
        mem_used = sum(c["memory"] for c in clients.values()) if clients else None
        if _text(card.dev / "power" / "runtime_status", 32) == "suspended":
            # Reading sensors would wake a sleeping card, which costs battery.
            f = dict.fromkeys(("memPct", "memUsed", "memTotal", "temp", "power", "powerLimit", "clock", "clockMax", "fan"))
            f["usage"] = 0
            f["asleep"] = True
        elif card.amd:
            f = self._amd(card)
        else:
            f = self._intel(card, engines, mem_used, now)
        out = {"name": card.name, "usage": f["usage"], "memPct": f["memPct"], "temp": f["temp"], "power": f["power"]}
        if not detail:
            return out
        e = engines or {}
        out.update({
            "vendor": "amd" if card.amd else "intel", "asleep": bool(f.get("asleep")),
            "memUsed": f["memUsed"], "memTotal": f["memTotal"], "powerLimit": f["powerLimit"],
            "clock": f["clock"], "clockMax": f["clockMax"], "memClock": None, "fan": f["fan"], "pstate": None,
            "engines": {"graphics": f["usage"] if card.amd else e.get("graphics"), "encode": e.get("encode"),
                        "decode": e.get("decode"), "jpeg": e.get("jpeg"), "opticalFlow": None},
            "processes": self._procs(clients, rates),
        })
        return out

    @staticmethod
    def _engine_totals(rates):
        if rates is None:
            return None
        t = {"graphics": 0.0, "encode": 0.0, "decode": 0.0, "jpeg": 0.0}
        for eng in rates.values():
            t["graphics"] += _class_sum(eng, RENDER | COMPUTE)
            t["encode"] += _class_sum(eng, ENCODE)
            t["decode"] += _class_sum(eng, DECODE)
            t["jpeg"] += _class_sum(eng, JPEG)
        return {k: round(min(100.0, v), 1) for k, v in t.items()}

    def _amd(self, card):
        used, total = _int(card.dev / "mem_info_vram_used"), card.vram_total
        power = _int(card.hwmon / "power1_average")
        if power is None:
            power = _int(card.hwmon / "power1_input")
        limit, clock = _int(card.hwmon / "power1_cap"), _int(card.hwmon / "freq1_input")
        temp, pwm = _int(card.hwmon / "temp1_input"), _int(card.hwmon / "pwm1")
        levels = re.findall(r"(\d+)\s*Mhz", _text(card.dev / "pp_dpm_sclk") or "", re.IGNORECASE)
        return {
            "usage": _int(card.dev / "gpu_busy_percent"),
            "memPct": round(100.0 * used / total, 1) if used is not None and total else None,
            "memUsed": used, "memTotal": total,
            "temp": round(temp / 1000, 1) if temp is not None else None,
            "power": round(power / 1e6, 1) if power is not None else None,
            "powerLimit": round(limit / 1e6) if limit else None,
            "clock": round(clock / 1e6) if clock is not None else None,
            "clockMax": max(int(x) for x in levels) if levels else None,
            "fan": round(100 * pwm / 255) if pwm is not None else None,
        }

    def _intel(self, card, engines, mem_used, now):
        temp = _int(card.hwmon / "temp2_input")
        if temp is None:
            temp = _int(card.hwmon / "temp1_input")
        limit = _int(card.hwmon / "power1_max") or _int(card.hwmon / "power2_max")
        if card.driver == "xe":
            freq = card.dev / "tile0" / "gt0" / "freq0"
            clock, clock_max = _int(freq / "act_freq"), _int(freq / "rp0_freq")
        else:
            clock, clock_max = _int(card.path / "gt_act_freq_mhz"), _int(card.path / "gt_RP0_freq_mhz")
        return {
            "usage": max(engines.values()) if engines else None,
            "memPct": None, "memUsed": mem_used, "memTotal": None,
            "temp": round(temp / 1000, 1) if temp is not None else None,
            "power": self._intel_power(card, now),
            "powerLimit": round(limit / 1e6) if limit else None,
            "clock": clock, "clockMax": clock_max, "fan": None,
        }

    @staticmethod
    def _intel_power(card, now):
        energy = _int(card.hwmon / "energy1_input")
        if energy is None:
            energy = _int(card.hwmon / "energy2_input")
        prev, prev_t = card.energy, card.energy_time
        card.energy, card.energy_time = energy, now
        if energy is None or prev is None or now <= prev_t:
            return None
        return round(max(0, energy - prev) / (now - prev_t) / 1e6, 1)

    def _procs(self, clients, rates):
        rows = []
        for cid, s in clients.items():
            eng = (rates or {}).get(cid, {})
            names = set(s["engines"])
            rows.append({
                "name": self._names(s["pid"]), "memory": s["memory"],
                "usage": min(100.0, round(_class_sum(eng, RENDER | COMPUTE), 1)),
                "encode": min(100.0, round(_class_sum(eng, ENCODE), 1)),
                "decode": min(100.0, round(_class_sum(eng, DECODE), 1)),
                "compute": 1 if names & COMPUTE else 0, "graphics": 1 if names & RENDER else 0,
            })
        return _finish_rows(rows)


# ---------------------------------------------------------------- NVIDIA (NVML)

NVML_OK = 0
NVML_NA = 0xFFFFFFFFFFFFFFFF


class _Util(ctypes.Structure):
    _fields_ = [("gpu", ctypes.c_uint), ("memory", ctypes.c_uint)]


class _Mem(ctypes.Structure):
    _fields_ = [("total", ctypes.c_ulonglong), ("free", ctypes.c_ulonglong), ("used", ctypes.c_ulonglong)]


class _Proc(ctypes.Structure):
    _fields_ = [("pid", ctypes.c_uint), ("usedGpuMemory", ctypes.c_ulonglong),
                ("gpuInstanceId", ctypes.c_uint), ("computeInstanceId", ctypes.c_uint)]


class _ProcSample(ctypes.Structure):
    _fields_ = [("pid", ctypes.c_uint), ("timeStamp", ctypes.c_ulonglong), ("smUtil", ctypes.c_uint),
                ("memUtil", ctypes.c_uint), ("encUtil", ctypes.c_uint), ("decUtil", ctypes.c_uint)]


class Nvidia:
    @classmethod
    def open(cls, library="libnvidia-ml.so.1", names=None):
        # Bare soname: resolved only through the system loader paths (we run with -I, no LD tricks added).
        try:
            lib = ctypes.CDLL(library)
            if lib.nvmlInit_v2() != NVML_OK:
                return None
        except (OSError, AttributeError):
            return None
        return cls(lib, names)

    def __init__(self, lib, names):
        self._lib, self._names = lib, names or str
        count = ctypes.c_uint()
        lib.nvmlDeviceGetCount_v2(ctypes.byref(count))
        self._devs = []
        for i in range(min(count.value, 16)):
            handle = ctypes.c_void_p()
            if lib.nvmlDeviceGetHandleByIndex_v2(i, ctypes.byref(handle)) == NVML_OK:
                buf = ctypes.create_string_buffer(96)
                name = buf.value.decode("utf-8", "replace") if lib.nvmlDeviceGetName(handle, buf, 96) == NVML_OK else "GPU"
                self._devs.append({"handle": handle, "name": kernel.clean_name(name), "seen": 0})

    def _uint(self, fn_name, handle, *args):
        fn = getattr(self._lib, fn_name, None)
        if fn is None:
            return None
        v = ctypes.c_uint()
        return v.value if fn(handle, *args, ctypes.byref(v)) == NVML_OK else None

    def _codec(self, fn_name, handle):
        fn = getattr(self._lib, fn_name, None)
        if fn is None:
            return None
        v, period = ctypes.c_uint(), ctypes.c_uint()
        return v.value if fn(handle, ctypes.byref(v), ctypes.byref(period)) == NVML_OK else None

    def sample(self, detail):
        return [self._dev(d, detail) for d in self._devs]

    def _dev(self, d, detail):
        h = d["handle"]
        util, mem = _Util(), _Mem()
        has_util = self._lib.nvmlDeviceGetUtilizationRates(h, ctypes.byref(util)) == NVML_OK
        has_mem = self._lib.nvmlDeviceGetMemoryInfo(h, ctypes.byref(mem)) == NVML_OK
        power = self._uint("nvmlDeviceGetPowerUsage", h)
        out = {
            "name": d["name"], "usage": util.gpu if has_util else None,
            "memPct": round(100.0 * mem.used / mem.total, 1) if has_mem and mem.total else None,
            "temp": self._uint("nvmlDeviceGetTemperature", h, 0),
            "power": round(power / 1000, 1) if power is not None else None,
        }
        if not detail:
            return out
        limit = self._uint("nvmlDeviceGetPowerManagementLimit", h)
        out.update({
            "vendor": "nvidia", "asleep": False,
            "memUsed": mem.used if has_mem else None, "memTotal": mem.total if has_mem else None,
            "powerLimit": round(limit / 1000) if limit is not None else None,
            "clock": self._uint("nvmlDeviceGetClockInfo", h, 0),
            "clockMax": self._uint("nvmlDeviceGetMaxClockInfo", h, 0),
            "memClock": self._uint("nvmlDeviceGetClockInfo", h, 2),
            "fan": self._uint("nvmlDeviceGetFanSpeed", h),
            "pstate": self._uint("nvmlDeviceGetPerformanceState", h),
            "engines": {
                "graphics": util.gpu if has_util else None,
                "encode": self._codec("nvmlDeviceGetEncoderUtilization", h),
                "decode": self._codec("nvmlDeviceGetDecoderUtilization", h),
                "jpeg": self._codec("nvmlDeviceGetJpgUtilization", h),
                "opticalFlow": self._codec("nvmlDeviceGetOfaUtilization", h),
            },
            "processes": self._procs(d),
        })
        return out

    def _running(self, h, kind):
        for ver in ("_v3", "_v2"):
            fn = getattr(self._lib, f"nvmlDeviceGet{kind}RunningProcesses{ver}", None)
            if fn is None:
                continue
            n = ctypes.c_uint(128)
            buf = (_Proc * 128)()
            if fn(h, ctypes.byref(n), buf) == NVML_OK:
                return list(buf[:min(n.value, 128)])
        return []

    def _usage(self, d):
        buf = (_ProcSample * 128)()
        n = ctypes.c_uint(128)
        status = self._lib.nvmlDeviceGetProcessUtilization(d["handle"], buf, ctypes.byref(n), ctypes.c_ulonglong(d["seen"]))
        d["seen"] = int((time.time() - 1) * 1_000_000)
        if status != NVML_OK:
            return {}
        latest = {}
        for s in buf[:min(n.value, 128)]:
            cur = latest.get(s.pid)
            if cur is None or s.timeStamp > cur.timeStamp:
                latest[s.pid] = s
        return latest

    def _procs(self, d):
        rows = {}
        for kind, flag in (("Compute", "compute"), ("Graphics", "graphics")):
            for info in self._running(d["handle"], kind):
                r = rows.setdefault(info.pid, {"name": self._names(info.pid), "memory": 0, "usage": 0, "encode": 0,
                                               "decode": 0, "compute": 0, "graphics": 0})
                r[flag] = 1
                if info.usedGpuMemory and info.usedGpuMemory != NVML_NA:
                    r["memory"] = max(r["memory"], info.usedGpuMemory)
        for pid, s in self._usage(d).items():
            if pid in rows:
                rows[pid].update(usage=s.smUtil, encode=s.encUtil, decode=s.decUtil)
        return _finish_rows(list(rows.values()))


# ---------------------------------------------------------------- combined

class Chain:
    def __init__(self, sources):
        self._sources = sources

    def sample(self, detail):
        out = []
        for src in self._sources:
            try:
                out.extend(src.sample(detail))
            except Exception:  # one broken vendor must not hide the others
                continue
        return out


def chain(*sources):
    live = [s for s in sources if s is not None]
    return Chain(live) if live else None
