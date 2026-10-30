/*  Back to the indexes as the vendor shipped them.  */
USE StackOverflow2010;
GO
DROP INDEX IF EXISTS IX_Posts_PostTypeId_CreationDate ON dbo.Posts;
GO
CREATE INDEX IX_Posts_ParentId ON dbo.Posts (ParentId)
WITH (DROP_EXISTING = ON);
GO
