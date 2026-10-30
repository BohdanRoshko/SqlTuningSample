/*  Fix 05: make the top answerers report cheap for every date range, so the cached plan stops mattering.

    The report filters answers by a CreationDate range and needs OwnerUserId and Score.
    Before, the only date index was IX_Posts_CreationDate, with no other columns.
    For a one-day range the optimizer seeks it and looks up each row in the clustered index.
    That plan is cached. When the next call asks for a whole year, it reuses the plan and does
    about a million lookups. In the workload the worst call read 11.3 million pages and took 13.8 s.

    Fix 04 already added IX_Posts_PostTypeId_CreationDate. Adding OwnerUserId to its INCLUDE list
    (Score is already there) covers the report. Every range is now one seek and one range read,
    whichever plan was compiled first.  */
USE StackOverflow2010;
GO
CREATE INDEX IX_Posts_PostTypeId_CreationDate ON dbo.Posts (PostTypeId, CreationDate)
INCLUDE (Title, Tags, Score, AnswerCount, OwnerUserId)
WITH (DROP_EXISTING = ON, DATA_COMPRESSION = PAGE, SORT_IN_TEMPDB = ON);
GO
