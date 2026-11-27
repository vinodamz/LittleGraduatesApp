"""Host-side tests for evidence gates; these are not emulator/video evidence."""
import tempfile
import subprocess
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

from driver import Demo, PACKAGE, SERVICE, UiNotReady, bounds, foreground_evidence, picker_photo, select


def tree(nodes):
    root = ET.Element("hierarchy")
    for values in nodes:
        ET.SubElement(root, "node", {"bounds": "[10,20][110,120]", "enabled": "true", **values})
    return root


class DriverTests(unittest.TestCase):
    def test_selector_uses_semantics_and_excludes_hidden_disabled_nodes(self):
        root = tree([
            {"text": "Good", "enabled": "false"},
            {"text": "Good", "bounds": "[0,0][0,0]"},
            {"content-desc": "Good", "clickable": "true"},
        ])
        result = select(root, "^Good$")
        self.assertEqual(len(result), 1)
        self.assertEqual(bounds(result[0]), (10, 20, 110, 120))

    def test_selector_requires_systemui_for_notification(self):
        root = tree([{"text": "Uploading material checks", "package": PACKAGE}])
        self.assertEqual(select(root, "Uploading material checks", package=r"com\.android\.systemui"), [])

    def test_picker_rejects_app_image(self):
        root = tree([{"text": "demo-material.png", "package": PACKAGE}])
        self.assertIsNone(picker_photo(root))

    def test_picker_selects_real_file_or_system_thumbnail(self):
        for fields in ({"text": "demo-material.png"}, {"resource-id": "com.google.android.providers.media.module:id/icon_thumbnail"}):
            root = tree([{**fields, "package": "com.google.android.providers.media.module"}])
            self.assertIsNotNone(picker_photo(root))

    def test_evidence_requires_active_datasync_service_and_app_notification(self):
        services = (f"* ServiceRecord{{abc {PACKAGE}/{SERVICE}}}\n"
                    "isForeground=true foregroundId=71041 types=0x00000001\n")
        notifications = f"NotificationRecord(abc pkg={PACKAGE} id=71041 tag=null)"
        self.assertTrue(foreground_evidence(services, notifications))
        self.assertFalse(foreground_evidence(services.replace("true", "false"), notifications))
        self.assertFalse(foreground_evidence(services.replace("0x00000001", "0x00000008"), notifications))
        self.assertFalse(foreground_evidence(services, notifications.replace(PACKAGE, "another.app")))
        self.assertFalse(foreground_evidence(services, notifications.replace("71041", "999")))

    def test_cannot_combine_unrelated_service_fields(self):
        services = (f"* ServiceRecord{{abc {PACKAGE}/{SERVICE}}}\nisForeground=false\n"
                    "* ServiceRecord{def other/service}\nisForeground=true foregroundId=71041 foregroundServiceType=0x1")
        self.assertFalse(foreground_evidence(services, f"NotificationRecord(pkg={PACKAGE} id=71041)"))

    def test_wait_accepts_leaf_xml_node(self):
        demo = Demo.__new__(Demo)
        demo.record_started = None
        node = tree([{"text": "6"}])[0]
        self.assertIs(demo.wait("leaf node", lambda: node, timeout=1), node)

    def test_cold_start_retries_missing_root_and_preserves_stderr(self):
        demo = Demo.__new__(Demo)
        demo.record_started = None
        xml = '<hierarchy><node text="Demo Materials Teacher" /></hierarchy>'
        with tempfile.TemporaryDirectory() as folder:
            demo.output = Path(folder)
            with patch.object(demo, "shell", side_effect=["", "", "", xml]) as shell, \
                    patch("driver.subprocess.run", side_effect=[
                        subprocess.CompletedProcess([], 0, "", "ERROR: null root node returned by UiTestAutomationBridge"),
                        subprocess.CompletedProcess([], 0, "", "UI hierarchy dumped to: /sdcard/lg-window.xml")]), \
                    patch("driver.time.sleep"):
                result = demo.wait("cold launch", demo.tree, timeout=1)
            self.assertEqual(result[0].get("text"), "Demo Materials Teacher")
            self.assertEqual(sum(call.args[:2] == ("rm", "-f") for call in shell.call_args_list), 2)
            self.assertIn("null root node", (demo.output / "uiautomator.log").read_text())

    def test_failed_dump_cannot_be_used_for_taps(self):
        demo = Demo.__new__(Demo)
        with tempfile.TemporaryDirectory() as folder:
            demo.output = Path(folder)
            with patch.object(demo, "shell", side_effect=["", ""]), \
                    patch("driver.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "", "ERROR: no root")):
                with self.assertRaises(UiNotReady):
                    demo.tree()

    def test_checkpoint_writes_real_capture_and_xml(self):
        demo = Demo.__new__(Demo)
        demo.sequence = 0
        root = tree([{"text": "Materials"}])
        with tempfile.TemporaryDirectory() as folder:
            demo.output = Path(folder)
            with patch.object(demo, "adb", return_value=b"test capture bytes"), patch.object(demo, "event"):
                demo.checkpoint("test", root)
            self.assertEqual((demo.output / "01-test.png").read_bytes(), b"test capture bytes")
            self.assertEqual(ET.parse(demo.output / "01-test.xml").getroot()[0].get("text"), "Materials")

    def test_tap_uses_observed_bounds(self):
        demo = Demo.__new__(Demo)
        with patch.object(demo, "shell") as shell, patch.object(demo, "event"), patch("driver.time.sleep"):
            demo.tap(tree([{"text": "Photos", "bounds": "[100,300][400,500]"}])[0])
        shell.assert_called_once_with("input", "tap", "250", "400")


if __name__ == "__main__":
    unittest.main()
