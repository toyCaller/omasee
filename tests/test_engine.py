"""Run with:  python3 -I tests/test_engine.py   (from the plugin folder)"""
import asyncio
import json
import os
import pathlib
import socket
import stat
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "engine"))
from omasee import demo, gpu, host, hub, kernel  # noqa: E402

STAT = "cpu  100 0 50 800 50 0 0 0\ncpu0 50 0 25 400 25 0 0 0\ncpu1 50 0 25 400 25 0 0 0\nintr 1\n"
STAT2 = "cpu  200 0 100 1600 100 0 0 0\ncpu0 100 0 50 800 50 0 0 0\ncpu1 100 0 50 800 50 0 0 0\n"


class Parsers(unittest.TestCase):
    def test_cpu_share(self):
        a, b = kernel.cpu_stat(STAT), kernel.cpu_stat(STAT2)
        share = kernel.cpu_share(a["total"], b["total"])
        self.assertAlmostEqual(share["usage"], 15.0)
        self.assertEqual(sorted(b["cores"]), [0, 1])

    def test_cpu_share_never_negative(self):
        a, b = kernel.cpu_stat(STAT2), kernel.cpu_stat(STAT)
        self.assertEqual(kernel.cpu_share(a["total"], b["total"])["usage"], 0.0)

    def test_memory(self):
        info = kernel.meminfo("MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 600 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n")
        m = kernel.memory(info)
        self.assertEqual(m["usedPct"], 40.0)

    def test_mounts_folds_subvolumes_and_unescapes(self):
        text = ("/dev/a / btrfs rw 0 0\n/dev/a /home btrfs rw 0 0\nproc /proc proc rw 0 0\n"
                "/dev/b /mnt/my\\040disk ext4 rw 0 0\n")
        vols = kernel.mounts(text)
        self.assertEqual([v["mount"] for v in vols], ["/", "/mnt/my disk"])

    def test_names_are_sanitised(self):
        self.assertEqual(kernel.clean_name("evil\x1b[31mred\n"), "evil[31mred")
        self.assertLessEqual(len(kernel.clean_name("x" * 500)), kernel.NAME_LIMIT)

    def test_app_name_prefers_comm_for_launchers(self):
        self.assertEqual(kernel.app_name("/usr/bin/python3.14", "myscript"), "myscript")
        self.assertEqual(kernel.app_name("/usr/lib/chromium/chromium", "ThreadPool"), "chromium")

    def test_fdinfo(self):
        text = "drm-pdev:\t0000:03:00.0\ndrm-client-id:\t7\ndrm-engine-gfx:\t1000 ns\ndrm-total-vram:\t2 MiB\ndrm-memory-vram:\t9 MiB\n"
        p = gpu.fdinfo(text)
        self.assertEqual(p["memory"], 2 * 1024 * 1024)
        self.assertEqual(p["engines"]["gfx"]["ns"], 1000)
        self.assertIsNone(gpu.fdinfo("pos: 0\n"))

    def test_hwmon_rejects_garbage(self):
        with tempfile.TemporaryDirectory() as d:
            chip = pathlib.Path(d, "hwmon0")
            chip.mkdir()
            (chip / "name").write_text("coretemp\n")
            (chip / "temp1_input").write_text("-273000\n")
            (chip / "temp2_input").write_text("45000\n")
            out = host.hwmon(d)
        self.assertEqual([t["value"] for t in out["temps"]], [45.0])


class HubSecurity(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        os.chmod(self.dir, 0o700)
        self.path = os.path.join(self.dir, "s.sock")

    def test_rejects_shared_directory(self):
        os.chmod(self.dir, 0o755)
        with self.assertRaises(hub.UnsafePath):
            hub.Hub(self.path, demo.Pulse()).acquire()

    def test_refuses_symlinked_lock(self):
        os.symlink("/etc/passwd", self.path + ".lock")
        with self.assertRaises(hub.UnsafePath):
            hub.Hub(self.path, demo.Pulse()).acquire()

    def test_single_instance(self):
        a, b = hub.Hub(self.path, demo.Pulse()), hub.Hub(self.path, demo.Pulse())
        self.assertTrue(a.acquire())
        self.assertFalse(b.acquire())
        a.release()

    def test_will_not_unlink_foreign_file(self):
        pathlib.Path(self.path).write_text("not a socket")
        h = hub.Hub(self.path, demo.Pulse())
        self.assertTrue(h.acquire())
        with self.assertRaises(hub.UnsafePath):
            h._bind()
        h.release()

    def test_serves_private_socket_and_detail_on_request(self):
        h = hub.Hub(self.path, demo.Pulse(), interval=0.5)
        self.assertTrue(h.acquire())

        async def scenario():
            task = asyncio.create_task(h.run())
            for _ in range(50):
                if os.path.exists(self.path):
                    break
                await asyncio.sleep(0.02)
            self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o600)
            reader, writer = await asyncio.open_unix_connection(self.path)
            bar = json.loads(await reader.readline())
            self.assertFalse(bar["detail"])
            writer.write(b"x" * 5000 + b"\n")  # oversize junk is ignored or drops us, never crashes the hub
            await writer.drain()
            reader2, writer2 = await asyncio.open_unix_connection(self.path)
            writer2.write(b"detail on\n")
            await writer2.drain()
            for _ in range(5):
                msg = json.loads(await reader2.readline())
                if msg["detail"]:
                    break
            self.assertTrue(msg["detail"])
            self.assertIn("history", msg)
            writer.close()
            writer2.close()
            task.cancel()

        asyncio.run(scenario())
        h.release()


class Demo(unittest.TestCase):
    def test_demo_round_trips_as_json(self):
        p = demo.Pulse()
        json.dumps(p.sample(True), allow_nan=False)
        self.assertNotIn("history", hub.slim(p.sample(True)))


if __name__ == "__main__":
    unittest.main(verbosity=1)
