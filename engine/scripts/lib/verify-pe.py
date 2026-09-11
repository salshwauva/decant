import hashlib
import os
from pathlib import Path
import sys


data = Path(sys.argv[1]).read_bytes()
if len(data) <= 64 or data[:2] != b"MZ":
    sys.exit("installer has no MZ header")
offset = int.from_bytes(data[60:64], "little")
if offset < 64 or offset > len(data) - 4 or data[offset:offset + 4] != b"PE\0\0":
    sys.exit("installer has no valid PE signature")
expected = os.environ.get("DECANT_STEAMSETUP_SHA256", "").lower()
if expected and hashlib.sha256(data).hexdigest() != expected:
    sys.exit("installer SHA256 mismatch")
