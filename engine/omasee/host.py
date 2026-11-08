"""Readers for /proc and /sys that need more than one file. Nothing here spawns a process."""
import fcntl
import functools
import os
import pathlib
import socket
import struct
import time

from . import kernel

READ_LIMIT = 1 << 20  # No single kernel file we read is anywhere near 1 MiB.
SIOCGIFADDR = 0x8915
PCI_IDS = ("/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids")


def read_text(path, limit=READ_LIMIT):
    try:
        with open(path, "rb") as handle:
            return handle.read(limit).decode("utf-8", "replace")
    except OSError:
        return None


def read_int(path):
    text = read_text(path, 64)
    try:
        return int(text.strip()) if text is not None else None
    except ValueError:
        return None


# ---------------------------------------------------------------- network

def physical_ifaces(root="/sys/class/net"):
    base = pathlib.Path(root)
    return {p.name for p in base.iterdir() if (p / "device").exists()} if base.is_dir() else set()


def _ipv4(name):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            raw = fcntl.ioctl(sock.fileno(), SIOCGIFADDR, struct.pack("256s", name[:15].encode()))
        except OSError:
            return None
    return socket.inet_ntoa(raw[20:24])


def links(root="/sys/class/net"):
    out = []
    for name in sorted(physical_ifaces(root)):
        path = pathlib.Path(root) / name
        if (read_text(path / "operstate", 32) or "").strip() != "up":
            continue
        speed = read_int(path / "speed")
        out.append({
            "name": kernel.clean_name(name),
            "kind": "wifi" if (path / "wireless").exists() or (path / "phy80211").exists() else "ethernet",
            "ip": _ipv4(name),
            "speed": speed if speed and speed > 0 else None,
        })
    return out


# ---------------------------------------------------------------- storage

def whole_disks(root="/sys/block"):
    base = pathlib.Path(root)
    return {p.name for p in base.iterdir() if (p / "device").exists()} if base.is_dir() else set()


def disk_models(root="/sys/block"):
    out = {}
    for name in whole_disks(root):
        model = read_text(pathlib.Path(root) / name / "device/model", 256)
        out[name] = kernel.clean_name(model.strip()) if model and model.strip() else name
    return out


def volumes(read=read_text):
    out = []
    for vol in kernel.mounts(read("/proc/mounts") or ""):
        try:
            st = os.statvfs(vol["mount"])
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        if not total:
            continue
        used = total - st.f_bfree * st.f_frsize
        out.append({**vol, "mount": kernel.clean_name(vol["mount"]), "total": total,
                    "free": st.f_bavail * st.f_frsize, "usedPct": round(100.0 * used / total, 1)})
    return out


# ---------------------------------------------------------------- power, sensors, topology

def rapl_energy(path="/sys/class/powercap/intel-rapl:0/energy_uj"):
    # Root-only on most kernels since PLATYPUS; then CPU power is simply unknown.
    return read_int(path)


def hwmon(root="/sys/class/hwmon"):
    temps, fans = [], []
    base = pathlib.Path(root)
    if not base.is_dir():
        return {"temps": temps, "fans": fans}
    for chip_dir in sorted(base.iterdir()):
        chip = (read_text(chip_dir / "name", 64) or chip_dir.name).strip()
        for kind, pattern, scale, bucket in (("temp", "temp*_input", 1000, temps), ("fan", "fan*_input", 1, fans)):
            for entry in sorted(chip_dir.glob(pattern)):
                value = read_int(entry)
                if value is None:
                    continue
                label = read_text(entry.with_name(entry.name.replace("_input", "_label")), 64)
                name = kernel.clean_name(f"{chip} {label.strip()}" if label and label.strip() else chip)
                if kind == "temp":
                    if -50000 < value < 200000:  # discard disconnected-probe garbage
                        bucket.append({"name": name, "value": round(value / scale, 1)})
                else:
                    bucket.append({"name": name, "rpm": value})
    return {"temps": temps, "fans": fans}


CPU_SENSORS = ("k10temp Tctl", "zenpower Tdie", "zenpower Tctl", "coretemp Package", "cpu_thermal", "acpitz")


def cpu_temp(temps):
    for wanted in CPU_SENSORS:
        for t in temps:
            if t["name"].startswith(wanted):
                return t["value"]
    return None


def siblings(core_map):
    """core_map: cpu -> (package, core). Returns sibling-thread lists, one per physical core."""
    groups = {}
    for cpu in sorted(core_map):
        groups.setdefault(core_map[cpu], []).append(cpu)
    return [groups[k] for k in sorted(groups)]


def topology(root="/sys/devices/system/cpu"):
    core_map = {}
    for path in pathlib.Path(root).glob("cpu[0-9]*"):
        pkg = read_int(path / "topology/physical_package_id")
        core = read_int(path / "topology/core_id")
        if pkg is not None and core is not None:
            core_map[int(path.name[3:])] = (pkg, core)
    return siblings(core_map)


def cpu_model(read=read_text):
    for line in (read("/proc/cpuinfo") or "").splitlines():
        if line.startswith("model name"):
            return kernel.clean_name(line.split(":", 1)[1].strip())
    return None


# ---------------------------------------------------------------- PCI names, without lspci

@functools.lru_cache(maxsize=1)
def _pci_table():
    for path in PCI_IDS:
        text = read_text(path, 8 << 20)
        if text:
            return text
    return ""


@functools.lru_cache(maxsize=32)
def pci_name(address, root="/sys/bus/pci/devices"):
    dev = pathlib.Path(root) / address
    vendor = (read_text(dev / "vendor", 16) or "").strip().lower().replace("0x", "")
    device = (read_text(dev / "device", 16) or "").strip().lower().replace("0x", "")
    if not vendor or not device:
        return address
    in_vendor = False
    for line in _pci_table().splitlines():
        if not line or line.startswith("#"):
            continue
        if not line.startswith("\t"):
            if in_vendor:
                break
            in_vendor = line[:4].lower() == vendor
        elif in_vendor and not line.startswith("\t\t") and line[1:5].lower() == device:
            name = line[5:].strip()
            if "[" in name and name.endswith("]"):
                name = name[name.rindex("[") + 1:-1]
            return kernel.clean_name(name)
    return address


def passthrough_gpus(root="/sys/bus/pci/devices", describe=pci_name):
    out = []
    base = pathlib.Path(root)
    if not base.is_dir():
        return out
    for dev in sorted(base.iterdir()):
        cls = read_text(dev / "class", 16)
        if not cls or not cls.startswith("0x03"):
            continue
        driver = dev / "driver"
        if driver.exists() and driver.resolve().name == "vfio-pci":
            out.append({"name": describe(dev.name), "driver": "vfio-pci"})
    return out


# ---------------------------------------------------------------- processes

def _exe(pid):
    try:
        return os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return None


def _pids():
    return [int(n) for n in os.listdir("/proc") if n.isdigit()]


def process_name(pid):
    comm = (read_text(f"/proc/{pid}/comm", 64) or str(pid)).strip()
    return kernel.app_name(_exe(pid), comm)


class ProcessTable:
    """Per-app CPU, private memory and disk rates. Names come from exe/comm, never cmdline."""

    LIMIT = 12

    def __init__(self, pids=_pids, read=read_text, exe=_exe, hz=None, page=None, cpus=None):
        self._pids, self._read, self._exe = pids, read, exe
        self._hz = hz or os.sysconf("SC_CLK_TCK")
        self._page = page or os.sysconf("SC_PAGE_SIZE")
        self._cpus = cpus or os.cpu_count() or 1
        self._prev, self._when, self._names = {}, None, {}

    def _name(self, pid, start, comm):
        key = (pid, start)
        if key not in self._names:
            self._names[key] = kernel.app_name(self._exe(pid), comm)
        return self._names[key]

    def _io(self, pid):
        text = self._read(f"/proc/{pid}/io", 4096)
        if not text:
            return None
        vals = dict(line.split(": ", 1) for line in text.splitlines() if ": " in line)
        try:
            return int(vals.get("read_bytes", 0)), int(vals.get("write_bytes", 0))
        except ValueError:
            return None

    def sample(self, now):
        span = now - self._when if self._when is not None else 0
        seen, rows = {}, []
        for pid in self._pids():
            stat_text = self._read(f"/proc/{pid}/stat", 4096)
            statm_text = self._read(f"/proc/{pid}/statm", 256)
            if not stat_text or not statm_text:
                continue
            try:
                st = kernel.pid_stat(stat_text)
                resident, shared = (int(v) for v in statm_text.split()[1:3])
            except (ValueError, IndexError):
                continue
            io = self._io(pid)
            seen[pid] = (st["start"], st["ticks"], io)
            row = {"name": self._name(pid, st["start"], st["comm"]), "cpu": 0.0,
                   "memory": max(0, resident - shared) * self._page, "read": 0.0, "write": 0.0}
            prev = self._prev.get(pid)
            if prev and prev[0] == st["start"] and span > 0:
                row["cpu"] = round(100.0 * (st["ticks"] - prev[1]) / self._hz / span / self._cpus, 2)
                if io and prev[2]:
                    row["read"] = max(0.0, (io[0] - prev[2][0]) / span)
                    row["write"] = max(0.0, (io[1] - prev[2][1]) / span)
            row["io"] = row["read"] + row["write"]
            rows.append(row)
        self._prev, self._when = seen, now
        alive = {(pid, v[0]) for pid, v in seen.items()}
        self._names = {k: v for k, v in self._names.items() if k in alive}
        return {
            "cpu": kernel.rollup(rows, "cpu", self.LIMIT),
            "memory": kernel.rollup(rows, "memory", self.LIMIT),
            "disk": kernel.rollup(rows, "io", self.LIMIT),
            "total": len(rows),
        }


class WarmTable:
    """A cold table has no deltas, so take a quick baseline rather than show a list of zeros."""

    BASELINE = 0.25
    STALE = 10.0

    def __init__(self, table, clock=time.monotonic, sleep=time.sleep):
        self._table, self._clock, self._sleep, self._last = table, clock, sleep, None

    def __call__(self):
        now = self._clock()
        if self._last is None or now - self._last > self.STALE:
            self._table.sample(now)
            self._sleep(self.BASELINE)
            now = self._clock()
        self._last = now
        return self._table.sample(now)
