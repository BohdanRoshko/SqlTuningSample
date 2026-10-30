/*  Fix 02: stop converting every CrmContactMap row to nvarchar.

    The column is varchar(20). The parameter is nvarchar(20), which is what .NET sends.
    nvarchar wins the type contest, so SQL Server converted the column, row by row,
    and scanned the whole index instead of seeking one key.

    The new WHERE converts the parameter once and seeks. Then it re-checks the found row
    with the original nvarchar comparison. So an odd input, for example a full-width digit
    that best-fit maps to a plain digit, still cannot match a row the old code would not match.
    The signature stays the same, so the app does not change.  */
USE StackOverflow2010;
GO
CREATE OR ALTER PROCEDURE app.GetUserByExternalId @ExternalContactId nvarchar(20)
AS
SET NOCOUNT ON;
SELECT u.Id, u.DisplayName, u.Reputation, m.ExternalContactId, m.SyncedAt
FROM dbo.CrmContactMap m
JOIN dbo.Users u ON u.Id = m.UserId
WHERE m.ExternalContactId = CAST(@ExternalContactId AS varchar(20))
  AND CAST(m.ExternalContactId AS nvarchar(20)) = @ExternalContactId;
GO
DROP PROCEDURE IF EXISTS app.GetUserByExternalId_TestOld;
DROP PROCEDURE IF EXISTS app.GetUserByExternalId_Test;
GO
