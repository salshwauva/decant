import os
import hashlib
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[2]

# steam's connection and console log lines, as far as the launcher reads them.
# the account id must never reach the launcher's output.
SIGN_IN = (
    "[{t}] [Logging On, 4, 7] [U:1:424242] RecvMsgClientLogOnResponse() : [U:1:424242] 'OK'\n"
    "[{t}] [Logged On, 4, 7] [U:1:424242] RecvMsgClientLogOnResponse() : processing complete\n"
)
CONNECTING = "[2026-09-28 20:06:40] [Connecting, 4, 0] [U:1:424242] PingWebSocketCM() starting...\n"
WATCH_SPAWN = '( bash "$0" watch "$1" >>"$LOG" 2>&1 </dev/null & )'
GAME_LINE = ('[{t}] Game process added : AppID {app} '
             '""C:\\Program Files (x86)\\Steam\\steamapps\\common\\Game\\Game.exe"", ProcID 896, IP 0.0.0.0:0\n')


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

    def launcher(self, same_prefix=True, wine_exit=0, last_state="Logged On",
                 sign_in="start", game_app="123", rotate=False, watch_spawn=":"):
        """checkout with fake wine, steam and logs.

        last_state: how the connection log ends before the run.
        sign_in: when the fake steam signs in: "start" (as launch-steam.sh
          runs), "late" (on the third sleep), or "never".
        game_app: app id of the game line the forwarder makes steam log, or
          None for no line.
        rotate: the late sign-in replaces the connection log instead of
          appending to it.
        watch_spawn: what play runs where the real script starts the exit
          watch in the background. nothing by default, so no test leaves a
          watcher polling behind it.
        """
        script = self.checkout / "scripts/decant-launch.sh"
        script.parent.mkdir(parents=True)
        text = (REPO / "scripts/decant-launch.sh").read_text()
        # short waits so the timeout cases finish quickly.
        short = text.replace("LOGON_WAIT=150", "LOGON_WAIT=6").replace("START_WAIT=60", "START_WAIT=6")
        self.assertNotEqual(short, text)
        self.assertIn(WATCH_SPAWN, short)
        short = short.replace(WATCH_SPAWN, watch_spawn)
        script.write_text(short)
        common = self.checkout / "engine/scripts/lib/common.sh"
        common.parent.mkdir(parents=True)
        shutil.copy(REPO / "engine/scripts/lib/common.sh", common)

        logs = self.support / "bottles/steam11/drive_c/Program Files (x86)/Steam/logs"
        logs.mkdir(parents=True)
        connection = shlex.quote(str(logs / "connection_log.txt"))
        console = shlex.quote(str(logs / "console_log.txt"))
        stale = SIGN_IN.format(t="2026-09-28 19:05:02")
        (logs / "connection_log.txt").write_text(
            stale * 3 + (CONNECTING if last_state == "Connecting" else ""))
        (logs / "console_log.txt").write_text(GAME_LINE.format(t="2026-09-28 19:06:00", app="123"))
        (self.support / "sign-in.txt").write_text(SIGN_IN.format(t="2026-09-28 20:06:51"))
        sign_in_cmd = f'cat "$DECANT_HOME/sign-in.txt" {">" if rotate else ">>"} {connection}\n'

        launch = 'echo start >> "$DECANT_HOME/start"\ntouch "$DECANT_HOME/steam-running"\n'
        if sign_in == "start":
            launch += sign_in_cmd
        self.executable(self.checkout / "engine/scripts/launch-steam.sh", launch)

        game = ""
        if game_app:
            (self.support / "game.txt").write_text(
                GAME_LINE.format(t="2026-09-28 20:07:00", app=game_app))
            game = f'cat "$DECANT_HOME/game.txt" >> {console}\n'
        wine = self.support / "engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wine"
        # reg-seq, when present, holds one RunningAppID per line, read one per
        # query; the last line repeats.
        self.executable(wine, 'if [ "$1" = reg ]; then\n'
                        '  f="$DECANT_HOME/reg-seq"; hex="${RUNNING_HEX:-0x0}"\n'
                        '  if [ -s "$f" ]; then\n'
                        '    hex=$(head -1 "$f")\n'
                        '    if [ "$(wc -l < "$f")" -gt 1 ]; then tail -n +2 "$f" > "$f.n"; mv "$f.n" "$f"; fi\n'
                        '  fi\n'
                        '  printf "    RunningAppID    REG_DWORD    %s\\r\\n" "$hex"; exit 0\n'
                        'fi\n'
                        'printf "%s\\n" "$@" > "$DECANT_HOME/args"\n'
                        'if [ "$2" = -shutdown ]; then rm -f "$DECANT_HOME/steam-running"; fi\n'
                        'cat "$DECANT_HOME/sleeps" > "$DECANT_HOME/sleeps-at-request" 2>/dev/null || true\n'
                        + game
                        + f"exit {wine_exit}\n")
        steam = self.support / "bottles/steam11/drive_c/Program Files (x86)/Steam/steam.exe"
        steam.touch()
        self.executable(self.bin / "arch", 'shift\nexec "$@"\n')
        # every sleep is counted and returns at once.
        late = sign_in_cmd if sign_in == "late" else ":\n"
        self.executable(self.bin / "sleep",
                        'n=$(cat "$DECANT_HOME/sleeps" 2>/dev/null || echo 0); n=$((n + 1))\n'
                        'echo "$n" > "$DECANT_HOME/sleeps"\n'
                        f'if [ "$n" = 3 ]; then\n{late}fi\n')
        # a play request in flight is a pgrep for decant-launch.sh; play-flights
        # holds how many more polls see one.
        self.executable(self.bin / "pgrep",
                        'case "$*" in\n'
                        '*decant-launch*)\n'
                        '  n=$(cat "$DECANT_HOME/play-flights" 2>/dev/null || echo 0)\n'
                        '  [ "$n" -gt 0 ] || exit 1\n'
                        '  echo $((n - 1)) > "$DECANT_HOME/play-flights"; echo 202 ;;\n'
                        '*) echo 101 ;;\n'
                        'esac\n')
        wineserver = self.support / "engines/wine11/Wine Stable.app/Contents/Resources/wine/bin/wineserver"
        self.executable(wineserver, 'echo "$@" >> "$DECANT_HOME/wineserver"\n')
        # steam's working directory names its prefix; ps shows no environment.
        if same_prefix:
            (self.support / "steam-running").touch()
        # the full listing (lsof -d cwd) shows the live pids named in
        # leftover-pids under the prefix and those in outside-pids elsewhere.
        self.executable(self.bin / "lsof",
                        'if [ "$1" = -d ]; then\n'
                        '  for pid in $(cat "$DECANT_HOME/leftover-pids" 2>/dev/null); do\n'
                        '    kill -0 "$pid" 2>/dev/null && printf "p%s\\nfcwd\\nn%s/drive_c/windows\\n" "$pid" "$WINEPREFIX"\n'
                        '  done\n'
                        '  for pid in $(cat "$DECANT_HOME/outside-pids" 2>/dev/null); do\n'
                        '    kill -0 "$pid" 2>/dev/null && printf "p%s\\nfcwd\\nn/elsewhere\\n" "$pid"\n'
                        '  done\n'
                        '  exit 0\n'
                        'fi\n'
                        'if [ -f "$DECANT_HOME/steam-running" ]; then\n'
                        'echo "n$WINEPREFIX/drive_c/Program Files (x86)/Steam"\n'
                        'else echo "n/elsewhere/drive_c/Program Files (x86)/Steam"; fi\n')
        return script

    def sleeps(self):
        counter = self.support / "sleeps"
        return int(counter.read_text()) if counter.exists() else 0

    def run_launcher(self, script, *args):
        return subprocess.run(["/bin/bash", str(script), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_existing_session_is_preserved(self):
        script = self.launcher()
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.support / "start").exists())
        self.assertIn("-applaunch\n123\n", (self.support / "args").read_text())
        # signed in already, and the game line is there at once: no waiting.
        self.assertEqual(self.sleeps(), 0)

    def test_cold_start_signs_in_before_the_request(self):
        script = self.launcher(same_prefix=False, sign_in="late")
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "start").read_text(), "start\n")
        self.assertIn("-applaunch\n123\n", (self.support / "args").read_text())
        # the stale sign-in in the log does not count; the request waits for
        # the third sleep, when the fake steam signs in.
        self.assertEqual((self.support / "sleeps-at-request").read_text().strip(), "3")

    def test_cold_start_that_never_signs_in_fails_without_a_request(self):
        script = self.launcher(same_prefix=False, sign_in="never")
        result = self.run_launcher(script, "play", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not sign in", result.stderr)
        self.assertFalse((self.support / "args").exists())

    def test_running_steam_that_is_still_signing_in_is_waited_for(self):
        script = self.launcher(last_state="Connecting", sign_in="late")
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.support / "start").exists())
        self.assertEqual((self.support / "sleeps-at-request").read_text().strip(), "3")

    def stop_steam_during_wait(self):
        sleep = self.bin / "sleep"
        sleep.write_text(sleep.read_text() +
                         'rm -f "$DECANT_HOME/steam-running"\n')

    def test_steam_that_dies_during_sign_in_is_restarted(self):
        script = self.launcher(last_state="Connecting")
        self.stop_steam_during_wait()
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "start").read_text(), "start\n")
        self.assertIn("-applaunch\n123\n", (self.support / "args").read_text())

    def test_steam_that_dies_again_fails_without_another_restart(self):
        script = self.launcher(last_state="Connecting", sign_in="never")
        self.stop_steam_during_wait()
        result = self.run_launcher(script, "play", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.support / "start").read_text(), "start\n")
        self.assertIn("steam exited again", result.stderr)
        self.assertLess(self.sleeps(), 6)
        self.assertFalse((self.support / "args").exists())

    def test_restart_does_not_accept_the_dead_sessions_sign_in(self):
        script = self.launcher(last_state="Connecting", sign_in="never")
        self.stop_steam_during_wait()
        sleep = self.bin / "sleep"
        connection = shlex.quote(str(self.support / "bottles/steam11/drive_c" /
                                    "Program Files (x86)/Steam/logs/connection_log.txt"))
        sleep.write_text(sleep.read_text() +
                         f'cat "$DECANT_HOME/sign-in.txt" >> {connection}\n')
        result = self.run_launcher(script, "play", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.support / "start").read_text(), "start\n")
        self.assertFalse((self.support / "args").exists())

    def test_rotated_connection_log_still_shows_the_sign_in(self):
        script = self.launcher(same_prefix=False, sign_in="late", rotate=True)
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "sleeps-at-request").read_text().strip(), "3")

    def test_prefix_with_same_start_is_not_accepted(self):
        script = self.launcher(same_prefix=False)
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "start").read_text(), "start\n")

    def test_running_game_blocks_second_launch(self):
        script = self.launcher()
        self.env["RUNNING_HEX"] = "0x1a"
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(result.stdout.strip(), "26")
        self.assertIn("already running", result.stderr)
        self.assertFalse((self.support / "start").exists())
        self.assertFalse((self.support / "args").exists())

    def helper_file(self):
        helper = self.checkout / "engine/helpers/dismiss-dialog/dismiss-dialog.exe"
        helper.parent.mkdir(parents=True)
        helper.touch()
        return helper

    def wait_for_args(self, needle):
        # the helper starts in the background, so its call lands after play returns.
        for _ in range(50):
            args = self.support / "args"
            if args.exists() and needle in args.read_text():
                return args.read_text()
            time.sleep(0.1)
        return (self.support / "args").read_text()

    def test_kynseed_launch_starts_the_dialog_helper(self):
        script = self.launcher(game_app="758870")
        helper = self.helper_file()
        result = self.run_launcher(script, "play", "758870")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.wait_for_args("dismiss-dialog.exe")
        self.assertEqual(args.split("\n")[:5],
                         [str(helper), "Microsoft .NET Framework", "Kynseed.exe", "Continue", "90"])

    def test_other_games_never_start_the_dialog_helper(self):
        script = self.launcher()
        self.helper_file()
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        time.sleep(0.5)
        self.assertIn("-applaunch\n123\n", (self.support / "args").read_text())

    def test_missing_dialog_helper_does_not_fail_the_launch(self):
        script = self.launcher(game_app="758870")
        result = self.run_launcher(script, "play", "758870")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dialog helper missing", result.stderr)
        self.assertIn("-applaunch\n758870\n", (self.support / "args").read_text())

    def install_game(self, app, folder, unity=False):
        steam = self.support / "bottles/steam11/drive_c/Program Files (x86)/Steam/steamapps"
        steam.mkdir(parents=True, exist_ok=True)
        (steam / f"appmanifest_{app}.acf").write_text(
            f'"AppState"\n{{\n\t"appid"\t\t"{app}"\n\t"installdir"\t\t"{folder}"\n}}\n')
        game = steam / "common" / folder
        (game / "Windows").mkdir(parents=True)
        if unity:
            (game / "Windows/UnityPlayer.dll").touch()

    def test_unity_game_keeps_the_launch_flags(self):
        script = self.launcher()
        self.install_game("123", "Some Unity Game", unity=True)
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-applaunch\n123\n-force-d3d11-no-singlethreaded\n-screen-fullscreen\n0\n",
                      (self.support / "args").read_text())

    def test_other_games_get_no_unity_flags(self):
        script = self.launcher()
        self.install_game("123", "Some Other Game")
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "args").read_text().split("\n")[-3:],
                         ["-applaunch", "123", ""])

    def test_game_with_unknown_folder_keeps_the_launch_flags(self):
        script = self.launcher()
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-force-d3d11-no-singlethreaded", (self.support / "args").read_text())

    def test_running_game_in_another_prefix_is_ignored(self):
        script = self.launcher(same_prefix=False)
        self.env["RUNNING_HEX"] = "0x1a"
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "start").read_text(), "start\n")

    def test_forwarder_failure_with_a_started_game_is_success(self):
        script = self.launcher(wine_exit=1)
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("steam started app 123", result.stderr)

    def test_forwarder_success_without_a_started_game_is_failure(self):
        # the log already holds an old game line for app 123; only a new one counts.
        script = self.launcher(game_app=None)
        result = self.run_launcher(script, "play", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not start app 123", result.stderr)

    def test_game_line_for_another_app_is_not_evidence(self):
        script = self.launcher(game_app="1234")
        result = self.run_launcher(script, "play", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not start app 123", result.stderr)

    def test_request_failure_is_nonzero(self):
        script = self.launcher(wine_exit=9, game_app=None)
        result = self.run_launcher(script, "play", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exited 9", result.stderr)
        self.assertIn("did not start app 123", result.stderr)

    def spawn_sleeper(self):
        proc = subprocess.Popen(["/bin/sleep", "60"])
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        return proc

    def reg_sequence(self, *hexes):
        (self.support / "reg-seq").write_text("".join(h + "\n" for h in hexes))

    def wineserver_calls(self):
        calls = self.support / "wineserver"
        return calls.read_text() if calls.exists() else ""

    def test_stop_ends_steam_wineserver_and_what_is_left(self):
        script = self.launcher()
        inside, outside = self.spawn_sleeper(), self.spawn_sleeper()
        (self.support / "leftover-pids").write_text(f"{inside.pid}\n")
        (self.support / "outside-pids").write_text(f"{outside.pid}\n")
        result = self.run_launcher(script, "stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-shutdown", (self.support / "args").read_text())
        self.assertEqual(self.wineserver_calls(), "-k\n")
        self.assertEqual(inside.wait(timeout=5), -signal.SIGTERM)
        self.assertIsNone(outside.poll())

    def test_stop_sweeps_leftovers_when_steam_is_already_gone(self):
        # the orphan case: winedevice and steamservice outlive their wineserver.
        script = self.launcher(same_prefix=False)
        inside = self.spawn_sleeper()
        (self.support / "leftover-pids").write_text(f"{inside.pid}\n")
        result = self.run_launcher(script, "stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.support / "args").exists())
        self.assertEqual(inside.wait(timeout=5), -signal.SIGTERM)

    def test_stop_leaves_a_running_game_alone(self):
        script = self.launcher()
        inside = self.spawn_sleeper()
        (self.support / "leftover-pids").write_text(f"{inside.pid}\n")
        self.env["RUNNING_HEX"] = "0x7b"
        result = self.run_launcher(script, "stop")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(result.stdout.strip(), "123")
        self.assertFalse((self.support / "args").exists())
        self.assertEqual(self.wineserver_calls(), "")
        self.assertIsNone(inside.poll())

    def test_watch_stops_the_bottle_when_the_game_is_over(self):
        script = self.launcher()
        self.reg_sequence("0x7b", "0x7b", "0x0")
        result = self.run_launcher(script, "watch", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("app 123 is over", result.stderr)
        self.assertIn("-shutdown", (self.support / "args").read_text())
        self.assertEqual(self.wineserver_calls(), "-k\n")
        # two polls with the game, then two without: the stop comes on the fourth.
        self.assertEqual(self.sleeps(), 3)

    def test_watch_does_not_stop_on_a_one_poll_gap(self):
        script = self.launcher()
        self.reg_sequence("0x7b", "0x0", "0x7b", "0x7b", "0x0")
        result = self.run_launcher(script, "watch", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.sleeps(), 5)
        self.assertEqual(self.wineserver_calls(), "-k\n")

    def test_watch_waits_while_a_play_request_is_in_flight(self):
        script = self.launcher()
        self.reg_sequence("0x7b", "0x0")
        (self.support / "play-flights").write_text("3\n")
        result = self.run_launcher(script, "watch", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.sleeps(), 5)

    def test_watch_gives_up_on_a_game_that_never_registers(self):
        script = self.launcher()
        result = self.run_launcher(script, "watch", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        # SEEN_WAIT is 30 s of 10 s polls, then two polls with nothing.
        self.assertEqual(self.sleeps(), 4)
        self.assertEqual(self.wineserver_calls(), "-k\n")

    def test_watch_does_nothing_once_steam_has_exited_by_itself(self):
        script = self.launcher(same_prefix=False)
        result = self.run_launcher(script, "watch", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("leaving the bottle alone", result.stderr)
        self.assertFalse((self.support / "args").exists())
        self.assertEqual(self.wineserver_calls(), "")

    def test_watch_rejects_a_bad_app_id(self):
        script = self.launcher()
        result = self.run_launcher(script, "watch", "12x")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid steam app id", result.stderr)

    def test_play_starts_the_exit_watch(self):
        script = self.launcher(watch_spawn='echo "watch $1" > "$DECANT_HOME/watch"')
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.support / "watch").read_text(), "watch 123\n")

    def test_running_game_does_not_start_an_exit_watch(self):
        script = self.launcher(watch_spawn='echo "watch $1" > "$DECANT_HOME/watch"')
        self.env["RUNNING_HEX"] = "0x1a"
        self.run_launcher(script, "play", "123")
        self.assertFalse((self.support / "watch").exists())

    def test_uninstall_request_failure_is_nonzero(self):
        script = self.launcher(wine_exit=9)
        result = self.run_launcher(script, "uninstall", "123")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("request failed", result.stderr)

    def test_account_id_never_reaches_the_output(self):
        script = self.launcher(same_prefix=False, sign_in="late")
        result = self.run_launcher(script, "play", "123")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = (self.support / "logs/decant-launch.log").read_text()
        for text in (result.stdout, result.stderr, log):
            self.assertNotIn("424242", text)

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
