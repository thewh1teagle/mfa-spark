#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WITH_SMOKE_TEST=0
SMOKE_TEST_ONLY=0
STAGE=all

source "$ROOT/scripts/versions.env"
source "$ROOT/scripts/env.sh"

mkdir -p "$PREFIX" "$SRC" "$ROOT/logs"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --stage)
      STAGE="${2:-}"
      shift 2
      ;;
    --with-smoke-test)
      WITH_SMOKE_TEST=1
      shift
      ;;
    --smoke-test-only)
      SMOKE_TEST_ONLY=1
      shift
      ;;
    *)
      echo "Usage: $0 [--stage openfst-stack|kaldi|python-stack|all] [--with-smoke-test|--smoke-test-only]" >&2
      exit 2
      ;;
  esac
done

fetch_tarball() {
  local url="$1"
  local archive="$2"
  local dir="$3"
  if [[ ! -d "$dir" ]]; then
    wget -O "$archive" "$url"
    tar -xf "$archive" -C "$SRC"
  fi
}

clone_at_commit() {
  local repo="$1"
  local commit="$2"
  local dir="$3"
  if [[ ! -d "$dir/.git" ]]; then
    git clone "$repo" "$dir"
  fi
  git -C "$dir" fetch --tags origin
  git -C "$dir" checkout "$commit"
}

apply_repo_patch() {
  local dir="$1"
  local patch_file="$2"
  if git -C "$dir" apply --check "$patch_file"; then
    git -C "$dir" apply "$patch_file"
  else
    echo "Patch already applied or not applicable: $patch_file"
  fi
}

build_openfst_stack() {
  fetch_tarball "$OPENFST_URL" "$SRC/openfst-${OPENFST_VERSION}.tar.gz" "$SRC/openfst-${OPENFST_VERSION}"
  (
    cd "$SRC/openfst-${OPENFST_VERSION}"
    ./configure --prefix="$PREFIX" --enable-shared --enable-far --enable-pdt --enable-mpdt
    make -j"$(nproc)"
    make install
  )

  fetch_tarball "$NGRAM_URL" "$SRC/ngram-${NGRAM_VERSION}.tar.gz" "$SRC/ngram-${NGRAM_VERSION}"
  (
    cd "$SRC/ngram-${NGRAM_VERSION}"
    ./configure --prefix="$PREFIX"
    make -j"$(nproc)"
    make install
  )

  fetch_tarball "$BAUMWELCH_URL" "$SRC/baumwelch-${BAUMWELCH_VERSION}.tar.gz" "$SRC/baumwelch-${BAUMWELCH_VERSION}"
  (
    cd "$SRC/baumwelch-${BAUMWELCH_VERSION}"
    ./configure --prefix="$PREFIX"
    make -j"$(nproc)"
    make install
  )
}

build_kaldi() {
  clone_at_commit "$KALDI_REPO" "$KALDI_COMMIT" "$KALDI_ROOT"
  apply_repo_patch "$KALDI_ROOT" "$ROOT/patches/kaldi/cuda13-gb10-and-kalpy-nnet2.patch"

  mkdir -p "$KALDI_ROOT/tools/python"
  (
    cd "$KALDI_ROOT/tools"
    # Kaldi's dependency script does not know every DGX Spark/aarch64 package
    # name. Treat it as advisory and let the actual build fail if something
    # important is missing.
    extras/check_dependencies.sh || true
    if [[ ! -f "$KALDI_ROOT/tools/OpenBLAS/install/lib/libopenblas.so" ]]; then
      extras/install_openblas.sh
    else
      echo "OpenBLAS already installed, skipping extras/install_openblas.sh"
    fi
    make -j"$(nproc)"
  )

  (
    cd "$KALDI_ROOT/src"
    ./configure --shared --mathlib=OPENBLAS --openblas-root=../tools/OpenBLAS/install \
      --use-cuda=yes --cudatk-dir="$CUDA_HOME"
    make depend -j"$(nproc)"
    make -j"$(nproc)"
  )

  build_kaldi_portaudio_and_online
}

build_kaldi_portaudio_and_online() {
  (
    cd "$KALDI_ROOT/tools"
    # Gotcha 20: the installer can leave a duplicate pa_ringbuffer.o entry.
    # Reconfigure below and normalize the generated Makefile before build.
    extras/install_portaudio.sh || true
  )
  (
    cd "$KALDI_ROOT/tools/portaudio"
    ./configure --prefix="$PWD/install" --build=aarch64-unknown-linux-gnu
    perl -0pi -e 's{(^OTHER_OBJS =.*?)(\s+src/common/pa_ringbuffer\.o)}{$1}m' Makefile
    make -j"$(nproc)"
    make install
  )
  (
    cd "$KALDI_ROOT/src/online"
    make depend -j"$(nproc)"
    make -j"$(nproc)"
  )
}

stage_kalpy_kaldi_root() {
  local stage="$PREFIX/kalpy-kaldi-root"
  mkdir -p "$stage/include" "$stage/lib" "$stage/tools/openfst"
  ln -sfn "$KALDI_ROOT/src" "$stage/include/kaldi"
  ln -sfn "$PREFIX/include/fst" "$stage/include/fst"
  find "$KALDI_ROOT/src/lib" "$PREFIX/lib" -maxdepth 1 \( -type f -o -type l \) -name 'lib*.so*' -exec ln -sfn {} "$stage/lib/" \;
  ln -sfn "$stage/lib" "$stage/tools/openfst/lib"
}

build_python_stack() {
  uv venv --allow-existing --python "$PYTHON_VERSION" "$ROOT/.venv"
  source "$ROOT/.venv/bin/activate"
  uv pip install --upgrade pip setuptools wheel setuptools_scm cython pybind11 ninja cmake

  fetch_tarball "$PYNINI_URL" "$SRC/pynini-${PYNINI_VERSION}.tar.gz" "$SRC/pynini-${PYNINI_VERSION}"
  (
    cd "$SRC/pynini-${PYNINI_VERSION}"
    PYNINI_EXTENSIONS="$PREFIX" uv pip install -v --no-build-isolation .
  )

  clone_at_commit "$KALPY_REPO" "$KALPY_COMMIT" "$SRC/kalpy"
  apply_repo_patch "$SRC/kalpy" "$ROOT/patches/kalpy/pynini-pywrapfst-compat-header.patch"
  stage_kalpy_kaldi_root
  local pybind_cmake
  pybind_cmake="$(python -m pybind11 --cmakedir)"
  # Kalpy's build expects a Kaldi-style install root; stage one from the
  # source build outputs without copying the whole Kaldi tree.
  KALDI_ROOT="$PREFIX/kalpy-kaldi-root" \
    LD_LIBRARY_PATH="$PREFIX/kalpy-kaldi-root/lib:$LD_LIBRARY_PATH" \
    CMAKE_ARGS="-DCMAKE_PREFIX_PATH=$pybind_cmake -DCMAKE_INSTALL_RPATH=$PREFIX/kalpy-kaldi-root/lib -DCMAKE_BUILD_RPATH=$PREFIX/kalpy-kaldi-root/lib" \
    uv pip install -v -e "$SRC/kalpy"

  clone_at_commit "$MFA_REPO" "$MFA_COMMIT" "$SRC/Montreal-Forced-Aligner"
  uv pip install -e "$SRC/Montreal-Forced-Aligner"
  uv pip install pgvector jinja2
  uv pip uninstall pysoundfile || true
  uv pip install --reinstall soundfile
}

if [[ "$SMOKE_TEST_ONLY" -eq 0 ]]; then
  case "$STAGE" in
    openfst-stack)
      build_openfst_stack 2>&1 | tee "$ROOT/logs/build-openfst-stack.log"
      ;;
    kaldi)
      build_kaldi 2>&1 | tee "$ROOT/logs/build-kaldi.log"
      ;;
    python-stack)
      build_python_stack 2>&1 | tee "$ROOT/logs/build-python-stack.log"
      ;;
    all)
      build_openfst_stack 2>&1 | tee "$ROOT/logs/build-openfst-stack.log"
      build_kaldi 2>&1 | tee "$ROOT/logs/build-kaldi.log"
      build_python_stack 2>&1 | tee "$ROOT/logs/build-python-stack.log"
      ;;
    *)
      echo "Unknown stage: $STAGE" >&2
      exit 2
      ;;
  esac
fi

if [[ "$WITH_SMOKE_TEST" -eq 1 || "$SMOKE_TEST_ONLY" -eq 1 ]]; then
  "$ROOT/scripts/smoke-test.sh" 2>&1 | tee "$ROOT/logs/smoke-test.log"
fi

echo "Build complete. Run: source ./scripts/env.sh && source .venv/bin/activate && mfa --help"
