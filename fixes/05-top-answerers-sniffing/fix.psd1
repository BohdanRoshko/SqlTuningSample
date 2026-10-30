@{
    # Each call first clears the cached plan, then runs one call to decide which plan gets cached,
    # then measures the call that has to live with that plan. That is what happens in production
    # after a restart, a statistics update, or a plan cache flush.
    Title = 'Top answerers report: cost no longer depends on which range ran first'
    Apply = @('index.sql')
    Calls = @(
        @{ Label = 'year, after a day plan'
           Setup = "EXEC sp_recompile N'app.GetTopAnswerers'; EXEC app.GetTopAnswerers @From = '2010-06-01', @To = '2010-06-02';"
           Sql   = "EXEC app.GetTopAnswerers @From = '2010-01-01', @To = '2011-01-01'" }
        @{ Label = 'month, after a day plan'
           Setup = "EXEC sp_recompile N'app.GetTopAnswerers'; EXEC app.GetTopAnswerers @From = '2010-06-01', @To = '2010-06-02';"
           Sql   = "EXEC app.GetTopAnswerers @From = '2010-03-01', @To = '2010-04-01'" }
        @{ Label = 'day, after a year plan'
           Setup = "EXEC sp_recompile N'app.GetTopAnswerers'; EXEC app.GetTopAnswerers @From = '2010-01-01', @To = '2011-01-01';"
           Sql   = "EXEC app.GetTopAnswerers @From = '2010-06-01', @To = '2010-06-02'" }
        @{ Label = 'day, own plan'
           Setup = "EXEC sp_recompile N'app.GetTopAnswerers';"
           Sql   = "EXEC app.GetTopAnswerers @From = '2009-09-14', @To = '2009-09-15'" }
        @{ Label = 'week, own plan'
           Setup = "EXEC sp_recompile N'app.GetTopAnswerers';"
           Sql   = "EXEC app.GetTopAnswerers @From = '2009-09-14', @To = '2009-09-21'" }
        @{ Label = 'year, own plan'
           Setup = "EXEC sp_recompile N'app.GetTopAnswerers';"
           Sql   = "EXEC app.GetTopAnswerers @From = '2009-01-01', @To = '2010-01-01'" }
    )
}
