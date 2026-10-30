/*  Test twins for fix 03. _TestOld is the live body, unchanged. _Test is the candidate.  */
USE StackOverflow2010;
GO
CREATE OR ALTER PROCEDURE app.GetDailyPostCounts_TestOld @Year int, @Month int
AS
SET NOCOUNT ON;
SELECT CAST(p.CreationDate AS date) AS PostDate, COUNT(*) AS Posts
FROM dbo.Posts p
WHERE YEAR(p.CreationDate) = @Year
  AND MONTH(p.CreationDate) = @Month
GROUP BY CAST(p.CreationDate AS date)
ORDER BY PostDate;
GO
CREATE OR ALTER PROCEDURE app.GetDailyPostCounts_Test @Year int, @Month int
AS
SET NOCOUNT ON;
-- An invalid year or month leaves @From NULL, so the query returns no rows, as before, instead of an error.
DECLARE @From datetime = CASE WHEN @Month BETWEEN 1 AND 12 AND @Year BETWEEN 1753 AND 9998
                              THEN DATEFROMPARTS(@Year, @Month, 1) END;
SELECT CAST(p.CreationDate AS date) AS PostDate, COUNT(*) AS Posts
FROM dbo.Posts p
WHERE p.CreationDate >= @From
  AND p.CreationDate <  DATEADD(MONTH, 1, @From)
GROUP BY CAST(p.CreationDate AS date)
ORDER BY PostDate;
GO
