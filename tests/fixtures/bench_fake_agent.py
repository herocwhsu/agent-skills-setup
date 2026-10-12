import json
import os
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

mode = sys.argv[1]
if mode == "sleep":
    time.sleep(30)
elif mode == "apply":
    ref = Path(os.environ["BENCH_DIR"]) / "reference" / os.environ["BENCH_TASK_ID"]
    shutil.copytree(ref, ".", dirs_exist_ok=True)
    for stored in sorted(Path(".").rglob("*.fixture")):
        os.replace(stored, stored.with_suffix(""))

if mode == "log":
    now = datetime.now(timezone.utc).isoformat()
    with open(os.environ["FAKE_LOG"], "a", encoding="utf-8") as f:
        f.write(json.dumps({"timestamp": now, "attempt": True, "result": "ok"}) + "\n")
    row = {
        "type": "assistant",
        "timestamp": now,
        "message": {
            "id": "m1",
            "model": "fake-model",
            "usage": {"input_tokens": 1, "output_tokens": 7},
        },
    }
    Path(os.environ["FAKE_SESSION"]).write_text(json.dumps(row) + "\n", encoding="utf-8")
