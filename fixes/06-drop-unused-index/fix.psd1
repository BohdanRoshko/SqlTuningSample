@{
    # Writes run inside a transaction that rolls back, so the data stays the same between runs.
    Title = 'Drop the unused index: page views and votes stop maintaining it'
    Apply = @('drop.sql')
    Calls = @(
        @{ Label = 'write: record a page view';  Sql = 'BEGIN TRAN; EXEC app.RecordPostView @PostId = 1000080; ROLLBACK;' }
        @{ Label = 'write: cast an up-vote';     Sql = 'BEGIN TRAN; EXEC app.CastVote @PostId = 1000080, @UserId = 22656, @VoteTypeId = 2; ROLLBACK;' }
    )
}
