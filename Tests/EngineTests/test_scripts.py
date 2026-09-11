import os
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]


class EngineScripts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="decant-engine-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.checkout = self.root / "checkout"
        self.support = self.root / "support"
        self.bin = self.root / "brew/bin"
        self.bin.mkdir(parents=True)
        self.support.mkdir()
        self.env = dict(os.environ, DECANT_HOME=str(self.support),
                        HOMEBREW_PREFIX=str(self.root / "brew"))

    def executable(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\n" + text)
        path.chmod(0o755)

    def launcher(self, same_prefix=True, wine_exit=0):
        script = self.checkout / "scripts/decant-launch.sh"
        script.parent.mkdir(parents=True)
        shutil.copy(REPO / "scripts/decant-launch.sh", script)
        common = self.checkout / "engine/scripts/lib/common.sh"
        common.parent.mkdir(parents=True)
        shutil.copy(REPO / "engine/scripts/lib/common.sh", common)
        self.executable(self.checkout / "engine/scripts/launch-steam.sh",
                        'echo start >> "$DECANT_HOME/start"\n')
        wine = self.support / "engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine"
        self.executable(wine, 'printf "%s\\n" "$@" > "$DECANT_HOME/args"\n'
                        + f"exit {wine_exit}\n")
        steam = self.support / "bottles/steam11/drive_c/Program Files (x86)/Steam/steam.exe"
        steam.parent.mkdir(parents=True)
        steam.touch()
        self.executable(self.bin / "arch", 'shift\nexec "$@"\n')
        self.executable(self.bin / "pgrep", "echo 101\n")
        suffix = "" if same_prefix else " other"
        self.executable(self.bin / "ps", 'printf "%s\\n" "steam.exe WINEPREFIX=$WINEPREFIX'
                        + suffix + ' USER=test"\n')
        return script

    def run_launcher(self, script, *args):
        return subprocess.run(["/bin/bash", str(script), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_existing_session_is_preserved(self):
        script = self.launcher()
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.support / "start").exists())
        self.assertIn("-applaunch\n123\n", (self.support / "args").read_text())

    def test_prefix_with_same_start_is_not_accepted(self):
        script = self.launcher(same_prefix=False)
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "start").read_text(), "start\n")

    def test_request_failure_is_nonzero(self):
        script = self.launcher(wine_exit=9)
        result = self.run_launcher(script, "play", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("request failed", result.stderr)

    def test_invalid_id_never_reaches_wine(self):
        script = self.launcher()
        result = self.run_launcher(script, "play", "123;echo unsafe")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.support / "args").exists())

    def test_deployment_retains_launcher_on_repeat(self):
        engine = self.checkout / "engine"
        engine.mkdir(parents=True)
        source = self.checkout / "scripts/decant-launch.sh"
        self.executable(source, "echo current\n")
        deploy = self.support / "engine"
        deploy.mkdir()
        self.executable(deploy / "decant-launch.sh", "echo old\n")
        (engine / "recipe").write_text("recipe")
        installer = (REPO / "engine/install.sh").read_text()
        start = installer.index('DEPLOY="$DECANT_HOME/engine"')
        end = installer.index('log_ok "Recipe deployed"', start)
        body = 'log_step() { :; }; die() { echo "$*" >&2; exit 1; };\n' + installer[start:end]
        for _ in range(2):
            result = subprocess.run(["bash", "-e", "-c", body], cwd=engine,
                                    env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((deploy / "decant-launch.sh").read_text(), source.read_text())
            self.assertTrue(os.access(deploy / "decant-launch.sh", os.X_OK))

    def test_all_shell_syntax(self):
        files = list((REPO / "engine").rglob("*.sh")) + list((REPO / "scripts").glob("*.sh"))
        for path in files:
            with self.subTest(path=path):
                result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_installer_signature_and_optional_hash(self):
        installer = self.root / "SteamSetup.exe"
        data = bytearray(128)
        data[:2] = b"MZ"
        data[60:64] = (64).to_bytes(4, "little")
        verify = ["python3", str(REPO / "engine/scripts/lib/verify-pe.py"), str(installer)]
        installer.write_bytes(data)
        self.assertNotEqual(subprocess.run(verify, capture_output=True).returncode, 0)
        data[64:68] = b"PE\0\0"
        installer.write_bytes(data)
        env = dict(self.env, DECANT_STEAMSETUP_SHA256=hashlib.sha256(data).hexdigest())
        self.assertEqual(subprocess.run(verify, env=env, capture_output=True).returncode, 0)
        env["DECANT_STEAMSETUP_SHA256"] = "0" * 64
        self.assertNotEqual(subprocess.run(verify, env=env, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
