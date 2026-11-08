"""Single-instance Unix socket hub shared by every monitor's bar.

Hardening:
  * the socket's directory must be a private (0700, owned by us) directory;
  * the lock file is opened with O_NOFOLLOW, so a planted symlink can't redirect it;
  * a stale path is only removed if it is a socket we own;
  * the socket is created 0600 and every peer's UID is checked with SO_PEERCRED;
  * commands are a fixed whitelist, lines are length-capped, clients are capped,
    and a client that stops reading is dropped instead of growing our memory.
"""
import asyncio
import fcntl
import json
import os
import socket
import stat
import struct

MAX_CLIENTS = 16
MAX_LINE = 256
MAX_BACKLOG = 4 << 20
COMMANDS = {"detail on", "detail off", "ping"}
BAR_KEYS = ("seq", "t", "detail", "cpu", "net", "mem")
CPU_BAR = ("usage", "user", "system", "temp", "power")
GPU_BAR = ("name", "usage", "memPct", "temp", "power")


class UnsafePath(Exception):
    pass


def private_dir(path):
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid() and (st.st_mode & 0o077) == 0


def slim(message):
    """The bar-only view of a detailed message, for clients without a report open."""
    out = {k: message[k] for k in BAR_KEYS if k in message}
    out["detail"] = False
    out["cpu"] = {k: message["cpu"].get(k) for k in CPU_BAR}
    out["gpu"] = [{k: g.get(k) for k in GPU_BAR} for g in message.get("gpu", [])[:1]]
    out["net"] = {"down": message["net"].get("down"), "up": message["net"].get("up")}
    out["mem"] = {"usedPct": (message.get("mem") or {}).get("usedPct")}
    return out


def encode(message):
    return (json.dumps(message, separators=(",", ":"), allow_nan=False, default=str) + "\n").encode()


class Hub:
    def __init__(self, path, pulse, interval=2.0):
        self._path = os.path.abspath(path)
        self._pulse = pulse
        self._interval = max(0.5, min(10.0, float(interval)))
        self._lock_fd = None
        self._clients = {}
        self._wake = None

    # ---------------------------------------------------------------- lifetime

    def acquire(self):
        """True when this process becomes the engine; False when another one already is."""
        if not private_dir(os.path.dirname(self._path)):
            raise UnsafePath(f"{os.path.dirname(self._path)} is not a private directory")
        flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC
        try:
            fd = os.open(self._path + ".lock", flags, 0o600)
        except OSError as exc:
            raise UnsafePath(f"cannot open lock safely: {exc}") from exc
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return False
        self._lock_fd = fd
        return True

    def release(self):
        if self._lock_fd is not None:
            os.close(self._lock_fd)
            self._lock_fd = None

    def _bind(self):
        try:
            st = os.lstat(self._path)
        except FileNotFoundError:
            st = None
        if st is not None:
            if not stat.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid():
                raise UnsafePath(f"{self._path} exists and is not our socket")
            os.unlink(self._path)  # stale: we hold the lock, so nobody else serves it
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        old = os.umask(0o177)
        try:
            sock.bind(self._path)
        finally:
            os.umask(old)
        os.chmod(self._path, 0o600)
        sock.listen(MAX_CLIENTS)
        sock.setblocking(False)
        return sock

    # ---------------------------------------------------------------- clients

    @staticmethod
    def _peer_uid(writer):
        sock = writer.get_extra_info("socket")
        if sock is None:
            return None
        raw = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        return struct.unpack("3i", raw)[1]

    async def _serve(self, reader, writer):
        if len(self._clients) >= MAX_CLIENTS or self._peer_uid(writer) != os.getuid():
            writer.close()
            return
        self._clients[writer] = False
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                cmd = line.decode("ascii", "ignore").strip()
                if cmd not in COMMANDS:
                    continue
                if cmd == "ping":
                    continue
                self._clients[writer] = cmd == "detail on"
                if self._clients[writer]:
                    self._wake.set()
        except (OSError, ValueError, asyncio.LimitOverrunError, asyncio.IncompleteReadError):
            pass
        finally:
            self._clients.pop(writer, None)
            writer.close()

    def _send(self, message):
        full = encode(message)
        bar = encode(slim(message)) if message.get("detail") else full
        for writer, wants_detail in list(self._clients.items()):
            transport = writer.transport
            if transport.is_closing() or transport.get_write_buffer_size() > MAX_BACKLOG:
                self._clients.pop(writer, None)
                writer.close()
                continue
            try:
                writer.write(full if wants_detail else bar)
            except OSError:
                self._clients.pop(writer, None)

    async def run(self):
        self._wake = asyncio.Event()
        server = await asyncio.start_unix_server(self._serve, sock=self._bind(), limit=MAX_LINE)
        loop = asyncio.get_running_loop()
        async with server:
            while True:
                detail = any(self._clients.values())
                message = await loop.run_in_executor(None, self._pulse.sample, detail)
                self._send(message)
                self._wake.clear()
                try:
                    await asyncio.wait_for(self._wake.wait(), self._interval)
                except (TimeoutError, asyncio.TimeoutError):
                    pass
