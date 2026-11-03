"""Keep all downloads, build products and reports outside the source checkout."""

import hashlib, os, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
default = Path(tempfile.gettempdir()) / (
    "msgpack-interop-"
    + str(os.getuid())
    + "-"
    + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
)
WORK = Path(os.environ.get("INTEROP_WORK_DIR", str(default))).resolve()
if WORK == ROOT or ROOT in WORK.parents:
    raise ValueError("INTEROP_WORK_DIR must be outside the interop source directory")
if __name__ == "__main__":
    print(WORK)
