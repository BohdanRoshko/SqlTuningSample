@{
    Title = 'Vote counts: seek the votes of one post instead of scanning all of them'
    Apply = @('index.sql')
    Calls = @(
        @{ Label = 'post with most votes (4,504)'; Sql = 'EXEC app.GetPostVoteCounts @PostId = 194812' }
        @{ Label = 'post with 10 votes';           Sql = 'EXEC app.GetPostVoteCounts @PostId = 1000080' }
        @{ Label = 'post 4';                       Sql = 'EXEC app.GetPostVoteCounts @PostId = 4' }
        @{ Label = 'post with no votes';           Sql = 'EXEC app.GetPostVoteCounts @PostId = 2000008' }
        # The new index costs every vote insert a little. Measured inside a transaction that rolls back.
        @{ Label = 'write: cast a vote (rolled back)'; Sql = 'BEGIN TRAN; EXEC app.CastVote @PostId = 1000080, @UserId = 22656, @VoteTypeId = 2; ROLLBACK;' }
    )
}
