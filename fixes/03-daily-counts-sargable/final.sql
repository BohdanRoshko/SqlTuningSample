/*  Fix 03: let the month report seek instead of scan.

    YEAR(CreationDate) = @Year AND MONTH(CreationDate) = @Month hides the column inside
    functions, so SQL Server had to compute them for all 3.7 million posts.
    A plain range on the column, from the first day of the month to the first day of the next,
    selects exactly the same rows and can seek IX_Posts_CreationDate.  */
USE StackOverflow2010;
GO
CREATE OR ALTER PROCEDURE app.GetDailyPostCounts @Year int, @Month int
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
DROP PROCEDURE IF EXISTS app.GetDailyPostCounts_TestOld;
DROP PROCEDURE IF EXISTS app.GetDailyPostCounts_Test;
GO
