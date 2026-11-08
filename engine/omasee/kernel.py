"""Pure parsers for kernel text interfaces (/proc). No I/O, so tests can feed strings."""
from collections import namedtuple

Ticks = namedtuple("Ticks", "user system idle total")

PSEUDO_FS = frozenset({
    "proc", "sysfs", "tmpfs", "devtmpfs", "devpts", "cgroup", "cgroup2", "pstore", "bpf", "tracefs",
    "debugfs", "securityfs", "configfs", "fusectl", "mqueue", "hugetlbfs", "autofs", "ramfs", "efivarfs",
    "binfmt_misc", "nsfs", "overlay", "squashfs", "rpc_pipefs", "fuse.portal", "fuse.gvfsd-fuse",
})
# Interpreters and launchers: the process name says more than the executable.
LAUNCHERS = frozenset({"electron", "python", "python3", "node", "bash", "sh", "zsh", "java", "wine", "wine64", "ruby", "perl"})
NAME_LIMIT = 64


def clean_name(text):
    """Printable, bounded process/device name. Control characters never reach the UI."""
    text = "".join(ch for ch in str(text) if ch.isprintable())
    return (text[:NAME_LIMIT - 1] + "…") if len(text) > NAME_LIMIT else text


def _ticks(fields):
    v = [int(x) for x in fields[:8]] + [0] * max(0, 8 - len(fields[:8]))
    user, nice, system, idle, iowait, irq, softirq, steal = v
    busy_user, busy_sys = user + nice, system + irq + softirq + steal
    return Ticks(busy_user, busy_sys, idle + iowait, busy_user + busy_sys + idle + iowait)


def cpu_stat(text):
    total, cores = None, {}
    for line in text.splitlines():
        if not line.startswith("cpu"):
            break
        name, *fields = line.split()
        if name == "cpu":
            total = _ticks(fields)
        elif name[3:].isdigit():
            cores[int(name[3:])] = _ticks(fields)
    return {"total": total, "cores": cores}


def cpu_share(before, after):
    span = after.total - before.total
    if span <= 0:
        return {"user": 0.0, "system": 0.0, "usage": 0.0}
    user = max(0.0, 100.0 * (after.user - before.user) / span)
    system = max(0.0, 100.0 * (after.system - before.system) / span)
    return {"user": round(user, 1), "system": round(system, 1), "usage": round(min(100.0, user + system), 1)}


def meminfo(text):
    out = {}
    for line in text.splitlines():
        key, _, rest = line.partition(":")
        parts = rest.split()
        if parts and parts[0].isdigit():
            out[key] = int(parts[0]) * 1024
    return out


def memory(info):
    total = info.get("MemTotal", 0)
    free = info.get("MemFree", 0)
    avail = info.get("MemAvailable", free)
    shared = info.get("Shmem", 0)
    cache = max(0, info.get("Buffers", 0) + info.get("Cached", 0) + info.get("SReclaimable", 0) - shared)
    apps = max(0, total - free - cache - shared)
    used = max(0, total - avail)
    swap_total = info.get("SwapTotal", 0)
    return {
        "total": total, "used": used, "usedPct": round(100.0 * used / total, 1) if total else 0.0,
        "apps": apps, "cache": cache, "shared": shared, "free": free,
        "swapTotal": swap_total, "swapUsed": max(0, swap_total - info.get("SwapFree", 0)),
    }


def pressure(text):
    for line in text.splitlines():
        if line.startswith("some"):
            for token in line.split():
                if token.startswith("avg10="):
                    try:
                        return float(token[6:])
                    except ValueError:
                        return None
    return None


def net_dev(text):
    out = {}
    for line in text.splitlines()[2:]:
        name, _, rest = line.partition(":")
        f = rest.split()
        if len(f) >= 9:
            out[name.strip()] = (int(f[0]), int(f[8]))
    return out


def net_sum(counters, physical):
    picked = [v for k, v in counters.items() if k in physical]
    return sum(v[0] for v in picked), sum(v[1] for v in picked)


def diskstats(text, disks):
    out = {}
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 10 and f[2] in disks:
            out[f[2]] = (int(f[5]) * 512, int(f[9]) * 512)
    return out


def _unoctal(path):
    return path.replace("\\040", " ").replace("\\011", "\t").replace("\\012", "\n").replace("\\134", "\\")


def mounts(text):
    """One entry per block device; bind mounts and btrfs subvolumes fold onto the shortest path."""
    by_dev = {}
    for line in text.splitlines():
        f = line.split()
        if len(f) < 3 or f[2] in PSEUDO_FS or not f[0].startswith("/"):
            continue
        dev, where, fs = f[0], _unoctal(f[1]), f[2]
        seen = by_dev.get(dev)
        if seen is None or len(where) < len(seen["mount"]):
            by_dev[dev] = {"device": dev, "mount": where, "fs": fs}
    return sorted(by_dev.values(), key=lambda v: v["mount"])


def pid_stat(line):
    lp, rp = line.index("("), line.rindex(")")
    f = line[rp + 2:].split()
    return {"pid": int(line[:lp]), "comm": line[lp + 1:rp], "ticks": int(f[11]) + int(f[12]), "start": int(f[19])}


def app_name(exe, comm):
    if exe:
        base = exe.replace(" (deleted)", "").rsplit("/", 1)[-1]
        if base and base not in LAUNCHERS and base.split(".")[0] not in LAUNCHERS:
            return clean_name(base)
    return clean_name(comm)


def rollup(rows, key, limit):
    """Merge rows by name (a browser's 40 helpers become one line with a count)."""
    groups = {}
    for row in rows:
        g = groups.setdefault(row["name"], {"name": row["name"], "count": 0})
        g["count"] += 1
        for k, v in row.items():
            if k != "name" and isinstance(v, (int, float)):
                g[k] = g.get(k, 0) + v
    return sorted(groups.values(), key=lambda g: g.get(key, 0), reverse=True)[:limit]
