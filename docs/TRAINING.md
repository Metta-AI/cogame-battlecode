# Battlecode post-training

The exporter runs the production match engine with the shipped strong
scripted doctrine for each year. Each row pairs the model-facing system
preamble and seat-specific public brief with that year's scripted reply.
Both seats' prompts are captured before the match. The completed game is
scored by the production rules. Matches are split between training and
validation by seed.

```sh
nimby sync nimby.lock
nim c -d:release --path:src -o:/tmp/battlecode-posttrain tools/export_posttrain.nim
/tmp/battlecode-posttrain /tmp/battlecode-bc26-dataset 10 bc26
```

The variant may be any of `bc26`, `bc20`, `bc21`, `bc24`, `bc25`, `bc23`,
`bc22`, `bc16`, `bc19`, or `bc17`. Each output directory contains
`train.jsonl`, `validation.jsonl`, and `manifest.json`. The exporter needs
at least ten matches, giving both train and validation seeds. It refuses to
overwrite an existing directory.

From a Metta checkout with the post-training package installed:

```sh
uv run --package metta-posttrain --extra train python -m metta_posttrain.train \
  --dataset /tmp/battlecode-bc26-dataset \
  --output /tmp/battlecode-adapter --model Qwen/Qwen3-0.6B \
  --max-steps 100 --max-length 8192
```

The dataset teaches doctrine replies for the fixed champion chassis. It does
not train per-robot actions; those are executed by the game's deterministic
year-specific chassis after the doctrine decision.
