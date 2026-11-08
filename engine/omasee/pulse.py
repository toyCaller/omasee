"""Builds one JSON-ready message per tick from the raw readers."""
import collections

from . import host, kernel

HISTORY = 120  # samples; at 2 s per tick that is four minutes


class History:
    def __init__(self, capacity=HISTORY):
        self._cap, self._series = capacity, {}

    def add(self, name, value):
        self._series.setdefault(name, collections.deque(maxlen=self._cap)).append(value)

    def dump(self):
        return {k: list(v) for k, v in self._series.items()}


class Rate:
    """Per-second rate of a growing counter. A reset reads as zero, never a negative spike."""

    def __init__(self):
        self._v = self._t = None

    def update(self, value, now):
        pv, pt = self._v, self._t
        self._v, self._t = value, now
        if pv is None or now <= pt:
            return None
        return max(0.0, (value - pv) / (now - pt))


def guard(fn, fallback):
    try:
        return fn()
    except Exception:  # a single broken source must never take the engine down
        return fallback


class Pulse:
    def __init__(self, read, clock, ifaces, disks, sensors, gpu, rapl, topology, passthrough,
                 processes, volumes, models, links, cpu_model=lambda: None):
        self._read, self._clock = read, clock
        self._ifaces, self._disks, self._sensors, self._gpu = ifaces, disks, sensors, gpu
        self._rapl, self._passthrough, self._processes = rapl, passthrough, processes
        self._volumes, self._models, self._links = volumes, models, links
        self._topology = guard(topology, [])
        self._cpu_model = guard(cpu_model, None)
        self._history = History()
        self._cpu_prev = None
        self._rates = collections.defaultdict(Rate)
        self._seq = 0

    def sample(self, detail):
        self._seq += 1
        now = self._clock()
        stat = self._cpu()
        sensors = guard(self._sensors, {"temps": [], "fans": []})
        cpu = stat["summary"]
        cpu["temp"] = host.cpu_temp(sensors["temps"])
        cpu["power"] = self._power(now)
        gpus = guard(lambda: self._gpu.sample(detail) if self._gpu else [], [])
        down, up = self._net(now)
        disk = self._disk(now)
        mem = self._mem()
        self._record(cpu, gpus, (down, up), disk, mem)

        msg = {"seq": self._seq, "t": now, "detail": detail, "cpu": cpu, "gpu": gpus,
               "net": {"down": down, "up": up}, "mem": {"usedPct": mem.get("usedPct")}}
        if not detail:
            return msg
        cpu.update(freq=self._freq(), cores=stat["cores"], threads=self._topology, load=self._loadavg(),
                   uptime=self._uptime(), model=self._cpu_model)
        msg["gpuPassthrough"] = guard(self._passthrough, [])
        msg["mem"] = mem
        msg["disks"] = {"volumes": guard(self._volumes, []), "models": guard(self._models, {}),
                        "read": disk[0], "write": disk[1], "perDisk": disk[2]}
        msg["net"]["interfaces"] = guard(self._links, [])
        msg["sensors"] = sensors
        msg["processes"] = guard(self._processes, {})
        msg["history"] = self._history.dump()
        return msg

    def _cpu(self):
        blank = {"summary": {"user": None, "system": None, "usage": None}, "cores": []}
        text = self._read("/proc/stat")
        if not text:
            return blank
        cur = kernel.cpu_stat(text)
        prev, self._cpu_prev = self._cpu_prev, cur
        if prev is None or cur["total"] is None:
            return blank
        cores = {i: kernel.cpu_share(prev["cores"][i], t)["usage"] for i, t in cur["cores"].items() if i in prev["cores"]}
        return {"summary": kernel.cpu_share(prev["total"], cur["total"]),
                "cores": [cores.get(i, 0.0) for i in range(max(cores, default=-1) + 1)]}

    def _power(self, now):
        energy = guard(self._rapl, None)
        if energy is None:
            return None
        w = self._rates["rapl"].update(energy, now)
        return round(w / 1e6, 1) if w is not None else None

    def _freq(self):
        text = self._read("/proc/cpuinfo")
        if not text:
            return None
        mhz = []
        for line in text.splitlines():
            if line.startswith("cpu MHz"):
                try:
                    mhz.append(float(line.split(":")[1]))
                except (IndexError, ValueError):
                    pass
        return round(sum(mhz) / len(mhz)) if mhz else None

    def _net(self, now):
        text = self._read("/proc/net/dev")
        if not text:
            return None, None
        rx, tx = kernel.net_sum(kernel.net_dev(text), guard(self._ifaces, set()))
        return self._rates["rx"].update(rx, now), self._rates["tx"].update(tx, now)

    def _disk(self, now):
        text = self._read("/proc/diskstats")
        if not text:
            return None, None, {}
        per, rd, wr = {}, None, None
        for name, (r_bytes, w_bytes) in kernel.diskstats(text, guard(self._disks, set())).items():
            r = self._rates["r:" + name].update(r_bytes, now)
            w = self._rates["w:" + name].update(w_bytes, now)
            per[name] = {"read": r, "write": w}
            if r is not None:
                rd = (rd or 0.0) + r
            if w is not None:
                wr = (wr or 0.0) + w
        return rd, wr, per

    def _mem(self):
        text = self._read("/proc/meminfo")
        if not text:
            return {}
        mem = kernel.memory(kernel.meminfo(text))
        psi = self._read("/proc/pressure/memory")
        mem["pressure"] = kernel.pressure(psi) if psi else None
        return mem

    def _loadavg(self):
        text = self._read("/proc/loadavg")
        try:
            return [float(v) for v in text.split()[:3]] if text else None
        except ValueError:
            return None

    def _uptime(self):
        text = self._read("/proc/uptime")
        try:
            return int(float(text.split()[0])) if text else None
        except (ValueError, IndexError):
            return None

    def _record(self, cpu, gpus, net, disk, mem):
        add = self._history.add
        if cpu["usage"] is not None:
            add("cpuUser", cpu["user"])
            add("cpuSystem", cpu["system"])
        for key, name in (("temp", "cpuTemp"), ("power", "cpuPower")):
            if cpu[key] is not None:
                add(name, cpu[key])
        if gpus:
            for key, name in (("usage", "gpuUsage"), ("memPct", "gpuMemory"), ("temp", "gpuTemp"), ("power", "gpuPower")):
                if gpus[0].get(key) is not None:
                    add(name, gpus[0][key])
        if net[0] is not None:
            add("netDown", round(net[0]))
            add("netUp", round(net[1]))
        if disk[0] is not None:
            add("diskRead", round(disk[0]))
            add("diskWrite", round(disk[1] or 0))
        if mem:
            add("memUsed", mem["usedPct"])
            if mem.get("pressure") is not None:
                add("memPressure", mem["pressure"])
            if mem["swapTotal"]:
                add("swapUsed", round(100.0 * mem["swapUsed"] / mem["swapTotal"], 1))
