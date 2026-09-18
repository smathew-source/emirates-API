-- Demo only: this intentionally fails so you can see an ADF error.
SET NOCOUNT ON;

THROW 51099, 'DEMO: ETL validation failed because a test error was raised.', 1;