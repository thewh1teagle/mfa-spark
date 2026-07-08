# Build Gotchas

This file records every issue that blocks or changes the expected MFA/Kaldi/CUDA build path, plus the fix or workaround used.

## 1. CUDA driver is installed, but `nvcc` is missing from `PATH`

Evidence:

```text
nvidia-smi reports Driver Version 580.126.09 and CUDA Version 13.0 on NVIDIA GB10.
which nvcc fails.
```

Impact:

Kaldi CUDA compilation requires the CUDA toolkit compiler (`nvcc`), not only the NVIDIA driver/runtime.

Fix/workaround:

The toolkit is already installed at `/usr/local/cuda-13.0`; it is just not exposed as `/usr/local/cuda` or on `PATH`.

Use:

```bash
export CUDA_HOME=/usr/local/cuda-13.0
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
```

before configuring Kaldi.

## 2. OpenGrm NGram and Baum-Welch ignore `--with-openfst`

Evidence:

```text
configure: WARNING: unrecognized options: --with-openfst
```

Impact:

The build does not fail, but the documented `--with-openfst="$PREFIX"` option is ignored by these autotools releases. They discover OpenFst through the active compiler/linker environment instead.

Fix/workaround:

Keep these variables exported before running `configure`:

```bash
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPLUS_INCLUDE_PATH="$PREFIX/include:${CPLUS_INCLUDE_PATH:-}"
export LIBRARY_PATH="$PREFIX/lib:${LIBRARY_PATH:-}"
```

Then verify the installed binaries resolve to local libraries:

```bash
ldd opt/bin/ngramcount
ldd opt/bin/baumwelchtrain
```

## 3. Kaldi `check_dependencies.sh` prints Python symlink errors but continues

Evidence:

```text
ln: failed to create symbolic link '.../kaldi/tools/python/python3': No such file or directory
ln: failed to create symbolic link '.../kaldi/tools/python/python': No such file or directory
extras/check_dependencies.sh: all OK.
```

Impact:

This is noisy but did not block the Kaldi tools build. The script still detected Python 3 and reported dependency success.

Fix/workaround:

No build fix was needed. If rerunning manually and the warning is distracting, create the directory first:

```bash
mkdir -p src/kaldi/tools/python
```

## 4. Kaldi `src/configure` CUDA option spelling is strict

Evidence:

```text
Unknown argument: CUDA_HOME=/usr/local/cuda-13.0, exiting
Unknown argument: --use-cuda, exiting
```

Impact:

The initial Kaldi tools build completed, but Kaldi `src` configuration stopped before compiling Kaldi itself.

Fix/workaround:

Use Kaldi's supported CUDA option names:

```bash
cd src/kaldi/src
./configure --shared --mathlib=OPENBLAS --use-cuda=yes --cudatk-dir=/usr/local/cuda-13.0
```

Do not pass `CUDA_HOME=...` after the configure options. Keep `CUDA_HOME` exported in the shell environment if desired. The help text lists `--use-cuda`, but this checked-out parser accepts only `--use-cuda=yes` or `--use-cuda=no`.

## 5. Kaldi OPENBLAS mode expects a bundled local OpenBLAS by default

Evidence:

```text
./configure: FATAL: OpenBLAS not found in '../tools/OpenBLAS/install'.
```

Impact:

Even though Ubuntu `libopenblas-dev` is installed, Kaldi's default `--mathlib=OPENBLAS` lookup expects `src/kaldi/tools/OpenBLAS/install` unless `--openblas-root=` is passed.

Fix/workaround:

Build Kaldi's local OpenBLAS so the dependency is compiled inside this workspace:

```bash
cd src/kaldi/tools
extras/install_openblas.sh
```

Then rerun:

```bash
cd src/kaldi/src
./configure --shared --mathlib=OPENBLAS --openblas-root=../tools/OpenBLAS/install --use-cuda=yes --cudatk-dir=/usr/local/cuda-13.0
```

Additional note:

This Kaldi checkout's configure script prints `../tools/OpenBLAS/install` in the error message but the actual default lookup in the script is `../tools/extras/OpenBLAS/install`. Passing `--openblas-root=../tools/OpenBLAS/install` avoids that mismatch.

## 6. Kaldi configure does not know CUDA 13.0 / GB10 yet

Evidence:

```text
***configure failed: Unsupported CUDA version 13_0.
```

Additional local evidence:

```text
nvcc --list-gpu-arch includes compute_120 and compute_121.
Tiny CUDA runtime query reports: NVIDIA GB10 12.1.
```

Impact:

Kaldi stopped at CUDA configuration even though the CUDA 13.0 toolkit and GB10 GPU are installed and working.

Fix/workaround:

Patch `src/kaldi/src/configure` locally:

- Accept `13_*` CUDA versions.
- Treat GCC versions below 15 as supported for this local CUDA 13.0/GCC 13.3 setup.
- For `aarch64`, set `CUDA_ARCH` to `-gencode arch=compute_121,code=sm_121`.
- For non-aarch64 CUDA 13, add Blackwell `sm_120` and `sm_121`.

This is a local compatibility patch for the DGX Spark/GB10 toolchain.

## 7. CUDA 13 requires C++17 and removed `cudaDeviceProp.computeMode`

Evidence:

```text
Thrust requires at least C++17.
libcu++ requires at least C++ 17.
The version of CUB in your include path is not compatible with this release of Thrust.
cu-device.cc:379:20: error: 'struct cudaDeviceProp' has no member named 'computeMode'
```

Impact:

Kaldi's CUDA build reached `cudamatrix`, generated several CUDA object files for `sm_121`, then failed on CUDA 13 API/toolchain compatibility.

Fix/workaround:

Patch local Kaldi files:

- `src/kaldi/src/makefiles/cuda_64bit.mk`: use `-std=c++17`.
- Add `-DCCCL_IGNORE_DEPRECATED_CPP_DIALECT`.
- Add `-DTHRUST_IGNORE_CUB_VERSION_CHECK` because Kaldi's bundled CUB 1.8.0 is older than CUDA 13's bundled CCCL/Thrust expectation.
- `src/kaldi/src/cudamatrix/cu-device.cc`: for CUDA 13+, query compute mode with `cudaDeviceGetAttribute(..., cudaDevAttrComputeMode, ...)` instead of the removed `cudaDeviceProp.computeMode` field.

## 8. Kaldi bundled CUB 1.8.0 uses removed CUDA 13 texture APIs

Evidence:

```text
tex_ref_input_iterator.cuh(88): error: texture is not a template
tex_ref_input_iterator.cuh(100): error: identifier "cudaBindTexture" is undefined
tex_ref_input_iterator.cuh(109): error: identifier "cudaUnbindTexture" is undefined
make: *** [Makefile:172: cudafeat] Error 2
```

Impact:

The main Kaldi CUDA libraries and many binaries linked successfully, but the final `cudafeat` CUDA decoder feature objects failed because the build selected Kaldi's old `tools/cub-1.8.0` headers before CUDA 13's bundled CCCL/CUB headers.

Fix/workaround:

Patch `src/kaldi/src/makefiles/cuda_64bit.mk` so `CUDA_INCLUDE` no longer includes `-I$(CUBROOT)`. Because `configure` had already generated `src/kaldi/src/kaldi.mk`, patch the generated `kaldi.mk` the same way for the active build. The configure check can still validate that CUB exists, but compilation now prefers CUDA 13's supported CUB/CCCL headers from `$(CUDATKDIR)/include`.

Verification:

Rebuild passed after patching both the template and generated `kaldi.mk`; `nvcc` command lines no longer include `-I.../tools/cub-1.8.0`.

## 9. CUDA 13 CCCL/CUB removed old `cub::Min()` functor alias

Evidence:

```text
cuda-decoder-kernels.cu(557): error: namespace "cub" has no member "Min"
CostType min = BlockReduce(temp_storage).Reduce(total_cost, cub::Min());
```

Impact:

After switching away from Kaldi's old bundled CUB, the CUDA decoder started compiling with CUDA 13's bundled CCCL/CUB headers. Those headers no longer expose the old `cub::Min()` alias used by Kaldi.

Fix/workaround:

Patch `src/kaldi/src/cudadecoder/cuda-decoder-kernels.cu` to use the CUDA 13 CCCL functor form:

```cpp
::cuda::minimum<CostType>{}
```

Verification:

Rebuild passed and linked `libkaldi-cudadecoder.so` plus `cudadecoderbin` binaries against CUDA 13 libraries.

## 10. Pynini requires OpenFst MPDT/PDT extensions

Evidence:

```text
extensions/_pynini.cpp:1230:10: fatal error: fst/extensions/mpdt/compose.h: No such file or directory
```

Impact:

The local OpenFst install worked for base FST, OpenGrm NGram, Baum-Welch, and Kaldi, but Pynini needs OpenFst extension headers/libraries that were not enabled in the first OpenFst build.

Fix/workaround:

Reconfigure and reinstall OpenFst with at least `far`, `pdt`, and `mpdt` extensions enabled:

```bash
cd src/openfst-1.8.4
./configure --prefix="$PREFIX" --enable-shared --enable-far --enable-pdt --enable-mpdt
make -j"$(nproc)"
make install
```

Verification:

Rebuild in progress.

## 11. MFA source install omits Kalpy dependency

Evidence:

```text
ModuleNotFoundError: No module named '_kalpy'
```

Impact:

`uv pip install -e .` from the MFA repository installed the CLI and Python dependencies listed in `setup.cfg`, but this source checkout does not list `kalpy` in `install_requires`. MFA 3.x imports `_kalpy` at startup, so `mfa version` and `mfa -h` fail without Kalpy.

Fix/workaround:

Kalpy is not published on PyPI, so `uv pip install kalpy` cannot resolve it. Clone/build Kalpy from source in the same `uv` environment instead.

Verification:

Source install in progress.

## 12. Kalpy links Kaldi's legacy `online` library, which needs PortAudio

Evidence:

```text
ERROR: portaudio is required. Run tools/install_portaudio.sh.
online-audio-source.h:29:10: fatal error: pa_ringbuffer.h: No such file or directory
```

Impact:

The main Kaldi/MFA runtime path uses `online2`, but Kalpy's CMake target links `kaldi-online` as well. The top-level Kaldi build did not build the legacy `online` library, and that target needs Kaldi's local PortAudio install.

Fix/workaround:

Build Kaldi's local PortAudio and then build `src/kaldi/src/online`:

```bash
cd src/kaldi/tools
extras/install_portaudio.sh
cd ../src
make online -j"$(nproc)"
```

Verification:

Build in progress.

## 13. Kaldi PortAudio helper uses stale `config.guess` on aarch64

Evidence:

```text
config.guess timestamp = 2011-05-11
uname -m = aarch64
configure: error: cannot guess build type; you must specify one
```

Impact:

`extras/install_portaudio.sh` downloaded and patched PortAudio, but its old autotools config scripts do not recognize DGX Spark/aarch64. The helper also continued after configure failed, so the shell exit status was misleading.

Fix/workaround:

Run PortAudio configure manually with an explicit build triple:

```bash
cd src/kaldi/tools/portaudio
./configure --prefix="$PWD/install" --build=aarch64-unknown-linux-gnu
make -j"$(nproc)"
make install
```

Verification:

Manual PortAudio build completed successfully after the duplicate object fix in gotcha 14.

## 14. Kaldi PortAudio helper patch can duplicate `pa_ringbuffer.o`

Evidence:

```text
/usr/bin/ld: src/common/.libs/pa_ringbuffer.o: multiple definition of `PaUtil_GetRingBufferReadAvailable'
```

Impact:

After manually configuring PortAudio for aarch64, linking failed because `pa_ringbuffer.o` appeared both in the common object list and in JACK-related `OTHER_OBJS`.

Fix/workaround:

Patch the generated `src/kaldi/tools/portaudio/Makefile` so `OTHER_OBJS` does not include `src/common/pa_ringbuffer.o`; keep the common object list entry. Then rerun `make && make install`.

Verification:

PortAudio installed successfully, and `src/kaldi/src/online/libkaldi-online.so` built successfully against it.

## 15. Kalpy expects Pynini's private `_pywrapfst.h`, but Pynini does not install it

Evidence:

```text
extensions/fstext/pybind_fstext.h:20:10: fatal error: _pywrapfst.h: No such file or directory
extensions/lm/lm.cpp:356:37: error: 'SymbolTableObject' does not name a type
```

Impact:

Kalpy bridges Kaldi FSTs to Pynini by reading the Cython object layout for `pywrapfst.VectorFst`. Current Pynini/OpenFst source and wheel installs provide `_pywrapfst.cpp`, `.pyx`, and `.pxd` files, but not the private C/C++ header Kalpy includes.

Fix/workaround:

Add a local compatibility header at `src/kalpy/extensions/fstext/_pywrapfst.h` matching the installed Pynini 2.1.7 Cython object layout for `Fst`, `MutableFst`, `VectorFst`, and `SymbolTable`. This is scoped to the Kalpy source checkout and only exposes the fields Kalpy already dereferences.

Verification:

Kalpy rebuilt successfully, and `_kalpy`, `_kalpy.gmm`, `_kalpy.fstext`, `_kalpy.cudamatrix`, and `_kalpy.nnet2` import successfully.

## 16. Kalpy binds Kaldi nnet2 sources that were not exported by `libkaldi-nnet2.so`

Evidence:

```text
ImportError: undefined symbol: kaldi::nnet2::CombineNnetsA(...)
```

Impact:

Kalpy linked against `libkaldi-nnet2.so`, but this Kaldi checkout's `src/nnet2/Makefile` did not include `combine-nnet-a.o` or `shrink-nnet.o` in `OBJFILES`, even though Kalpy's `nnet2.cpp` includes and binds those APIs.

Fix/workaround:

Patch `src/kaldi/src/nnet2/Makefile` locally to add:

```make
combine-nnet-a.o shrink-nnet.o
```

to `OBJFILES`, then rebuild `src/kaldi/src/nnet2` and rerun the Kalpy import check.

Verification:

`src/kaldi/src/nnet2/libkaldi-nnet2.so` rebuilt successfully, and `_kalpy` import no longer reports unresolved `nnet2` symbols.

## 17. MFA source install did not install all current runtime imports

Evidence:

```text
ModuleNotFoundError: No module named 'pgvector'
ModuleNotFoundError: No module named 'jinja2'
```

Impact:

After Kalpy imported successfully, the MFA CLI still failed during import because current MFA source imports packages that are not listed in `setup.cfg`'s `install_requires`.

Fix/workaround:

Install the missing runtime dependencies into the `uv` environment as they are exposed by CLI import checks:

```bash
uv pip install pgvector jinja2
```

Verification:

`mfa version` reports `3.4.0`, and `mfa --help` loads successfully.

## 18. `pysoundfile` shadows modern `soundfile` and rejects `Path` inputs

Evidence:

```text
TypeError: Invalid file: PosixPath('.../utt12.wav')
import soundfile; soundfile.__version__ == 0.9.0
uv pip show soundfile == 0.14.0 and pysoundfile == 0.9.0.post1
```

Impact:

MFA passes `pathlib.Path` objects when reading WAV metadata. The old `pysoundfile` package installed a top-level `soundfile.py` that shadowed the newer `soundfile` package required by `librosa`, causing corpus loading to fail.

Fix/workaround:

Remove the obsolete package and keep modern `soundfile`:

```bash
uv pip uninstall pysoundfile
uv pip install --reinstall soundfile
```

Verification:

Modern `soundfile 0.14.0` imports correctly, accepts `Path` inputs, and MFA corpus validation completed successfully.

## 19. CUDA 13 CCCL removed the old `cub::Max()` reducer functor

Evidence:

```text
cu-kernels.cu(2864): error: namespace "cub" has no member "Max"
cu-kernels.cu(3057): error: namespace "cub" has no member "Max"
```

Impact:

Kaldi's CUDA matrix kernels failed during `src/cudamatrix` compilation with CUDA 13, after the earlier `cub::Min()` decoder fix had already been applied.

Fix/workaround:

Patch `src/kaldi/src/cudamatrix/cu-kernels.cu` to use CUDA CCCL's current functor:

```cpp
::cuda::maximum<Real>{}
```

instead of:

```cpp
cub::Max()
```

The reusable patch `patches/kaldi/cuda13-gb10-and-kalpy-nnet2.patch` now includes this hunk, so clean host and Docker builds apply it automatically.

Verification:

The clean host build resumed past `cu-kernels.cu` and linked CUDA-enabled Kaldi binaries. Later failure moved to the separate portaudio step, so this CUDA 13 `cub::Max()` issue is fixed.

## 20. PortAudio duplicate-object cleanup regex was over-escaped

Evidence:

```text
Backslash found where operator expected (Missing operator before "\") at -e line 1, near "common\"
Unknown regexp modifier "/_" at -e line 1, at end of line
Execution of -e aborted due to compilation errors.
script_build_status=255
```

Impact:

After Kaldi's CUDA build completed, `scripts/build.sh` reached the PortAudio rebuild step and failed before `make` because the Perl one-liner intended to remove a duplicate `pa_ringbuffer.o` reference used slash-delimited regex syntax with over-escaped path separators.

Fix/workaround:

Use a non-slash regex delimiter so the path can be matched literally:

```bash
perl -0pi -e 's{(^OTHER_OBJS =.*?)(\s+src/common/pa_ringbuffer\.o)}{$1}m' Makefile
```

Verification:

The resumed host build completed PortAudio `make` and `make install`, then continued into Kaldi `online` and the Python stack. The host script finished with `script_build_status=0`, so this regex fix is verified.

## 21. Kaldi OpenBLAS reinstall made resumed builds much slower

Evidence:

```text
make -j 20 -C ./lapack-netlib lapacklib
```

appeared on a resumed `scripts/build.sh` run even though OpenBLAS had already been built during the same clean build attempt.

Impact:

Resume builds spent time rebuilding Kaldi's bundled OpenBLAS/LAPACK instead of quickly continuing from the failed Kaldi/MFA stage. This does not change runtime behavior, but it makes iterative source-build debugging slower.

Fix/workaround:

`scripts/build.sh` now skips `extras/install_openblas.sh` when:

```bash
src/kaldi/tools/OpenBLAS/install/lib/libopenblas.so
```

already exists.

Verification:

The resumed host build printed `OpenBLAS already installed, skipping extras/install_openblas.sh` and continued through Kaldi, Kalpy, MFA installation, and final script completion with `script_build_status=0`.

## 22. Docker build cannot run CUDA runtime import smoke tests

Evidence:

```text
ImportError: libcuda.so.1: cannot open shared object file: No such file or directory
ERROR: failed to build: failed to solve: process "/bin/sh -c chmod +x ./scripts/build.sh ./docker/entrypoint.sh   && ./scripts/build.sh --with-smoke-test" did not complete successfully: exit code: 1
```

Impact:

The image compiled Kaldi, Pynini, Kalpy, and MFA, but failed when the build-time smoke test imported `_kalpy`/`cudamatrix`. `libcuda.so.1` is not part of the CUDA devel image; Docker injects it from the host driver only when the container is run with the NVIDIA runtime, e.g. `docker run --gpus all`.

Fix/workaround:

Keep Docker image construction as a compile/install step:

```dockerfile
RUN chmod +x ./scripts/build.sh ./docker/entrypoint.sh \
  && ./scripts/build.sh
```

Then run runtime validation after the image exists:

```bash
docker run --rm --gpus all mfa-spark:cuda13 ./scripts/build.sh --smoke-test-only
```

`scripts/build.sh` now supports `--smoke-test-only`, so the Docker runtime smoke test verifies imports plus sample `mfa train`/`mfa align` without rebuilding all dependencies.

Verification:

Post-build Docker runtime validation passed under `docker run --gpus all`: `mfa version` printed `3.4.0`, `_kalpy`, `pynini`, and Kalpy CUDA modules imported successfully, and `ldd` resolved `libcuda.so.1`, `libcudart.so.13`, `libcublas.so.13`, and `libcublasLt.so.13`.

## 23. MFA needs all Kaldi `*bin` directories on `PATH`

Evidence:

```text
Could not find 'compute-mfcc-feats'.
```

Impact:

The extracted smoke test imported `_kalpy` and printed `mfa version`, but `mfa train` failed during MFA's third-party binary check. `compute-mfcc-feats` is built under Kaldi `src/featbin`, while the env file only added `src/bin` and OpenFst's bin directory.

Fix/workaround:

`scripts/env.sh` now prepends every existing Kaldi `src/*bin` directory to `PATH`:

```bash
for _mfa_bin_dir in "$KALDI_ROOT"/src/*bin "$KALDI_ROOT"/src/bin; do
  if [ -d "$_mfa_bin_dir" ]; then
    export PATH="$_mfa_bin_dir:$PATH"
  fi
done
```

Verification:

`./scripts/build.sh --smoke-test-only` completed on the host build, training the sample overfit model, aligning `plans/sample/01.wav`, and writing `plans/sample/01.TextGrid`.

## 24. Monolithic Docker `RUN` made small edits restart the whole source build

Evidence:

After changing only build orchestration/smoke-test behavior, Docker invalidated the single compile layer:

```dockerfile
RUN chmod +x ./scripts/build.sh ./docker/entrypoint.sh \
  && ./scripts/build.sh
```

and restarted from OpenFst.

Impact:

Small changes to `scripts/`, sample handling, or Docker runtime setup caused another multi-hour compile path instead of reusing completed OpenFst/Kaldi/Python layers.

Fix/workaround:

The Dockerfile now has explicit cache boundaries:

```dockerfile
FROM build-base AS openfst-stack
RUN ./scripts/build.sh --stage openfst-stack

FROM openfst-stack AS kaldi
RUN ./scripts/build.sh --stage kaldi

FROM kaldi AS python-stack
RUN ./scripts/build.sh --stage python-stack
```

Runtime-only files, `scripts/smoke-test.sh` and `scripts/smoke/`, are copied after the expensive compile layers. The image no longer copies `plans/` just to get the smoke sample; the tracked sample WAV/text fixtures now live under `scripts/smoke/`.

Verification:

The staged Docker rebuild completed successfully. After a runtime-only `sqlite3` fix, Docker reused the cached OpenFst, Kaldi, and Python stack layers and rebuilt only the final runtime layer.

## 25. Smoke sample audio was ignored under `plans/sample`

Evidence:

`.gitignore` intentionally ignores non-Markdown files under `plans/`, so `plans/sample/01.wav` and `plans/sample/01.txt` were local-only payloads.

Impact:

A fresh checkout would have the smoke-test script and docs but not the WAV/text fixture needed to run the sample overfit test. Docker also had to copy `plans/sample` just to get test data.

Fix/workaround:

The smoke-test fixture is now tracked under `scripts/smoke/`:

```text
scripts/smoke/sample.wav
scripts/smoke/sample.txt
scripts/smoke/dictionary.txt
scripts/smoke/train.yaml
```

`scripts/smoke-test.sh` reads from `scripts/smoke/` and only writes generated `plans/sample/01.TextGrid` as local ignored output.

Verification:

`./scripts/build.sh --smoke-test-only` completed on the host using `scripts/smoke/sample.wav`, trained the overfit model, aligned the sample, and wrote `plans/sample/01.TextGrid`.

## 26. MFA smoke test needs the `sqlite3` executable at runtime

Evidence:

The Docker image built successfully and `mfa version` plus `_kalpy` CUDA imports passed under `docker run --gpus all`, but the sample overfit test failed during `mfa train` alignment collection:

```text
FileNotFoundError: [Errno 2] No such file or directory: 'sqlite3'
```

Impact:

MFA uses Python SQLite libraries and also shells out to the `sqlite3` CLI in parts of the training/alignment collection path. A container can pass import checks but still fail real `mfa train` or `mfa align` workflows if the executable is missing.

Fix/workaround:

Install `sqlite3` in the Docker runtime layer and list it as a host runtime requirement in `README.md`.

Verification:

The Docker runtime rebuild completed successfully, reusing all expensive compile layers. The Docker smoke test then passed under `docker run --gpus all`, training the sample overfit model, running `mfa align`, and writing a host-visible `runs/docker-smoke-out/01.TextGrid`.

## 27. Kalpy linked CUDA libraries but reported `CudaCompiled: False`

Evidence:

The Docker image linked `_kalpy` against CUDA libraries and `docker run --gpus all` exposed the GPU, but the Kalpy CUDA probe reported:

```text
CudaCompiled: False
```

`nvidia-smi` also showed no MFA/Kaldi compute process during the tiny GMM overfit smoke test. That smoke workflow is CPU-bound, so it is not a reliable proof of GPU execution.

Impact:

The build could appear CUDA-linked while Kalpy's C++ extension was compiled without `HAVE_CUDA`, making its CUDA wrapper report false and compile out GPU code paths. This hid the difference between "CUDA libraries are linked" and "Kalpy was compiled with CUDA macros enabled."

Fix/workaround:

Patch Kalpy's CMake build to define `HAVE_CUDA=1` and add CUDAToolkit include directories when CUDA is found. The CUDA include dirs are required once `HAVE_CUDA` causes Kaldi CUDA headers to include `cublas_v2.h`.

Kalpy also called a stale `CuDevice::SelectGpuDevice` method. This Kaldi checkout only exposes public `CuDevice::SelectGpuId(std::string)`, so the compatibility patch maps Kalpy's Python-facing `SelectGpuDevice(device_id)` wrapper to `SelectGpuId(device_id < 0 ? "no" : "yes")`.

Verification:

After rebuilding the host Python stack, this probe passed:

```text
CudaCompiled: True
SelectGpuId yes:
selected
```

Docker verification pending rebuild.
