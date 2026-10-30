/*  Puts the index back exactly as the vendor shipped it.  */
USE StackOverflow2010;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Posts') AND name = N'IX_Posts_LastActivityDate')
    CREATE INDEX IX_Posts_LastActivityDate ON dbo.Posts (LastActivityDate) INCLUDE (ViewCount, Score);
GO
