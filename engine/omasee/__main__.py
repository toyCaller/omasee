import argparse
import asyncio
import ctypes
import json
import os
import signal
import sys
import time

from . import VERSION, demo, gpu, host, hub, pulse

PR_SET_PDEATHSIG = 1


def live_pulse():
    nvidia = gpu.Nvidia.open(names=host.process_name)
    drm = gpu.Drm.open(names=host.process_name, describe=host.pci_name, primary=nvidia is None)
    return pulse.Pulse(
        read=host.read_text, clock=time.monotonic, ifaces=host.physical_ifaces, disks=host.whole_disks,
        sensors=host.hwmon, gpu=gpu.chain(nvidia, drm), rapl=host.rapl_energy, topology=host.topology,
        passthrough=host.passthrough_gpus, processes=host.WarmTable(host.ProcessTable()), volumes=host.volumes,
        models=host.disk_models, links=host.links, cpu_model=host.cpu_model,
    )


def default_socket():
    base = os.environ.get("XDG_RUNTIME_DIR")
    return os.path.join(base, "omasee.sock") if base else None


def main():
    ap = argparse.ArgumentParser(prog="omasee-engine", description=f"OmaSee telemetry engine {VERSION}")
    ap.add_argument("--socket", default=default_socket())
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--demo", action="store_true", help="serve fake data for UI work")
    ap.add_argument("--once", action="store_true", help="print one detailed sample as JSON and exit")
    args = ap.parse_args()

    if args.once:
        src = demo.Pulse() if args.demo else live_pulse()
        src.sample(True)
        time.sleep(1)
        print(json.dumps(src.sample(True), indent=1, default=str))
        return 0

    if not args.socket:
        print("omasee: XDG_RUNTIME_DIR is not set; refusing to pick a shared location", file=sys.stderr)
        return 2

    # Exit with the shell, even if it dies without stopping us.
    try:
        ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except (OSError, AttributeError):
        pass
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    server = hub.Hub(args.socket, demo.Pulse() if args.demo else live_pulse(), args.interval)
    try:
        if not server.acquire():
            return 0  # another bar's engine already serves this socket
        asyncio.run(server.run())
    except hub.UnsafePath as exc:
        print(f"omasee: {exc}", file=sys.stderr)
        return 3
    except KeyboardInterrupt:
        pass
    finally:
        server.release()
    return 0


if __name__ == "__main__":
    sys.exit(main())
