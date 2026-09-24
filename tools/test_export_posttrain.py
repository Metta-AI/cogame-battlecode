"""Check full-match Battlecode post-training rows and seed separation."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path


BINARY = Path(sys.argv[1]).resolve()
VARIANT = sys.argv[2] if len(sys.argv) > 2 else "bc26"
ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory() as directory:
    output = Path(directory) / VARIANT
    subprocess.run([str(BINARY), str(output), "10", VARIANT], cwd=ROOT, check=True)
    manifest = json.loads((output / "manifest.json").read_text())
    train = [json.loads(line) for line in (output / "train.jsonl").read_text().splitlines()]
    validation = [json.loads(line) for line in (output / "validation.jsonl").read_text().splitlines()]
    assert manifest["game"] == "battlecode" and manifest["variant"] == VARIANT
    assert len(manifest["runs"]) == 10
    assert len(train) == manifest["train_examples"] == 16
    assert len(validation) == manifest["validation_examples"] == 4
    assert all(run["games"] >= 1 and len(run["scores"]) == 2
               for run in manifest["runs"])
    assert all(int(row["seed"].split("-")[-1]) % 5 != 0 for row in train)
    assert all(int(row["seed"].split("-")[-1]) % 5 == 0 for row in validation)
    for row in train + validation:
        assert row["game"] == "battlecode"
        assert row["action_schema_revision"] == "battlecode-doctrine-" + VARIANT
        assert row["prompt"][0]["role"] == "system"
        assert row["prompt"][1]["role"] == "user"
        assert "local-seat" not in json.dumps(row["prompt"])
        answer = json.loads(row["completion"][0]["content"])
        assert isinstance(answer["sheet"], dict)
        assert set(answer) == {"sheet", "notes", "motto"}
    print(VARIANT, len(train), len(validation))
