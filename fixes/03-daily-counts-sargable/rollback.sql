USE StackOverflow2010;
GO
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
