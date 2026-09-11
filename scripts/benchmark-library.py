import os
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time


binary = Path(sys.argv[1] if len(sys.argv) > 1 else ".build/release/decant").resolve()
for count in [1000, 5000]:
    with tempfile.TemporaryDirectory(prefix="decant-benchmark-") as directory:
        root = Path(directory)
        apps = root / "bottles/steam11/drive_c/Program Files (x86)/Steam/steamapps"
        apps.mkdir(parents=True)
        for index in range(count):
            app_id = 100000 + index
            (apps / f"appmanifest_{app_id}.acf").write_text(
                f'"AppState" {{ "appid" "{app_id}" "name" "Game {count-index:05}" "StateFlags" "4" }}'
            )
        samples = []
        for run in range(6):
            start = time.perf_counter()
            result = subprocess.run([str(binary), "--games"], check=True, capture_output=True,
                                    env=dict(os.environ, DECANT_HOME=str(root)), timeout=30)
            elapsed = time.perf_counter() - start
            if len(result.stdout.splitlines()) != count:
                sys.exit("library count mismatch")
            if run:
                samples.append(elapsed)
            else:
                print(f"{count} games: first process {elapsed:.3f}s")
        print(f"{count} games: median of five later processes {statistics.median(samples):.3f}s")
