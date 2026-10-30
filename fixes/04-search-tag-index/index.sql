/*  Fix 04: a narrow copy of the question columns that search and the tag page read.

    app.SearchQuestions and app.GetTopAnswersByTag filter with LIKE '%term%'.
    A leading wildcard can never seek, so both read every question. Today they read them
    from the clustered index, which carries the full Body of every post: about 6.7 GB.

    This index holds only what the two procedures need. They still scan, but they scan
    a small index instead of the whole table, and search can stop after its first 50 hits
    because the index is already in CreationDate order.

    The real fix is full-text search or a tag table. That changes results, so it is a vendor decision.  */
USE StackOverflow2010;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Posts') AND name = N'IX_Posts_PostTypeId_CreationDate')
    CREATE INDEX IX_Posts_PostTypeId_CreationDate ON dbo.Posts (PostTypeId, CreationDate)
    INCLUDE (Title, Tags, Score, AnswerCount)
    WITH (DATA_COMPRESSION = PAGE, SORT_IN_TEMPDB = ON);
GO

/*  Second part. The tag page also reads the answers of every matching question.
    IX_Posts_ParentId found them, but each answer then needed a key lookup for Score and
    OwnerUserId. For a big tag like c# that was about 2.4 million reads after part one.
    Adding those two columns to the vendor's index removes the lookups.
    Cost: Score changes on every up or down vote, so each vote on an answer now also
    updates this index. See fix 06 for the write cost on votes after all changes.  */
CREATE INDEX IX_Posts_ParentId ON dbo.Posts (ParentId)
INCLUDE (Score, OwnerUserId)
WITH (DROP_EXISTING = ON, DATA_COMPRESSION = PAGE, SORT_IN_TEMPDB = ON);
GO
