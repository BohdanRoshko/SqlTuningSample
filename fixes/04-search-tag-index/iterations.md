# Fix 04: iteration log

Each row is one candidate, measured with `tools/Test-Fix.ps1` against the original
(median of 5 warm runs, logical reads). Rows identical in every case.

| Candidate | search 'memory leak' | search, no match | tag 'c#' | tag 'haskell' | Kept |
|---|---|---|---|---|---|
| Original (vendor indexes) | 610,002 | 21,939,183 | 2,742,919 | 837,662 | |
| 1. New IX_Posts_PostTypeId_CreationDate INCLUDE (Title, Tags, Score, AnswerCount) | 640 | 14,186 | 2,469,754 | 43,570 | yes |
| 2. Plus INCLUDE (Score, OwnerUserId) on the vendor's IX_Posts_ParentId | 640 | 14,186 | 426,337 | 20,450 | yes |

Candidate 1 fixed search but left the tag page for big tags almost where it was:
the cost had moved to key lookups on the answers. Candidate 2 removed them.
The question page, which also uses IX_Posts_ParentId, stayed at 66 reads.

A first trial of candidate 2 (3 runs, index added on top of candidate 1) read 20,672 pages for c#
with a hash join. The clean rerun from the original indexes, in fix.result.json, compiled a
nested-loop plan for c# that reads 426,337 pages. Elapsed is about the same either way (1.5 s and
1.7 s), so the report uses the clean rerun.

What is left: the tag page still reads every question's Tags with LIKE '%<tag>%',
about 1.3 seconds of CPU per call. Only a tag table or full-text search removes that,
and both change the procedure, so it goes to the vendor.
