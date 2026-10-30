@{
    Title = 'Implicit conversion: _TestOld against _Test, side by side'
    Calls = @(
        @{ Label = 'known id';            Sql = "EXEC app.GetUserByExternalId_TestOld @ExternalContactId = N'CRM-00022656'"; AfterSql = "EXEC app.GetUserByExternalId_Test @ExternalContactId = N'CRM-00022656'" }
        @{ Label = 'first user';          Sql = "EXEC app.GetUserByExternalId_TestOld @ExternalContactId = N'CRM-00000001'"; AfterSql = "EXEC app.GetUserByExternalId_Test @ExternalContactId = N'CRM-00000001'" }
        @{ Label = 'lower case';          Sql = "EXEC app.GetUserByExternalId_TestOld @ExternalContactId = N'crm-00022656'"; AfterSql = "EXEC app.GetUserByExternalId_Test @ExternalContactId = N'crm-00022656'" }
        @{ Label = 'trailing space';      Sql = "EXEC app.GetUserByExternalId_TestOld @ExternalContactId = N'CRM-00022656 '"; AfterSql = "EXEC app.GetUserByExternalId_Test @ExternalContactId = N'CRM-00022656 '" }
        @{ Label = 'full-width last digit'; Sql = "DECLARE @p nvarchar(20) = N'CRM-0002265' + NCHAR(65302); EXEC app.GetUserByExternalId_TestOld @ExternalContactId = @p"; AfterSql = "DECLARE @p nvarchar(20) = N'CRM-0002265' + NCHAR(65302); EXEC app.GetUserByExternalId_Test @ExternalContactId = @p" }
        @{ Label = 'unknown id';          Sql = "EXEC app.GetUserByExternalId_TestOld @ExternalContactId = N'CRM-99999999'"; AfterSql = "EXEC app.GetUserByExternalId_Test @ExternalContactId = N'CRM-99999999'" }
    )
}
