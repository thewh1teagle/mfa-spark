# Filtering Alignments By Confidence

After `mfa train` (or `mfa align`) completes, MFA stores per-utterance quality
scores in its SQLite database. Use them to drop the worst-aligned utterances and
keep the cleanest N% for downstream training (TTS, phoneme ASR, etc.).

## Where the scores live

SQLite DB inside the temporary directory:

```
runs/michael/temp/corpus/corpus.db
```

Relevant columns on the `utterance` table:

- `alignment_log_likelihood` — total acoustic log-likelihood of the alignment.
  More negative = worse fit. **Divide by `num_frames`** to compare across
  utterances of different length (raw totals penalize long utterances).
- `duration_deviation` — how far phone durations stray from the model's
  expectation. Higher = more suspect. Good secondary flag.
- `num_frames`, `text` — for context.

Primary signal: **per-frame log-likelihood** = `alignment_log_likelihood / num_frames`.
Lower (more negative) is worse.

## Keep the best 90% (drop bottom 10%)

The cutoff is the 10th-percentile of per-frame log-likelihood. Compute it
dynamically (do not hardcode — it changes per corpus/model). For the
`michael-he` run it was about `-0.159`.

List the utterance IDs to KEEP:

```bash
DB=runs/michael/temp/corpus/corpus.db
sqlite3 "$DB" "
WITH scored AS (
  SELECT id,
         alignment_log_likelihood*1.0/nullif(num_frames,0) AS ll_pf
  FROM utterance
  WHERE alignment_log_likelihood IS NOT NULL AND num_frames > 0
),
cutoff AS (
  SELECT ll_pf AS thr FROM scored
  ORDER BY ll_pf ASC
  LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.10 AS INT) FROM scored)
)
SELECT id FROM scored, cutoff WHERE ll_pf >= thr ORDER BY id;
" > runs/michael/keep_ids.txt
```

Change `0.10` to filter a different fraction (e.g. `0.20` for the best 80%).

List the worst utterances to inspect (bottom 10%), most-suspect first:

```bash
sqlite3 -header -column "$DB" "
SELECT id, num_frames AS fr,
       round(alignment_log_likelihood/nullif(num_frames,0),3) AS ll_pf,
       round(duration_deviation,2) AS dur_dev,
       substr(text,1,50) AS text
FROM utterance
WHERE alignment_log_likelihood IS NOT NULL AND num_frames > 0
ORDER BY ll_pf ASC
LIMIT 50;"
```

## Build a filtered corpus

Copy/symlink only the kept utterances' TextGrids (and wavs/txts if rebuilding a
dataset) into a new directory:

```bash
OUT=runs/michael/output/michael
DST=runs/michael/filtered
mkdir -p "$DST"
while read id; do
  ln -sf "$(pwd)/$OUT/$id.TextGrid" "$DST/$id.TextGrid"
done < runs/michael/keep_ids.txt
echo "kept $(ls "$DST" | wc -l) TextGrids"
```

## Notes / caveats

- **Per-frame LL, not raw LL** — always normalize by `num_frames`, or long
  utterances dominate the "worst" list unfairly.
- **Very short utterances** score low simply for lack of acoustic context; a low
  score there is not necessarily a misalignment. Cross-check with
  `duration_deviation` — utterances flagged by *both* signals are the real
  misalignments.
- The raw per-phone `phone_interval.phone_goodness` field is an **uncalibrated
  acoustic likelihood**, not a 0-1 confidence, and is confounded by phone
  identity/duration. Do not threshold on it directly; if needed, z-score it
  within each phone type first.
- Percentile cutoffs are corpus/model specific — recompute after any retrain.
- The DB is under `--temporary_directory`; if that dir is cleaned, re-run
  `mfa align` (fast — inference only) to regenerate scores without retraining.
