"""Offline tests of the exact menu selector; never invoke the UI run handler."""
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).with_name("finish_host_original_ui.applescript")


class OriginalUISelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.compiled = Path(cls.directory.name) / "helper.scpt"
        subprocess.run(["osacompile", "-o", str(cls.compiled), str(SOURCE)],
                       check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def select(self, names, allowed, *, error=None):
        # Only call the pure handler on the compiled production script object.
        script = (f'set helper to load script POSIX file "{self.compiled}"\n'
                  f"return helper's exactIndex({names}, {allowed})")
        result = subprocess.run(["osascript", "-e", script],
                                capture_output=True, text=True, timeout=5)
        if error:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(error, result.stderr)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)
            return int(result.stdout.strip())

    def test_apple_system_menu_is_never_the_app_menu(self):
        self.assertEqual(self.select('{"Apple", "Aftelle", "File"}', '{"Aftelle"}'), 2)
        self.assertEqual(self.select('{"File", "Apple", "Aftelle"}', '{"Aftelle"}'), 3)

    def test_missing_or_duplicate_app_menu_fails(self):
        self.select('{"Apple", "OtherApp"}', '{"Aftelle"}', error="unavailable")
        self.select('{"Aftelle", "Aftelle"}', '{"Aftelle"}', error="Ambiguous")

    def test_exact_quit_localizations(self):
        for title in ("Quit Aftelle", "退出Aftelle", "退出 Aftelle"):
            with self.subTest(title=title):
                names = '{"退出登录用户", "Force Quit Aftelle", missing value, "' + title + '"}'
                self.assertEqual(self.select(names, '{"Quit Aftelle", "退出Aftelle", "退出 Aftelle"}'), 4)

    def test_logout_and_other_apps_are_rejected(self):
        self.select('{"退出登录用户", "Quit OtherApp", "Force Quit Aftelle"}',
                    '{"Quit Aftelle", "退出Aftelle", "退出 Aftelle"}', error="unavailable")

    def test_partial_names_and_case_changes_are_rejected(self):
        for title in ("Quit Aftelle and Close", "Quit AftelleHelper", "quit aftelle"):
            with self.subTest(title=title):
                self.select('{"' + title + '"}', '{"Quit Aftelle"}', error="unavailable")

    def test_ambiguous_quit_fails(self):
        self.select('{"Quit Aftelle", "退出Aftelle"}',
                    '{"Quit Aftelle", "退出Aftelle", "退出 Aftelle"}', error="Ambiguous")

    def test_pid_and_exact_menu_are_required_in_actual_ui_handler(self):
        text = SOURCE.read_text()
        self.assertEqual(text.count("first application process whose unix id is targetPID"), 3)
        self.assertIn('if name is not "Aftelle"', text)
        self.assertIn('set appMenuIndex to my exactIndex', text)
        self.assertIn('click menu item quitIndex of appMenu', text)
        self.assertIn('if not enabled of menu item quitIndex of appMenu', text)
        self.assertNotIn('menu bar item 1 of menu bar 1', text)
        self.assertNotIn('starts with "退出"', text)
        self.assertNotIn('starts with "Quit"', text)
        self.assertNotIn('keystroke', text)
        self.assertIn('JSON_EXPORT_CONFIRMED', text)
        self.assertIn('Export local evidence?', text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
