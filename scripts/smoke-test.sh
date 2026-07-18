#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/env.sh"
source "$ROOT/.venv/bin/activate"

python - <<'PY'
import _kalpy
from _kalpy import fstext, gmm, nnet2
import pynini

print("kalpy/pynini import ok", pynini.__version__)
PY

mfa version

if [[ ! -f "$ROOT/scripts/smoke/sample.wav" || ! -f "$ROOT/scripts/smoke/sample.txt" ]]; then
  echo "scripts/smoke/sample.wav and scripts/smoke/sample.txt are required for the smoke test" >&2
  exit 1
fi

rm -rf "$ROOT/runs/sample-overfit" "$ROOT/runs/sample-original"
mkdir -p "$ROOT/runs/sample-overfit/corpus/speaker1" "$ROOT/runs/sample-overfit/output" \
  "$ROOT/runs/sample-overfit/models" "$ROOT/runs/sample-overfit/temp"

for i in $(seq -w 1 24); do
  cp "$ROOT/scripts/smoke/sample.wav" "$ROOT/runs/sample-overfit/corpus/speaker1/utt${i}.wav"
  cp "$ROOT/scripts/smoke/sample.txt" "$ROOT/runs/sample-overfit/corpus/speaker1/utt${i}.txt"
done

cp "$ROOT/scripts/smoke/dictionary.txt" "$ROOT/runs/sample-overfit/dictionary.txt"
cp "$ROOT/scripts/smoke/train.yaml" "$ROOT/runs/sample-overfit/train.yaml"

mfa train "$ROOT/runs/sample-overfit/corpus" "$ROOT/runs/sample-overfit/dictionary.txt" \
  "$ROOT/runs/sample-overfit/models/sample_overfit.zip" \
  --output_directory "$ROOT/runs/sample-overfit/output" \
  --temporary_directory "$ROOT/runs/sample-overfit/temp" \
  --config_path "$ROOT/runs/sample-overfit/train.yaml" \
  --clean --overwrite --single_speaker --num_jobs 1 --no_use_mp

mkdir -p "$ROOT/runs/sample-original/corpus/speaker1" "$ROOT/runs/sample-original/output" \
  "$ROOT/runs/sample-original/temp"
cp "$ROOT/scripts/smoke/sample.wav" "$ROOT/runs/sample-original/corpus/speaker1/01.wav"
cp "$ROOT/scripts/smoke/sample.txt" "$ROOT/runs/sample-original/corpus/speaker1/01.txt"

mfa align "$ROOT/runs/sample-original/corpus" "$ROOT/runs/sample-overfit/dictionary.txt" \
  "$ROOT/runs/sample-overfit/models/sample_overfit.zip" "$ROOT/runs/sample-original/output" \
  --temporary_directory "$ROOT/runs/sample-original/temp" \
  --clean --overwrite --single_speaker --num_jobs 1 --no_use_mp

mkdir -p "$ROOT/plans/sample"
cp "$ROOT/runs/sample-original/output/speaker1/01.TextGrid" "$ROOT/plans/sample/01.TextGrid"
