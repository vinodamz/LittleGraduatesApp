#!/usr/bin/env python3
"""Record the unmodified app. Only UI actions, connectivity and read-only evidence."""
import argparse
import hashlib
import json
import re
import sqlite3
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "in.thelittlegraduates.app"
ACTIVITY = PACKAGE + "/in.thelittlegraduates.little_graduates.MainActivity"
TITLE = "Uploading material checks"
SERVICE = "androidx.work.impl.foreground.SystemForegroundService"
BASE = "http://127.0.0.1:8765"


class UiNotReady(RuntimeError):
    """The active window has not exposed a fresh accessibility tree yet."""


def bounds(node):
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if not match:
        return None
    left, top, right, bottom = map(int, match.groups())
    return (left, top, right, bottom) if right > left and bottom > top else None


def select(root, pattern, *, package=None):
    """Use accessibility text/description; taps always derive from observed bounds."""
    found = []
    for node in root.iter("node"):
        if not bounds(node) or node.get("enabled") == "false":
            continue
        if package and not re.search(package, node.get("package", "")):
            continue
        if any(re.search(pattern, node.get(key, ""), re.I) for key in ("text", "content-desc")):
            found.append(node)
    # Flutter merges a label with supporting text. Prefer its actionable node.
    return sorted(found, key=lambda n: (n.get("clickable") != "true", bounds(n)[1], bounds(n)[0]))


def picker_photo(root):
    picker = r"photopicker|providers\.media|documentsui"
    names = select(root, r"demo-material\.png|^Photo taken|^Photo,", package=picker)
    if names:
        return names[0]
    for node in root.iter("node"):
        if (bounds(node) and re.search(picker, node.get("package", ""))
                and re.search(r":id/(icon_thumbnail|image_thumbnail|thumbnail)$", node.get("resource-id", ""))):
            return node
    return None


def foreground_evidence(services, notifications):
    # Require the WorkManager service itself, not another service in this app.
    blocks = re.split(r"(?=\* ServiceRecord\{)", services)
    service_ok = any(SERVICE in b and "isForeground=true" in b
                     and "foregroundId=71041" in b
                     and any(int(value, 16) & 1 for value in re.findall(r"\b(?:types|foregroundServiceType)=0x([0-9a-fA-F]+)", b))
                     for b in blocks)
    notification_ok = any(PACKAGE in line and re.search(r"\bid=71041\b", line)
                          for line in notifications.splitlines() if "NotificationRecord" in line)
    return service_ok and notification_ok


class Demo:
    def __init__(self, runtime, output):
        self.runtime, self.output = runtime, output
        self.output.mkdir(parents=True, exist_ok=True)
        self.fixture = json.loads((runtime / "fixture.json").read_text())
        if self.fixture.get("demo_only") is not True:
            raise RuntimeError("Refusing a non-demo fixture")
        self.events = []
        self.started = time.monotonic()
        self.recording = None
        self.record_started = None
        self.recorder_log = None
        self.token = None
        self.photo_hash = None
        self.photo_selected = False
        self.sequence = 0

    def event(self, message, **details):
        record = {"seconds": round(time.monotonic() - self.started, 2), "event": message, **details}
        self.events.append(record)
        print(json.dumps(record), flush=True)
        (self.output / "events.json").write_text(json.dumps(self.events, indent=2) + "\n")

    def adb(self, *args, binary=False, check=True, timeout=20):
        result = subprocess.run(["adb", *args], capture_output=True, timeout=timeout, check=check)
        return result.stdout if binary else result.stdout.decode(errors="replace")

    def shell(self, *args, **kwargs):
        return self.adb("shell", *args, **kwargs)

    def tree(self):
        # A cold Flutter launch can have no active accessibility root yet.
        # Remove our previous dump so a retry can never accept stale nodes.
        self.shell("rm", "-f", "/sdcard/lg-window.xml")
        result = subprocess.run(
            ["adb", "shell", "uiautomator", "dump", "--compressed", "/sdcard/lg-window.xml"],
            capture_output=True, text=True, timeout=20)
        diagnostic = (result.stdout + result.stderr).strip()
        with (self.output / "uiautomator.log").open("a") as log:
            log.write(f"exit={result.returncode} {diagnostic}\n")
        xml = self.shell("cat", "/sdcard/lg-window.xml", check=False)
        if result.returncode != 0 or not xml.strip():
            raise UiNotReady("No fresh UI tree: " + diagnostic)
        (self.output / "latest-ui.xml").write_text(xml)
        return ET.fromstring(xml)

    def checkpoint(self, name, root=None):
        self.sequence += 1
        prefix = self.output / f"{self.sequence:02}-{name}"
        prefix.with_suffix(".png").write_bytes(self.adb("exec-out", "screencap", "-p", binary=True))
        ET.ElementTree(root if root is not None else self.tree()).write(prefix.with_suffix(".xml"), encoding="unicode")
        self.event(name)

    def tap(self, node):
        rect = bounds(node)
        if rect is None:
            raise RuntimeError("Cannot tap a node without visible bounds")
        left, top, right, bottom = rect
        self.event("tap", label=node.get("text") or node.get("content-desc"), bounds=rect)
        self.shell("input", "tap", str((left + right) // 2), str((top + bottom) // 2))
        time.sleep(.4)

    def allow_notification(self, root):
        buttons = select(root, r"^Allow$", package=r"permissioncontroller")
        if buttons:
            self.tap(buttons[0])
            return True
        return False

    def wait(self, description, fn, timeout=30):
        end = time.monotonic() + timeout
        last = None
        while time.monotonic() < end:
            if self.record_started and time.monotonic() - self.record_started > 170:
                raise RuntimeError("Recording approached Android's 180-second limit")
            try:
                value = fn()
                if value is not None and value is not False:
                    return value
            except (UiNotReady, ET.ParseError, sqlite3.Error) as error:
                last = str(error)
            time.sleep(.7)
        raise RuntimeError(f"Timed out: {description}; {last or 'required evidence absent'}")

    def label(self, pattern, timeout=30):
        def probe():
            root = self.tree()
            if self.allow_notification(root):
                return None
            return next(iter(select(root, pattern)), None)
        return self.wait("UI " + pattern, probe, timeout)

    def tap_label(self, pattern, timeout=30):
        self.tap(self.label(pattern, timeout))

    def scroll_to(self, pattern):
        for _ in range(5):
            root = self.tree()
            if self.allow_notification(root):
                continue
            hits = select(root, pattern)
            if hits:
                return hits[0]
            areas = [n for n in root.iter("node") if n.get("scrollable") == "true" and bounds(n)]
            if not areas:
                raise RuntimeError("No semantic scroll region for " + pattern)
            left, top, right, bottom = max((bounds(n) for n in areas), key=lambda b: (b[2]-b[0])*(b[3]-b[1]))
            self.shell("input", "swipe", str((left+right)//2), str(top+(bottom-top)*4//5),
                       str((left+right)//2), str(top+(bottom-top)//5), "450")
        raise RuntimeError("Could not reveal " + pattern)

    def queue(self):
        # Copy only this synthetic user's database into a temporary directory.
        # Never mutate the device DB or publish meta rows (which hold tokens).
        name = f"materials_outbox_{int(self.fixture['user']['id'])}.db"
        listing = self.shell("run-as", PACKAGE, "ls", "databases").split()
        if name not in listing:
            return []
        with tempfile.TemporaryDirectory() as folder:
            for suffix in ("", "-wal", "-shm"):
                if name + suffix in listing:
                    Path(folder, name + suffix).write_bytes(self.adb(
                        "exec-out", "run-as", PACKAGE, "cat", "databases/" + name + suffix, binary=True))
            with sqlite3.connect(f"file:{folder}/{name}?mode=ro", uri=True) as db:
                db.row_factory = sqlite3.Row
                rows = [dict(row) for row in db.execute(
                    "SELECT id,kind,material_id,status,attempts,error_code,upload_path FROM outbox ORDER BY id")]
        return rows

    def api(self, path, body=None):
        headers = {"Accept": "application/json", "User-Agent": "LittleGraduates-Synthetic-Demo"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        payload = None if body is None else json.dumps(body).encode()
        if payload is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(BASE + "/api/v1/" + path, data=payload, headers=headers)
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.load(response)
        if data.get("ok") is not True:
            raise RuntimeError("Demo backend refused " + path)
        return data

    def start_recording(self):
        self.recorder_log = (self.output / "screenrecord.log").open("wb")
        self.recording = subprocess.Popen(
            ["adb", "shell", "screenrecord", "--bit-rate", "4000000", "--time-limit", "180", "/sdcard/lg-demo.mp4"],
            stdout=self.recorder_log, stderr=subprocess.STDOUT)
        self.record_started = time.monotonic()
        time.sleep(2)
        if self.recording.poll() is not None:
            raise RuntimeError("Android screenrecord exited before capture")
        self.event("recording-started")

    def stop_recording(self):
        if self.recording is None:
            return
        for pid in self.shell("pidof", "screenrecord", check=False).split():
            if pid.isdigit():
                self.shell("kill", "-2", pid)
        self.recording.wait(timeout=20)
        self.recorder_log.close()
        self.adb("pull", "/sdcard/lg-demo.mp4", str(self.output / "demo.mp4"))
        self.recording = None
        self.record_started = None

    def record(self):
        self.adb("logcat", "-c")
        self.shell("input", "keyevent", "KEYCODE_WAKEUP")
        self.shell("wm", "dismiss-keyguard")
        self.shell("settings", "put", "system", "screen_off_timeout", "600000")
        self.shell("svc", "power", "stayon", "true")
        self.shell("mkdir", "-p", "/sdcard/Pictures/LGDemo")
        self.adb("push", str(self.runtime / "demo-material.png"), "/sdcard/Pictures/LGDemo/demo-material.png")
        self.shell("am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE", "-d",
                   "file:///sdcard/Pictures/LGDemo/demo-material.png")
        self.shell("am", "start", "-n", ACTIVITY)
        self.label(re.escape(self.fixture["user"]["name"]), timeout=45)
        self.tap(self.scroll_to(re.escape(self.fixture["user"]["name"])))
        for digit in str(self.fixture["user"]["pin"]):
            self.tap_label("^" + digit + "$")
        if len(str(self.fixture["user"]["pin"])) < 6:
            self.tap_label(r"^OK$")
        self.tap_label(r"^School(?:\n|$)")
        self.tap(self.scroll_to(r"^Materials(?:\n|$)"))
        self.label(re.escape(self.fixture["materials"][0]["name"]))
        self.tap(self.scroll_to(r"^Condition$"))
        self.tap_label(r"^Good$")
        # Permit the real runtime notification request before backgrounding.
        self.wait("condition saved and permission handled", self.condition_ready)
        self.tap(self.scroll_to(r"^Choose from gallery$"))
        # Close the sheet; start the continuous clip before the actual selection.
        self.shell("input", "keyevent", "KEYCODE_BACK")
        self.checkpoint("materials-ready")
        self.start_recording()
        self.shell("cmd", "connectivity", "airplane-mode", "enable")
        self.shell("svc", "wifi", "disable")
        self.shell("svc", "data", "disable")
        self.wait("emulator route offline", lambda: self.no_route(), timeout=15)
        self.event("radios-offline")
        self.tap(self.scroll_to(r"^Choose from gallery$"))
        self.tap_label(r"^Photos$")
        self.wait("real system photo picker", self.choose_photo, timeout=30)
        self.wait("photo queued after failed foreground attempt", self.queued_photo, timeout=25)
        self.checkpoint("photo-saved-offline")
        self.shell("input", "keyevent", "KEYCODE_HOME")
        time.sleep(2)
        self.shell("am", "kill", "--user", "0", PACKAGE)
        self.wait("background UI process ended", lambda: not self.shell("pidof", PACKAGE, check=False).strip(), timeout=10)
        self.event("background-ui-process-ended-no-force-stop")
        self.shell("cmd", "connectivity", "airplane-mode", "disable")
        # Keep one route while the cold worker starts; simultaneous cellular
        # and Wi-Fi reconnection can change the default network mid-upload.
        self.shell("svc", "data", "disable")
        self.shell("svc", "wifi", "enable")
        self.event("connectivity-restored-wifi-only")
        self.shell("cmd", "statusbar", "expand-notifications")
        self.wait("actual WorkManager service and visible notification", self.upload_visible, timeout=75)
        self.checkpoint("actual-datasync-notification")
        time.sleep(6)
        self.verify_upload()
        self.shell("cmd", "statusbar", "collapse")
        self.shell("am", "start", "-n", ACTIVITY)
        # A cold start returns to the app shell; reach the same materials screen.
        self.tap_label(r"^School(?:\n|$)")
        self.tap(self.scroll_to(r"^Materials(?:\n|$)"))
        self.label(re.escape(self.fixture["materials"][0]["name"]))
        self.wait("outbox has no unfinished media", lambda: not [r for r in self.queue() if r["kind"] == "media" and r["status"] != "uploaded"])
        self.checkpoint("uploaded-material-reloaded")
        time.sleep(3)
        self.stop_recording()
        probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type,width,height",
                                "-of", "json", str(self.output / "demo.mp4")], capture_output=True, check=True, text=True)
        metadata = json.loads(probe.stdout)
        if float(metadata["format"]["duration"]) < 10 or not any(s["codec_type"] == "video" for s in metadata["streams"]):
            raise RuntimeError("Recording did not contain a usable video stream")
        (self.output / "video.json").write_text(probe.stdout)
        self.event("verified-recording-complete", duration=metadata["format"]["duration"])

    def condition_ready(self):
        root = self.tree()
        if self.allow_notification(root):
            return False
        rows = self.queue()
        return bool(select(root, r"^Good$")) and not any(r["status"] != "uploaded" for r in rows)

    def no_route(self):
        result = subprocess.run(["adb", "shell", "ip", "route", "get", "10.0.2.2"], capture_output=True, text=True, timeout=10)
        return result.returncode != 0 and "unreachable" in (result.stdout + result.stderr).lower()

    def choose_photo(self):
        root = self.tree()
        if select(root, r"^Choose from gallery$", package=re.escape(PACKAGE)):
            return True
        photo = picker_photo(root)
        if photo is not None and not self.photo_selected:
            self.checkpoint("real-system-picker", root)
            self.tap(photo)
            self.photo_selected = True
            time.sleep(1)
            root = self.tree()
        buttons = select(root, r"^(?:Add(?: \(\d+\)| \d+(?: photos?)?)?|Done|Open|Select)$", package=r"photopicker|providers\.media|documentsui")
        if buttons:
            self.tap(buttons[0])
        return False

    def queued_photo(self):
        rows = self.queue()
        media = [r for r in rows if r["kind"] == "media" and r["status"] in ("pending", "ready") and r["attempts"] >= 1]
        if not media:
            return False
        item = media[0]
        if not item["upload_path"]:
            return False
        content = self.adb("exec-out", "run-as", PACKAGE, "cat", item["upload_path"], binary=True)
        self.photo_hash = hashlib.sha256(content).hexdigest()
        (self.output / "offline-queue.json").write_text(json.dumps(rows, indent=2))
        self.event("queued-real-photo", bytes=len(content), sha256=self.photo_hash)
        return True

    def upload_visible(self):
        services = self.shell("dumpsys", "activity", "services", PACKAGE)
        notifications = self.shell("dumpsys", "notification", "--noredact")
        (self.output / "latest-foreground-services.txt").write_text(services)
        (self.output / "latest-notifications.txt").write_text(notifications)
        if not foreground_evidence(services, notifications):
            return False
        activities = self.shell("dumpsys", "activity", "activities")
        if any(PACKAGE in line for line in activities.splitlines() if "mResumedActivity" in line or "topResumedActivity" in line):
            raise RuntimeError("App activity resumed while claiming background evidence")
        root = self.tree()
        if not select(root, re.escape(TITLE), package=r"com\.android\.systemui"):
            return False
        for name, value in (("foreground-services.txt", services), ("notifications.txt", notifications), ("activities-background.txt", activities)):
            (self.output / name).write_text(value)
        self.event("actual-foreground-service-visible", service=SERVICE, notification_id=71041)
        return True

    def verify_upload(self):
        login = self.api("login.php", {"user_id": self.fixture["user"]["id"], "pin": self.fixture["user"]["pin"], "device_name": "Synthetic demo readback"})
        self.token = login["token"]
        def readback():
            day = self.api("materials/today.php")["day"]
            item = next(m for m in day["materials"] if m["id"] == self.fixture["materials"][0]["id"])
            return item if item["media"] else None
        item = self.wait("MTT persisted uploaded photo", readback, timeout=40)
        media = item["media"][0]
        url = urllib.parse.urlsplit(urllib.parse.urljoin(BASE + "/", media["url"]))
        if url.hostname not in ("127.0.0.1", "10.0.2.2") or url.port != 8765:
            raise RuntimeError("Refusing non-fixture media URL")
        request = urllib.request.Request(urllib.parse.urlunsplit(("http", "127.0.0.1:8765", url.path, url.query, "")),
                                         headers={"Authorization": "Bearer " + self.token})
        with urllib.request.urlopen(request, timeout=10) as reply:
            uploaded = reply.read()
        digest = hashlib.sha256(uploaded).hexdigest()
        if digest != self.photo_hash:
            raise RuntimeError("Uploaded photo does not match app's queued upload bytes")
        (self.output / "upload-readback.json").write_text(json.dumps({"material_id": item["id"], "media_id": media["id"],
                                                                    "bytes": len(uploaded), "sha256": digest}, indent=2))
        self.event("server-image-readback-matches", bytes=len(uploaded), sha256=digest)

    def finish(self, failure):
        try:
            if failure:
                self.checkpoint("failure")
        except Exception as error:
            self.event("failure-screenshot-unavailable", reason=str(error))
        try:
            self.stop_recording()
        except Exception as error:
            self.event("recording-finalize-error", reason=str(error))
        for name, args in (("logcat.txt", ("logcat", "-d", "-v", "threadtime")),
                           ("jobs.txt", ("shell", "dumpsys", "jobscheduler")),
                           ("device.txt", ("shell", "getprop"))):
            try:
                (self.output / name).write_text(self.adb(*args))
            except Exception as error:
                self.event("diagnostic-unavailable", name=name, reason=str(error))
        status = "FAILED — do not submit as declaration evidence" if failure else "PASSED — real emulator capture; visual review still required"
        summary = (f"# Android DataSync demonstration\n\n{status}\n\n"
                   "Actual unmodified Flutter debug app, API 35 x86_64 emulator, synthetic MTT records in isolated MariaDB. "
                   "No notification injection, video overlays, playback substitution or queue mutation. "
                   "Radio-off selection, Home, background process termination (not force-stop), reconnect, actual WorkManager upload. "
                   "The fixture delays the real media request by 30 seconds. Video is Android screenrecord output, unedited and silent.\n\n"
                   f"Backend revision: `{self.fixture['mtt_commit']}`. See runner.txt for app revision.\n\n")
        if failure:
            summary += f"Failure: {failure}\n\nAny partial demo.mp4 is diagnostic only.\n"
        else:
            summary += "Verified: visible system notification 71041, active WorkManager foreground service while the app activity was backgrounded, server image SHA-256 matching queued bytes, and successful app reload.\n"
        summary += "\nThis does not establish Play approval or release-signed/device parity. Review demo.mp4 before publishing it.\n"
        (self.output / "summary.md").write_text(summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    demo = Demo(args.runtime, args.output)
    failure = None
    try:
        demo.record()
    except Exception as error:
        failure = f"{type(error).__name__}: {error}"
        demo.event("failed", reason=failure)
    finally:
        demo.finish(failure)
    if failure:
        raise SystemExit(failure)


if __name__ == "__main__":
    main()
