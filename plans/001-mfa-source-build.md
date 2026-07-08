# MFA Source Build On DGX Spark

This repo's source of truth is the scripted build, not a hand-run command log.

Use:

```bash
./scripts/build.sh
```

For a host build with the sample overfit check:

```bash
./scripts/build.sh --with-smoke-test
```

For Docker:

```bash
docker build -t mfa-spark:cuda13 .
docker run --rm --gpus all mfa-spark:cuda13 ./scripts/build.sh --smoke-test-only
```

The smoke-test WAV/text fixtures are tracked under `scripts/smoke/`; the generated TextGrid output is written to ignored local path `plans/sample/01.TextGrid`.

Pinned versions live in `scripts/versions.env`. Runtime paths live in the committed, relocatable env file:

- `scripts/env.sh`

Reusable source patches live in:

- `patches/kaldi/cuda13-gb10-and-kalpy-nnet2.patch`
- `patches/kalpy/pynini-pywrapfst-compat-header.patch`

The build currently compiles:

- OpenFst `1.8.4`
- OpenGrm NGram `1.3.17`
- Baum-Welch `0.3.11`
- Kaldi at the pinned commit, CUDA-enabled for DGX Spark/CUDA 13
- Pynini `2.1.7`
- Kalpy at the pinned commit
- Montreal Forced Aligner at the pinned commit

Stage-only rebuilds are available for debugging:

```bash
./scripts/build.sh --stage openfst-stack
./scripts/build.sh --stage kaldi
./scripts/build.sh --stage python-stack
```

Known build gotchas and their fixes are documented in `plans/gotchas.md`.
