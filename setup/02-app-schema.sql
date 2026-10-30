/*  Build the "application" on top of StackOverflow2010.

    This plays the part of a vendor app: the tables it added, the indexes it shipped,
    and the stored procedures it calls. The problems in it are deliberate, and they
    are the kind real systems have:

      - app.GetPostVoteCounts     no index on Votes.PostId (missing index)
      - app.GetUserProfile        index on OwnerUserId only, so every post needs a key lookup
      - app.GetUserByExternalId   nvarchar parameter against a varchar column (implicit conversion)
      - app.GetDailyPostCounts    YEAR()/MONTH() on the column (non-SARGable predicate)
      - app.GetTopAnswerers       date range report whose cached plan depends on the first call (parameter sniffing)
      - IX_Posts_LastActivityDate never read by any query, but every view and vote updates it (unused index)
      - app.SearchQuestions and app.GetTopAnswersByTag  leading-wildcard LIKE on Posts

    Safe to re-run.  */
USE StackOverflow2010;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------- Query Store: on, capturing everything, small enough for a lab ---------- */
ALTER DATABASE StackOverflow2010 SET QUERY_STORE = ON;
ALTER DATABASE StackOverflow2010 SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = ALL,
    INTERVAL_LENGTH_MINUTES = 15,
    MAX_STORAGE_SIZE_MB = 1000,
    DATA_FLUSH_INTERVAL_SECONDS = 60);
GO

IF SCHEMA_ID(N'app') IS NULL EXEC (N'CREATE SCHEMA app AUTHORIZATION dbo;');
GO

/* ---------- A table the app added: mapping from users to contacts in an external CRM ---------- */
IF OBJECT_ID(N'dbo.CrmContactMap') IS NULL
BEGIN
    CREATE TABLE dbo.CrmContactMap (
        UserId            int          NOT NULL CONSTRAINT PK_CrmContactMap PRIMARY KEY,
        ExternalContactId varchar(20)  NOT NULL,
        SyncedAt          datetime2(0) NOT NULL);

    INSERT dbo.CrmContactMap (UserId, ExternalContactId, SyncedAt)
    SELECT Id,
           'CRM-' + RIGHT('00000000' + CAST(Id AS varchar(10)), 8),
           DATEADD(SECOND, Id % 86400, CAST('2010-12-31' AS datetime2(0)))
    FROM dbo.Users;

    CREATE UNIQUE INDEX UX_CrmContactMap_ExternalContactId ON dbo.CrmContactMap (ExternalContactId);
END
GO

/* ---------- Indexes the vendor shipped ---------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Posts_OwnerUserId' AND object_id = OBJECT_ID(N'dbo.Posts'))
    CREATE INDEX IX_Posts_OwnerUserId ON dbo.Posts (OwnerUserId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Posts_ParentId' AND object_id = OBJECT_ID(N'dbo.Posts'))
    CREATE INDEX IX_Posts_ParentId ON dbo.Posts (ParentId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Posts_CreationDate' AND object_id = OBJECT_ID(N'dbo.Posts'))
    CREATE INDEX IX_Posts_CreationDate ON dbo.Posts (CreationDate);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Posts_LastActivityDate' AND object_id = OBJECT_ID(N'dbo.Posts'))
    CREATE INDEX IX_Posts_LastActivityDate ON dbo.Posts (LastActivityDate) INCLUDE (ViewCount, Score);
GO

/* ---------- Question page ---------- */
CREATE OR ALTER PROCEDURE app.GetQuestionPage @PostId int
AS
SET NOCOUNT ON;
SELECT q.Id, q.Title, q.Body, q.Score, q.ViewCount, q.AnswerCount, q.Tags, q.CreationDate, u.DisplayName
FROM dbo.Posts q
LEFT JOIN dbo.Users u ON u.Id = q.OwnerUserId
WHERE q.Id = @PostId;

SELECT a.Id, a.Body, a.Score, a.CreationDate, u.DisplayName
FROM dbo.Posts a
LEFT JOIN dbo.Users u ON u.Id = a.OwnerUserId
WHERE a.ParentId = @PostId
ORDER BY a.Score DESC, a.Id;
GO

/* ---------- Vote breakdown shown on every question page ---------- */
CREATE OR ALTER PROCEDURE app.GetPostVoteCounts @PostId int
AS
SET NOCOUNT ON;
SELECT v.VoteTypeId, vt.Name AS VoteType, COUNT(*) AS Votes
FROM dbo.Votes v
JOIN dbo.VoteTypes vt ON vt.Id = v.VoteTypeId
WHERE v.PostId = @PostId
GROUP BY v.VoteTypeId, vt.Name
ORDER BY v.VoteTypeId;
GO

/* ---------- User profile page: the user and their top questions ---------- */
CREATE OR ALTER PROCEDURE app.GetUserProfile @UserId int
AS
SET NOCOUNT ON;
SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
FROM dbo.Users u
WHERE u.Id = @UserId;

SELECT TOP (10) p.Id, p.Title, p.Score, p.CreationDate
FROM dbo.Posts p
WHERE p.OwnerUserId = @UserId
  AND p.PostTypeId = 1
ORDER BY p.Score DESC, p.Id DESC;
GO

/* ---------- CRM sync: find the local user for an external contact id ---------- */
CREATE OR ALTER PROCEDURE app.GetUserByExternalId @ExternalContactId nvarchar(20)
AS
SET NOCOUNT ON;
SELECT u.Id, u.DisplayName, u.Reputation, m.ExternalContactId, m.SyncedAt
FROM dbo.CrmContactMap m
JOIN dbo.Users u ON u.Id = m.UserId
WHERE m.ExternalContactId = @ExternalContactId;
GO

/* ---------- Search box: questions whose title contains a term ---------- */
CREATE OR ALTER PROCEDURE app.SearchQuestions @Term nvarchar(100)
AS
SET NOCOUNT ON;
SELECT TOP (50) p.Id, p.Title, p.Score, p.AnswerCount, p.CreationDate
FROM dbo.Posts p
WHERE p.PostTypeId = 1
  AND p.Title LIKE N'%' + @Term + N'%'
ORDER BY p.CreationDate DESC, p.Id DESC;
GO

/* ---------- Tag page: best answers to questions with a tag ---------- */
CREATE OR ALTER PROCEDURE app.GetTopAnswersByTag @Tag nvarchar(50)
AS
SET NOCOUNT ON;
SELECT TOP (20) a.Id AS AnswerId, q.Id AS QuestionId, q.Title, a.Score, u.DisplayName
FROM dbo.Posts q
JOIN dbo.Posts a ON a.ParentId = q.Id
LEFT JOIN dbo.Users u ON u.Id = a.OwnerUserId
WHERE q.PostTypeId = 1
  AND q.Tags LIKE N'%<' + @Tag + N'>%'
ORDER BY a.Score DESC, a.Id DESC;
GO

/* ---------- Dashboard report: posts per day for one month ---------- */
CREATE OR ALTER PROCEDURE app.GetDailyPostCounts @Year int, @Month int
AS
SET NOCOUNT ON;
SELECT CAST(p.CreationDate AS date) AS PostDate, COUNT(*) AS Posts
FROM dbo.Posts p
WHERE YEAR(p.CreationDate) = @Year
  AND MONTH(p.CreationDate) = @Month
GROUP BY CAST(p.CreationDate AS date)
ORDER BY PostDate;
GO

/* ---------- Report: top answerers in a date range (a day, a week, or a whole year) ---------- */
CREATE OR ALTER PROCEDURE app.GetTopAnswerers @From datetime, @To datetime
AS
SET NOCOUNT ON;
SELECT TOP (20) p.OwnerUserId, u.DisplayName, COUNT(*) AS Answers, SUM(p.Score) AS TotalScore
FROM dbo.Posts p
JOIN dbo.Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 2
  AND p.CreationDate >= @From
  AND p.CreationDate <  @To
GROUP BY p.OwnerUserId, u.DisplayName
ORDER BY TotalScore DESC, p.OwnerUserId;
GO

/* ---------- Writes: a page view and a vote ---------- */
CREATE OR ALTER PROCEDURE app.RecordPostView @PostId int
AS
SET NOCOUNT ON;
UPDATE dbo.Posts SET ViewCount = ViewCount + 1 WHERE Id = @PostId;
GO

CREATE OR ALTER PROCEDURE app.CastVote @PostId int, @UserId int, @VoteTypeId int
AS
SET NOCOUNT ON;
INSERT dbo.Votes (PostId, UserId, BountyAmount, VoteTypeId, CreationDate)
VALUES (@PostId, @UserId, NULL, @VoteTypeId, SYSDATETIME());

UPDATE dbo.Posts
SET Score = Score + CASE @VoteTypeId WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END
WHERE Id = @PostId
  AND @VoteTypeId IN (2, 3);
GO
