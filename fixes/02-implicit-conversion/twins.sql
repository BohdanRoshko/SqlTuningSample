/*  Test twins for fix 02, side by side with the live procedure.
    _TestOld is the live body, unchanged. _Test is the candidate.
    Neither is called by the app. final.sql drops both.  */
USE StackOverflow2010;
GO
CREATE OR ALTER PROCEDURE app.GetUserByExternalId_TestOld @ExternalContactId nvarchar(20)
AS
SET NOCOUNT ON;
SELECT u.Id, u.DisplayName, u.Reputation, m.ExternalContactId, m.SyncedAt
FROM dbo.CrmContactMap m
JOIN dbo.Users u ON u.Id = m.UserId
WHERE m.ExternalContactId = @ExternalContactId;
GO
CREATE OR ALTER PROCEDURE app.GetUserByExternalId_Test @ExternalContactId nvarchar(20)
AS
SET NOCOUNT ON;
SELECT u.Id, u.DisplayName, u.Reputation, m.ExternalContactId, m.SyncedAt
FROM dbo.CrmContactMap m
JOIN dbo.Users u ON u.Id = m.UserId
WHERE m.ExternalContactId = CAST(@ExternalContactId AS varchar(20))         -- seek on the varchar index
  AND CAST(m.ExternalContactId AS nvarchar(20)) = @ExternalContactId;      -- the original test, on the one row found
GO
