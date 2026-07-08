# Build Timings

Timing notes for the DGX Spark source build.

## Native FST Stack

- OpenFst + OpenGrm NGram + Baum-Welch combined stage:
  - Started: 2026-07-08 01:28:29 Asia/Tel_Aviv, from `logs/build.log`
  - Ended: approximately 2026-07-08 01:34:xx Asia/Tel_Aviv, after Baum-Welch install completed
  - Duration: approximately 6 minutes
  - Result: completed successfully into `./opt`

Further stages will be appended as they complete.

## Kaldi Local OpenBLAS

- Started: 2026-07-08 01:39:30 Asia/Tel_Aviv
- Ended: 2026-07-08 01:40:07 Asia/Tel_Aviv
- Duration: 37 seconds
- Result: completed successfully into `src/kaldi/tools/OpenBLAS/install`

## Kaldi CUDA Source Build

- Main CUDA build started: 2026-07-08 01:42:18 Asia/Tel_Aviv
- Successful final resume ended: 2026-07-08 01:47:02 Asia/Tel_Aviv
- Wall time across active build/resume attempts: approximately 4 minutes 44 seconds
- Final successful resume duration: 12 seconds
- Result: completed successfully with CUDA 13.0 and GB10 `sm_121` patches

## Kaldi CUDA Runtime Tests

- Command: `cd src/kaldi/src/cudamatrix && make test -j$(nproc)`
- Duration: approximately 1 minute 19 seconds
- Result: completed successfully
- Passed targets: `cu-vector-test`, `cu-matrix-test`, `cu-math-test`, `cu-test`, `cu-sp-matrix-test`, `cu-packed-matrix-test`, `cu-tp-matrix-test`, `cu-block-matrix-test`, `cu-matrix-speed-test`, `cu-vector-speed-test`, `cu-sp-matrix-speed-test`, `cu-array-test`, `cu-sparse-matrix-test`, `cu-device-test`, `cu-rand-speed-test`, `cu-compressed-matrix-test`

## OpenFst Extension Rebuild For Pynini

- Command: rebuild OpenFst 1.8.4 with `--enable-far --enable-pdt --enable-mpdt`
- Duration: 40 seconds
- Result: completed successfully into `./opt`

## Pynini Source Build

- Command: `uv pip install -v --no-build-isolation ./src/pynini-2.1.7`
- Duration: 78 seconds
- Result: completed successfully against local `./opt` OpenFst

## MFA Source Install

- Command: `uv pip install -e src/Montreal-Forced-Aligner`
- Duration: approximately 10 seconds
- Result: installed MFA 3.4.0 source checkout

## Kalpy Source Build

- Command: `uv pip install -v -e src/kalpy`
- Successful build duration: 200 seconds
- Result: installed `kalpy-kaldi==0.10.3` against local CUDA-enabled Kaldi/OpenFst

## Kaldi nnet2 Rebuild For Kalpy

- Command: `cd src/kaldi/src/nnet2 && make depend && make`
- Duration: 7 seconds
- Result: rebuilt `libkaldi-nnet2.so` with `combine-nnet-a.o` and `shrink-nnet.o`

## MFA Sample Validation And Overfit

- `mfa validate` on replicated `plans/sample` corpus:
  - Duration: 84.545 seconds
  - Result: completed successfully, including MFA's monophone training smoke test
- `mfa train` overfit model on 24 replicated sample utterances:
  - Duration: 37 seconds wall time
  - Result: saved `runs/sample-overfit/models/sample_overfit.zip` and 24 TextGrids in `runs/sample-overfit/output`
- `mfa align` on the original single sample:
  - Duration: 13 seconds wall time
  - Result: saved `runs/sample-original/output/speaker1/01.TextGrid`
