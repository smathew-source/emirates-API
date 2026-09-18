-- SQLCMD mode. Replace the factory name below, then run in BOTH databases
-- as the configured Microsoft Entra SQL administrator.
:setvar FactoryName "REPLACE_WITH_FACTORY_NAME"
IF DATABASE_PRINCIPAL_ID(N'$(FactoryName)') IS NULL
 CREATE USER [$(FactoryName)] FROM EXTERNAL PROVIDER;
GO
IF OBJECT_ID('dbo.vPatientExtract','V') IS NOT NULL
 EXEC(N'GRANT SELECT ON OBJECT::dbo.vPatientExtract TO [$(FactoryName)]');
IF OBJECT_ID('stg.PatientExtract','U') IS NOT NULL
BEGIN
 EXEC(N'GRANT INSERT ON OBJECT::stg.PatientExtract TO [$(FactoryName)]');
 EXEC(N'GRANT EXECUTE ON OBJECT::etl.ResetStage TO [$(FactoryName)]');
 EXEC(N'GRANT EXECUTE ON OBJECT::etl.LoadPatientWarehouse TO [$(FactoryName)]');
END;
GO
