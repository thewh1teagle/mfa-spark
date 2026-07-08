# MFA Spark

Reproducible source build for Montreal Forced Aligner on NVIDIA DGX Spark / ARM64 with CUDA 13.

The build compiles the native stack locally instead of relying on conda binaries:

- OpenFst, OpenGrm NGram, Baum-Welch, and Pynini
- Kaldi with CUDA enabled
- Kalpy
- Montreal Forced Aligner

Pinned source versions and commits are in `scripts/versions.env`. Local compatibility fixes are kept as reusable patches under `patches/`.

## Requirements

- Linux on ARM64/aarch64
- NVIDIA CUDA toolkit at `/usr/local/cuda-13.0` by default
- `uv`
- Docker with NVIDIA runtime for container smoke tests
- Standard native build tools if building on the host
- `sqlite3` CLI for MFA alignment collection

Override CUDA location when needed:

```bash
CUDA_HOME=/path/to/cuda ./scripts/build.sh
```

## Host Build

```bash
./scripts/build.sh
source ./scripts/env.sh
source .venv/bin/activate
mfa version
```

Run the sample overfit smoke test:

```bash
./scripts/build.sh --smoke-test-only
```

Or build and smoke-test in one host run:

```bash
./scripts/build.sh --with-smoke-test
```

The smoke test trains a tiny overfit acoustic model from the tracked fixture in `scripts/smoke/`, aligns the sample utterance, and writes:

```text
plans/sample/01.TextGrid
```

That TextGrid is generated output and is intentionally ignored.

## Docker

Build the image:

```bash
docker build -t mfa-spark:cuda13 .
```

Run CUDA/runtime validation from the built image:

```bash
docker run --rm --gpus all mfa-spark:cuda13 ./scripts/build.sh --smoke-test-only
```

Run MFA directly:

```bash
docker run --rm --gpus all mfa-spark:cuda13 mfa version
```

The Dockerfile is staged so expensive layers are cached separately:

- `openfst-stack`
- `kaldi`
- `python-stack`
- final runtime layer with entrypoint and smoke fixtures

CUDA smoke tests are not run during `docker build`; `libcuda.so.1` is injected by the NVIDIA runtime only during `docker run --gpus all`.

## Useful Commands

Rebuild only one host stage:

```bash
./scripts/build.sh --stage openfst-stack
./scripts/build.sh --stage kaldi
./scripts/build.sh --stage python-stack
```

Check imports and linked CUDA libraries after a host build:

```bash
source ./scripts/env.sh
source .venv/bin/activate
python - <<'PY'
import _kalpy, pynini
from _kalpy import cudamatrix, fstext, gmm, nnet2
print("ok", pynini.__version__, _kalpy.__file__)
PY
ldd "$(python -c 'import _kalpy; print(_kalpy.__file__)')" | grep -E 'libkaldi-cudamatrix|libcudart|libcuda|libcublas|not found'
```

## Layout

- `scripts/build.sh` - source-of-truth staged build runner
- `scripts/env.sh` - runtime environment setup
- `scripts/smoke-test.sh` - import check plus sample train/align validation
- `scripts/smoke/` - tracked smoke-test WAV, transcript, dictionary, and train config
- `patches/` - reusable source patches
- `plans/gotchas.md` - failures encountered and exact fixes
- `plans/timings.md` - observed build timings
- `Dockerfile` - staged CUDA 13 build image

## Notes

Known gotchas are documented as they are found in `plans/gotchas.md`. If a build fails, check the matching log in `logs/` and add the failure plus fix there before rerunning.
