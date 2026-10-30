USE StackOverflow2010;
GO
CREATE OR ALTER PROCEDURE app.GetUserByExternalId @ExternalContactId nvarchar(20)
AS
SET NOCOUNT ON;
SELECT u.Id, u.DisplayName, u.Reputation, m.ExternalContactId, m.SyncedAt
FROM dbo.CrmContactMap m
JOIN dbo.Users u ON u.Id = m.UserId
WHERE m.ExternalContactId = @ExternalContactId;
GO
