@{
    Title = 'Month report: live procedure before and after final.sql'
    Apply = @('final.sql')
    Calls = @(
        @{ Label = '2008-07 (data starts 31st)'; Sql = 'EXEC app.GetDailyPostCounts @Year = 2008, @Month = 7';  AfterSql = 'EXEC app.GetDailyPostCounts @Year = 2008, @Month = 7' }
        @{ Label = '2008-08';                    Sql = 'EXEC app.GetDailyPostCounts @Year = 2008, @Month = 8';  AfterSql = 'EXEC app.GetDailyPostCounts @Year = 2008, @Month = 8' }
        @{ Label = '2009-02 (28 days)';          Sql = 'EXEC app.GetDailyPostCounts @Year = 2009, @Month = 2';  AfterSql = 'EXEC app.GetDailyPostCounts @Year = 2009, @Month = 2' }
        @{ Label = '2010-06';                    Sql = 'EXEC app.GetDailyPostCounts @Year = 2010, @Month = 6';  AfterSql = 'EXEC app.GetDailyPostCounts @Year = 2010, @Month = 6' }
        @{ Label = '2010-12 (last month)';       Sql = 'EXEC app.GetDailyPostCounts @Year = 2010, @Month = 12'; AfterSql = 'EXEC app.GetDailyPostCounts @Year = 2010, @Month = 12' }
        @{ Label = '2011-01 (no data)';          Sql = 'EXEC app.GetDailyPostCounts @Year = 2011, @Month = 1';  AfterSql = 'EXEC app.GetDailyPostCounts @Year = 2011, @Month = 1' }
        @{ Label = 'month 13 (invalid)';         Sql = 'EXEC app.GetDailyPostCounts @Year = 2010, @Month = 13'; AfterSql = 'EXEC app.GetDailyPostCounts @Year = 2010, @Month = 13' }
    )
}
