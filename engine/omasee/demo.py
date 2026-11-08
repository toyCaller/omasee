"""Deliberately awkward fake data for UI work: pegged values, long names, tiny and huge numbers."""
import collections
import math
import random
import time

GIB = 1024 ** 3
HISTORY = 120

CURVES = {
    "cpuUser": (30, 35), "cpuSystem": (8, 12), "cpuTemp": (55, 35), "cpuPower": (20, 60),
    "gpuUsage": (10, 90), "gpuMemory": (60, 30), "gpuTemp": (50, 35), "gpuPower": (40, 200),
    "netDown": (0, 90e6), "netUp": (0, 4e6), "diskRead": (0, 180e6), "diskWrite": (0, 60e6),
    "memUsed": (55, 30), "memPressure": (0, 40), "swapUsed": (10, 20),
}


class Wave:
    """Smooth breathing baseline with occasional bursts; looks like a real machine."""

    def __init__(self, seed):
        self._rng = random.Random(seed)
        self._phase = self._rng.random() * math.tau
        self._burst = 0.0

    def next(self):
        self._phase += 0.17
        if self._rng.random() < 0.07:
            self._burst = max(self._burst, self._rng.uniform(0.3, 1.0))
        v = 0.25 + 0.15 * math.sin(self._phase) + self._burst + self._rng.uniform(-0.03, 0.03)
        self._burst *= 0.55
        return max(0.0, min(1.0, v))


class Pulse:
    def __init__(self):
        self._seq = 0
        self._main = Wave(0)
        self._curves = {}
        for seed, (name, (lo, span)) in enumerate(CURVES.items(), start=1):
            w = Wave(seed)
            values = collections.deque((round(lo + span * w.next(), 1) for _ in range(HISTORY)), maxlen=HISTORY)
            self._curves[name] = (w, lo, span, values)

    def sample(self, detail):
        self._seq += 1
        lv = self._main.next()
        for w, lo, span, values in self._curves.values():
            values.append(round(lo + span * w.next(), 1))
        cur = {k: v[3][-1] for k, v in self._curves.items()}
        cpu = {"user": cur["cpuUser"], "system": cur["cpuSystem"], "usage": round(min(100, cur["cpuUser"] + cur["cpuSystem"]), 1),
               "temp": cur["cpuTemp"], "power": cur["cpuPower"]}
        gpu = {"name": "NVIDIA GeForce RTX 3090", "usage": round(cur["gpuUsage"]), "memPct": cur["gpuMemory"],
               "temp": round(cur["gpuTemp"]), "power": cur["gpuPower"]}
        msg = {"seq": self._seq, "t": time.time(), "detail": detail, "cpu": cpu, "gpu": [gpu],
               "net": {"down": cur["netDown"], "up": cur["netUp"]}, "mem": {"usedPct": cur["memUsed"]}}
        if not detail:
            return msg
        cpu.update(freq=4895, load=[3.12, 2.4, 1.89], uptime=32 * 86400 + 8 * 3600, model="AMD Ryzen 9 7950X 16-Core Processor",
                   cores=[round(100 * max(0, min(1, lv + 0.5 * math.sin(i + self._seq / 3))), 1) for i in range(32)],
                   threads=[[i, i + 16] for i in range(16)])
        gpu.update(vendor="nvidia", asleep=False, memUsed=23.4 * GIB, memTotal=24 * GIB, powerLimit=350, clock=1995,
                   clockMax=2100, memClock=9751, fan=72, pstate=0,
                   engines={"graphics": gpu["usage"], "encode": 64, "decode": 22, "jpeg": 0, "opticalFlow": 3},
                   processes=[
                       {"name": "a-really-long-process-name-that-should-truncate-cleanly", "type": "C+G", "usage": 88,
                        "memory": 18 * GIB, "encode": 64, "decode": 0, "count": 3},
                       {"name": "python3", "type": "C", "usage": 12, "memory": 3.2 * GIB, "encode": 0, "decode": 22, "count": 1},
                       {"name": "Hyprland", "type": "G", "usage": 4, "memory": 512 * 1024 ** 2, "encode": 0, "decode": 0, "count": 1},
                   ])
        rows = [("a-really-long-process-name-that-should-truncate-cleanly", 42.5, 41 * GIB, 180e6, 90e6),
                ("chromium", 11.2, 18 * GIB, 2e6, 4e6), ("ghostty", 3.1, 900 * 1024 ** 2, 12e3, 1e3),
                ("Hyprland", 1.4, 400 * 1024 ** 2, 0.0, 0.0), ("kworker/u64:3", 0.2, 0, 0.0, 512.0)]
        table = [{"name": n, "cpu": c, "memory": m, "read": r, "write": w, "io": r + w, "count": 1} for n, c, m, r, w in rows]
        msg["processes"] = {"cpu": table, "memory": table, "disk": table, "total": 412}
        msg["gpuPassthrough"] = [{"name": "RTX A1000", "driver": "vfio-pci"}]
        msg["net"]["interfaces"] = [{"name": "enp5s0", "kind": "ethernet", "ip": "192.0.2.18", "speed": 2500},
                                    {"name": "wlp8s0", "kind": "wifi", "ip": "192.0.2.69", "speed": None}]
        msg["mem"] = {"total": 125 * GIB, "used": 112 * GIB, "usedPct": cur["memUsed"], "apps": 88 * GIB, "cache": 14 * GIB,
                      "shared": 10 * GIB, "free": 13 * GIB, "swapTotal": 125 * GIB, "swapUsed": 26 * GIB, "pressure": cur["memPressure"]}
        msg["disks"] = {
            "volumes": [
                {"device": "/dev/mapper/root", "mount": "/", "fs": "btrfs", "total": 929 * GIB, "free": 12 * GIB, "usedPct": 98.7},
                {"device": "/dev/nvme1n1p1", "mount": "/boot", "fs": "vfat", "total": 2 * GIB, "free": 1.7 * GIB, "usedPct": 13.0},
            ],
            "models": {"nvme1n1": "Sabrent Rocket 4.0 1TB", "sda": "ST5000LM000-2AN170"},
            "read": cur["diskRead"], "write": cur["diskWrite"],
            "perDisk": {"nvme1n1": {"read": cur["diskRead"], "write": cur["diskWrite"]}, "sda": {"read": 0.0, "write": 0.0}},
        }
        msg["sensors"] = {
            "temps": [{"name": "k10temp Tctl", "value": cpu["temp"]}, {"name": "k10temp Tccd1", "value": 79.0},
                      {"name": "nvme Composite", "value": 61.9}],
            "fans": [{"name": "asusec CPU", "rpm": 2840}, {"name": "asusec Water Pump", "rpm": 0}],
        }
        msg["history"] = {k: list(v[3]) for k, v in self._curves.items()}
        return msg
