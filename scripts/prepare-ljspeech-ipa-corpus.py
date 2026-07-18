#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import unicodedata
from pathlib import Path


PUNCTUATION = ',.!?;:()[]{}"“”‘’…—'
STRESS_MARKS = {'ˈ', 'ˌ'}

# Keep conventional English affricates and diphthongs as single acoustic phones.
# Long vowels and syllabic consonants are assembled below from their modifiers.
MULTI_CHARACTER_PHONES = tuple(
    sorted(
        {
            'tʃ',
            'dʒ',
            'aɪ',
            'aʊ',
            'eɪ',
            'oʊ',
            'ɔɪ',
        },
        key=len,
        reverse=True,
    )
)
PHONE_MODIFIERS = {'ː', '̩'}


def normalize_transcript(text: str) -> str:
    text = unicodedata.normalize('NFC', text)
    text = ''.join(ch for ch in text if ch not in STRESS_MARKS)
    text = text.translate(str.maketrans({ch: ' ' for ch in PUNCTUATION}))
    return ' '.join(text.split())


def split_phones(token: str) -> list[str]:
    phones: list[str] = []
    index = 0
    while index < len(token):
        matched = next(
            (phone for phone in MULTI_CHARACTER_PHONES if token.startswith(phone, index)),
            None,
        )
        if matched is not None:
            phones.append(matched)
            index += len(matched)
            continue

        character = token[index]
        if character.isspace():
            index += 1
            continue
        if character in PHONE_MODIFIERS or unicodedata.combining(character):
            if not phones:
                raise ValueError(f'phone modifier {character!r} has no base in {token!r}')
            phones[-1] += character
        else:
            phones.append(character)
        index += 1
    return phones


def prepare_corpus(
    metadata: Path,
    wav_dir: Path,
    output_dir: Path,
    dictionary_path: Path,
    copy_audio: bool,
) -> tuple[int, int, int]:
    speaker_dir = output_dir / 'ljspeech'
    if speaker_dir.exists():
        shutil.rmtree(speaker_dir)
    speaker_dir.mkdir(parents=True, exist_ok=True)

    pronunciations: dict[str, tuple[str, ...]] = {}
    written = 0
    missing_wavs = 0

    for line_number, raw_line in enumerate(
        metadata.read_text(encoding='utf-8').splitlines(), 1
    ):
        if not raw_line.strip():
            continue
        fields = raw_line.split('|')
        if len(fields) != 3:
            raise ValueError(
                f'{metadata}:{line_number}: expected 3 pipe-separated fields, got {len(fields)}'
            )
        utterance_id, _orthography, ipa = fields
        source_wav = wav_dir / f'{utterance_id}.wav'
        if not source_wav.exists():
            missing_wavs += 1
            continue

        normalized = normalize_transcript(ipa)
        if not normalized:
            raise ValueError(f'{metadata}:{line_number}: empty normalized IPA transcript')

        for token in normalized.split():
            pronunciation = tuple(split_phones(token))
            previous = pronunciations.setdefault(token, pronunciation)
            if previous != pronunciation:
                raise ValueError(
                    f'inconsistent pronunciation for {token!r}: {previous!r} vs {pronunciation!r}'
                )

        (speaker_dir / f'{utterance_id}.txt').write_text(
            normalized + '\n', encoding='utf-8'
        )
        target_wav = speaker_dir / f'{utterance_id}.wav'
        if copy_audio:
            shutil.copy2(source_wav, target_wav)
        else:
            os.symlink(source_wav.resolve(), target_wav)
        written += 1

    dictionary_path.parent.mkdir(parents=True, exist_ok=True)
    with dictionary_path.open('w', encoding='utf-8') as dictionary:
        for token in sorted(pronunciations):
            dictionary.write(f'{token} {" ".join(pronunciations[token])}\n')

    return written, missing_wavs, len(pronunciations)


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Prepare stress-free LJSpeech IPA transcripts and dictionary for MFA.'
    )
    parser.add_argument(
        '--metadata',
        type=Path,
        default=Path('data/ljspeech/metadata-v1.csv'),
    )
    parser.add_argument(
        '--wav-dir',
        type=Path,
        default=Path('data/ljspeech/wavs'),
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=Path('data/corpus'),
    )
    parser.add_argument(
        '--dictionary',
        type=Path,
        default=Path('data/ljspeech_dictionary_no_stress.txt'),
    )
    parser.add_argument(
        '--copy-audio',
        action='store_true',
        help='Copy WAVs instead of symlinking them.',
    )
    args = parser.parse_args()

    written, missing_wavs, dictionary_entries = prepare_corpus(
        args.metadata,
        args.wav_dir,
        args.output_dir,
        args.dictionary,
        args.copy_audio,
    )
    print(f'wrote {written} utterances to {args.output_dir / "ljspeech"}')
    print(f'wrote {dictionary_entries} entries to {args.dictionary}')
    if missing_wavs:
        print(f'missing wavs: {missing_wavs}')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
