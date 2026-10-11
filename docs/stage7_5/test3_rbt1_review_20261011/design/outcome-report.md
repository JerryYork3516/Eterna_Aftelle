# RBT-1 static preparation outcome

## Actual completed work

- One metadata-only selection: 64 FIT / 40 CHECK triples, 208 distinct admitted file descriptors and 104 distinct path groups. FIT/CHECK speakers, files and paths are disjoint; all 207 speakers used by old SOR are excluded. No PCM file was read.
- Metadata selector actual child exit0, 0.775873541 seconds; outer tool 9af7c6 exit0. The fixed population is population-descriptors.json, SHA d6c07ba21e544671bdd9eae2770bd7caae97887f7d5eedb633c2ac2dc85938fd. Independent read-only outcome review passed.
- Independent static review found an actual F64 cancellation in the unexecuted row-loss reference. Equal F32 logits 2**60 with y=1 incorrectly lost log(3). Original versions were retained; root changed the evaluation to (top-y*zN)+log(denominator), preserving the defined objective and derivative.
- One 10-case stdlib synthetic fixture: actual child40121 exit0, no timeout, 0.03342275 seconds; outer tool de2e0d exit0. Parent/child completed RSS peaks summed to 54,099,968 bytes <128 MiB. Source hashes and revised contract match. Independent saved-only outcome review passed.

## What this establishes

The new RBT objective/reference, generated F32 sharing example, source-span mapping reference, integer mechanism gate, and fixed metadata partition are ready for a matching isolated implementation. The toy sharing example does not validate the actual source constructor. Metadata exclusion is not actual PCM, activity, producer or full source identity validation.

There has been no real source construction, capture, frontend, model forward, optimizer, training, solver, threshold grid, DEV, clean/actual-ready/native budget or physical human acceptance execution. The most important source-attribution problem remains unresolved. No old rejected candidate was changed to PASS.

## Next concrete work

Implement one new B/E/N source constructor and matching fresh-zero 3617-delta temporal-J RBT entry with exact fixed normalization/checkpoint lineage. Bind original causal source rows, loss and 40-triple common-negative-peak criterion. Freeze resource/publication/cleanup/actual exits first. The proposed 1800-second / aggregate 2-GiB / retained 64-MiB trial has no execution authorization yet; static PASS does not grant it. See minimum-matching-entry-freeze-plan.md.

All original product gates stay intact. Stage7 isolation PASS; Test3 BLOCKED; tau=null. No recording or user action is required at this stage.
