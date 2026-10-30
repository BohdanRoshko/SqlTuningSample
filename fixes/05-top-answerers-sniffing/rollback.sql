/*  Back to the index as fix 04 left it.  */
USE StackOverflow2010;
GO
CREATE INDEX IX_Posts_PostTypeId_CreationDate ON dbo.Posts (PostTypeId, CreationDate)
INCLUDE (Title, Tags, Score, AnswerCount)
WITH (DROP_EXISTING = ON, DATA_COMPRESSION = PAGE, SORT_IN_TEMPDB = ON);
GO
