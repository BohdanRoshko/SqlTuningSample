@{
    Title = 'Search and tag pages: scan a narrow index, not the whole Posts table'
    Apply = @('index.sql')
    Calls = @(
        @{ Label = "search 'linq'";          Sql = "EXEC app.SearchQuestions @Term = N'linq'" }
        @{ Label = "search 'memory leak'";   Sql = "EXEC app.SearchQuestions @Term = N'memory leak'" }
        @{ Label = "search 'unit test'";     Sql = "EXEC app.SearchQuestions @Term = N'unit test'" }
        @{ Label = "search, no match";       Sql = "EXEC app.SearchQuestions @Term = N'qqzzxx'" }
        @{ Label = "tag 'sql-server'";       Sql = "EXEC app.GetTopAnswersByTag @Tag = N'sql-server'" }
        @{ Label = "tag 'c#'";               Sql = "EXEC app.GetTopAnswersByTag @Tag = N'c#'" }
        @{ Label = "tag 'haskell'";          Sql = "EXEC app.GetTopAnswersByTag @Tag = N'haskell'" }
        @{ Label = "tag 'delphi'";           Sql = "EXEC app.GetTopAnswersByTag @Tag = N'delphi'" }
    )
}
