#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
from pathlib import Path


PUNCTUATION = ',.!?;:()[]{}"“”׳״…'
STRESS_MARKS = {'ˈ', 'ˌ'}


def normalize_transcript(text: str) -> str:
    table = str.maketrans({c: ' ' for c in PUNCTUATION})
    text = text.translate(table)
    text = ''.join(ch for ch in text if ch not in STRESS_MARKS)
    return ' '.join(text.split())


def prepare_corpus(metadata: Path, wav_dir: Path, output_dir: Path, copy_audio: bool) -> tuple[int, int]:
    speaker_dir = output_dir / 'michael'
    if speaker_dir.exists():
        shutil.rmtree(speaker_dir)
    speaker_dir.mkdir(parents=True, exist_ok=True)

    written = 0
    missing_wavs = 0
    for raw_line in metadata.read_text(encoding='utf-8').splitlines():
        if not raw_line.strip():
            continue
        utterance_id, transcript = raw_line.split('|', 1)
        source_wav = wav_dir / f'{utterance_id}.wav'
        if not source_wav.exists():
            missing_wavs += 1
            continue

        normalized = normalize_transcript(transcript)
        (speaker_dir / f'{utterance_id}.txt').write_text(normalized + '\n', encoding='utf-8')

        target_wav = speaker_dir / f'{utterance_id}.wav'
        if copy_audio:
            shutil.copy2(source_wav, target_wav)
        else:
            os.symlink(source_wav.resolve(), target_wav)
        written += 1

    return written, missing_wavs


def main() -> int:
    parser = argparse.ArgumentParser(description='Prepare the michael-he dataset for MFA.')
    parser.add_argument('--metadata', type=Path, default=Path('data/michael-he/he/metadata.csv'))
    parser.add_argument('--wav-dir', type=Path, default=Path('data/michael-he/he/wav'))
    parser.add_argument('--output-dir', type=Path, default=Path('data/corpus'))
    parser.add_argument('--copy-audio', action='store_true', help='Copy WAVs instead of symlinking them.')
    args = parser.parse_args()

    written, missing_wavs = prepare_corpus(args.metadata, args.wav_dir, args.output_dir, args.copy_audio)
    print(f'wrote {written} utterances to {args.output_dir / "michael"}')
    if missing_wavs:
        print(f'missing wavs: {missing_wavs}')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
