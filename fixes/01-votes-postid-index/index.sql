/*  Fix 01: index Votes by PostId.
    app.GetPostVoteCounts runs on every question page and scanned all of Votes
    (10 million rows) to count the votes of one post.
    VoteTypeId is the second key, so the GROUP BY reads the rows already in order.
    PAGE compression matches the rest of the database.
    Express and Standard cannot build indexes ONLINE, so run this in a quiet window.  */
USE StackOverflow2010;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Votes') AND name = N'IX_Votes_PostId_VoteTypeId')
    CREATE INDEX IX_Votes_PostId_VoteTypeId ON dbo.Votes (PostId, VoteTypeId)
    WITH (DATA_COMPRESSION = PAGE, SORT_IN_TEMPDB = ON);
GO
