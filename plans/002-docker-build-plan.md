# Docker And Script Build Plan

`scripts/versions.env` - will pin every external version/commit used by the build: OpenFst, OpenGrm NGram, Baum-Welch, Pynini, Kaldi, Kalpy, MFA, Python, and CUDA home.

`patches/kaldi/cuda13-gb10-and-kalpy-nnet2.patch` - will carry the local Kaldi fixes for CUDA 13, GB10 `sm_121`, CUDA 13 C++17/CUB/CCCL compatibility, CUDA compute-mode API changes, and the missing Kaldi `nnet2` objects Kalpy binds.

`patches/kalpy/pynini-pywrapfst-compat-header.patch` - will carry the local Kalpy compatibility header for Pynini 2.1.7's private Cython object layout.

`scripts/build.sh` - is the source-of-truth build: download/clone pinned sources, apply patches, build OpenFst/OpenGrm/Baum-Welch, build CUDA Kaldi, build Pynini/Kalpy/MFA through `uv`, and optionally call the smoke test.

`scripts/smoke-test.sh` - runs the runtime validation: `_kalpy`/Pynini imports, `mfa version`, sample overfit training, sample alignment, and TextGrid copyout.

`scripts/smoke/` - contains the tracked smoke-test fixtures: sample WAV, transcript, dictionary, and training config.

`scripts/env.sh` - is the committed runtime path setup for CUDA, Kaldi, OpenFst, and local libraries.

`Dockerfile` - uses cacheable stages: base dependencies, `openfst-stack`, `kaldi`, `python-stack`, then a runtime stage that copies only Docker entrypoint and smoke files after the expensive compile layers. CUDA smoke tests run with `docker run --gpus all`, not during `docker build`.

`docker/entrypoint.sh` - will source `scripts/env.sh`, activate `.venv`, and then run `mfa` or any command passed to the container.

`.dockerignore` - will keep generated local build outputs like `.venv`, `opt`, `src`, `logs`, and `runs` out of the Docker build context.
