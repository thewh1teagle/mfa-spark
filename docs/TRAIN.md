# Training MFA Once The CLI Works

This guide assumes the source build is already done and `mfa` runs successfully.

```bash
source ./scripts/env.sh
source .venv/bin/activate
mfa version
```

## Prepare Corpus

MFA does not read `metadata.csv` directly. It expects paired `.wav` and `.txt` files under speaker directories:

```text
data/corpus/michael/0.wav
data/corpus/michael/0.txt
data/corpus/michael/1.wav
data/corpus/michael/1.txt
```

For the `michael-he` dataset, generate that layout with:

```bash
uv run python scripts/prepare-michael-he-corpus.py
```

The script:

- reads `data/michael-he/he/metadata.csv`
- strips stress marks `ˈ` and `ˌ`
- strips punctuation
- writes normalized `.txt` files
- symlinks WAV files instead of copying audio

The matching stress-free dictionary is:

```text
data/dictionary_no_stress.txt
```

## Validate

Run validation before full training:

```bash
mfa validate data/corpus data/dictionary_no_stress.txt \
  --temporary_directory "$(pwd)/runs/michael/temp" \
  --single_speaker \
  --num_jobs "$(nproc)" \
  2>&1 | tee logs/michael-validate.log
```

Expected sanity checks for this corpus:

- `13951 sound files`
- `13951 text files`
- `1 speakers`
- no sound file read errors
- no missing features
- no missing transcriptions
- no OOV words

## Train

Use MFA's default acoustic training pipeline for the real run. Do not reuse the smoke-test overfit YAML.

```bash
mfa train data/corpus data/dictionary_no_stress.txt \
  runs/michael/models/michael_he.zip \
  --output_directory runs/michael/output \
  --temporary_directory "$(pwd)/runs/michael/temp" \
  --single_speaker \
  --num_jobs "$(nproc)" \
  --clean \
  --overwrite \
  2>&1 | tee logs/michael-train.log
```

Outputs:

- acoustic model: `runs/michael/models/michael_he.zip`
- aligned TextGrids: `runs/michael/output/`
- logs/temp files: `runs/michael/temp/`

Always pass `--temporary_directory` as an absolute path. With a relative temporary directory, MFA can create dangling SAT alignment symlinks during the final first-pass-to-final SAT step, which can make interval collection fail after training has already completed.

## Single-Speaker Training

Training on this single-speaker corpus is appropriate for forced alignment. The model is not being trained as a general speech recognizer; it only needs to place phone and word boundaries for audio where the transcript is already known.

For this dataset, a speaker-specific acoustic model is likely better than a generic model because:

- the same speaker is used for training and alignment
- the corpus has about 14k utterances and roughly 20 hours of audio
- the dictionary uses this dataset's IPA-like phone inventory
- there is no off-the-shelf MFA Hebrew model matching this exact phone set

Use `--single_speaker` for this run. It tells MFA not to spend effort modeling multiple speakers.

Limitations:

- the trained model is mainly useful for this speaker
- other voices should use a separate model or a retrained multi-speaker model
- same-speaker held-out recordings should still align well, especially if recording conditions are similar

## Notes

The transcripts in `metadata.csv` are stressed IPA-like text, but training uses stress-free text and dictionary entries. This keeps MFA phone alignment simpler. If stress timings are needed later, re-project stress from the original metadata by token position after alignment.

This GMM training path is mostly CPU-bound. CUDA support can be compiled and available while `nvidia-smi` still shows little or no activity during `mfa train`.
