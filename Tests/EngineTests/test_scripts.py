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

    def launcher(self, same_prefix=True, wine_exit=0, store_version=None):
        script = self.checkout / "scripts/decant-launch.sh"
        script.parent.mkdir(parents=True)
        shutil.copy(REPO / "scripts/decant-launch.sh", script)
        common = self.checkout / "engine/scripts/lib/common.sh"
        common.parent.mkdir(parents=True)
        shutil.copy(REPO / "engine/scripts/lib/common.sh", common)
        self.executable(self.checkout / "engine/scripts/launch-steam.sh",
                        'echo start >> "$DECANT_HOME/start"\n')
        if store_version:
            app = self.support / f"engines/versions/{store_version}/Wine Stable.app"
            app.mkdir(parents=True)
            link = self.support / "engines/current"
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(f"versions/{store_version}")
        else:
            app = self.support / "engines/wine11/Wine Stable.app"
        wine = app / "Contents/Resources/wine/bin/wine"
        self.executable(wine, 'printf "%s\\n" "$@" > "$DECANT_HOME/args"\n'
                        + f'echo "$0" > "$DECANT_HOME/which-wine"\n'
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

    def test_launcher_uses_the_active_store_version(self):
        # common.sh resolves engines/current before the old engines/wine11.
        script = self.launcher(store_version="v-1")
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("engines/current", (self.support / "which-wine").read_text())

    def test_explicit_wine_bin_overrides_the_lookup(self):
        # decant passes the engine it selected, so the script never picks one.
        script = self.launcher(store_version="v-1")
        other = self.support / "engines/versions/v-2/Wine Stable.app/Contents/Resources/wine/bin/wine"
        self.executable(other, 'printf "%s\\n" "$@" > "$DECANT_HOME/args"\n'
                        'echo "$0" > "$DECANT_HOME/which-wine"\n')
        self.env["WINE_BIN"] = str(other)
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("v-2", (self.support / "which-wine").read_text())

    def test_launch_id_reaches_the_log(self):
        script = self.launcher()
        self.env["DECANT_LAUNCH_ID"] = "id-7"
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = (self.support / "logs/decant-launch.log").read_text()
        self.assertIn("launch_id=id-7", log)

    def store(self, body):
        # run one engine store snippet against a temporary store root.
        script = ("source %s\nsource %s\n" % (
            REPO / "engine/scripts/lib/common.sh",
            REPO / "engine/scripts/lib/engine-store.sh")) + body
        return subprocess.run(["/bin/bash", "-c", script], env=self.env,
                              capture_output=True, text=True, timeout=30)

    def test_store_refuses_a_different_version_under_the_same_id(self):
        result = self.store('''
        mkdir -p "$ENGINE_STORE_ROOT/versions/v-1/bin"
        printf 'first\n' > "$ENGINE_STORE_ROOT/versions/v-1/bin/wine"
        engine_store_write_manifest "$ENGINE_STORE_ROOT/versions/v-1" v-1 wine-11.0 c v0.74 d
        engine_store_activate v-1
        mkdir -p "$ENGINE_STORE_ROOT/versions/v-1.partial/bin"
        printf 'second\n' > "$ENGINE_STORE_ROOT/versions/v-1.partial/bin/wine"
        engine_store_write_manifest "$ENGINE_STORE_ROOT/versions/v-1.partial" v-1 wine-11.0 c v0.74 d
        engine_store_promote v-1 && exit 1
        grep -q first "$ENGINE_STORE_ROOT/versions/v-1/bin/wine" || exit 1
        [ ! -e "$ENGINE_STORE_ROOT/versions/v-1.partial" ] || exit 1
        [ "$(basename "$(readlink "$ENGINE_STORE_ROOT/current")")" = v-1 ] || exit 1
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("different contents", result.stderr)

    def test_store_reuses_a_matching_version(self):
        result = self.store('''
        mkdir -p "$ENGINE_STORE_ROOT/versions/v-1/bin"
        printf 'same\n' > "$ENGINE_STORE_ROOT/versions/v-1/bin/wine"
        engine_store_write_manifest "$ENGINE_STORE_ROOT/versions/v-1" v-1 wine-11.0 c v0.74 d
        mkdir -p "$ENGINE_STORE_ROOT/versions/v-1.partial/bin"
        printf 'same\n' > "$ENGINE_STORE_ROOT/versions/v-1.partial/bin/wine"
        engine_store_write_manifest "$ENGINE_STORE_ROOT/versions/v-1.partial" v-1 wine-11.0 c v0.74 d
        engine_store_promote v-1 || exit 1
        [ "$(basename "$(readlink "$ENGINE_STORE_ROOT/current")")" = v-1 ] || exit 1
        [ ! -e "$ENGINE_STORE_ROOT/versions/v-1.partial" ] || exit 1
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_store_activate_is_repeatable(self):
        result = self.store('''
        mkdir -p "$ENGINE_STORE_ROOT/versions/v-1/bin"
        printf 'one\n' > "$ENGINE_STORE_ROOT/versions/v-1/bin/wine"
        engine_store_write_manifest "$ENGINE_STORE_ROOT/versions/v-1" v-1 wine-11.0 c v0.74 d
        engine_store_activate v-1
        engine_store_activate v-1
        [ "$(basename "$(readlink "$ENGINE_STORE_ROOT/current")")" = v-1 ] || exit 1
        [ ! -e "$ENGINE_STORE_ROOT/previous" ] || exit 1
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
