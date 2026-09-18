-- Run in PatientWarehouse. Re-running setup does not drop existing data.
SET XACT_ABORT ON;
GO
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg AUTHORIZATION dbo');
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw AUTHORIZATION dbo');
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl AUTHORIZATION dbo');
GO
IF OBJECT_ID('stg.PatientExtract','U') IS NULL
CREATE TABLE stg.PatientExtract (
 PatientId int NOT NULL, GivenName nvarchar(50) NOT NULL,
 FamilyName nvarchar(50) NOT NULL, DateOfBirth date NOT NULL, City nvarchar(80) NOT NULL,
 EncounterId int NULL, EncounterDate date NULL, DepartmentId int NULL,
 DepartmentName nvarchar(80) NULL, CostGBP decimal(12,2) NULL
);
IF OBJECT_ID('dw.DimPatient','U') IS NULL
CREATE TABLE dw.DimPatient (
 PatientKey int IDENTITY PRIMARY KEY, PatientId int NOT NULL UNIQUE,
 GivenName nvarchar(50) NOT NULL, FamilyName nvarchar(50) NOT NULL,
 DateOfBirth date NOT NULL, City nvarchar(80) NOT NULL
);
IF OBJECT_ID('dw.DimDepartment','U') IS NULL
CREATE TABLE dw.DimDepartment (
 DepartmentKey int IDENTITY PRIMARY KEY, DepartmentId int NOT NULL UNIQUE,
 DepartmentName nvarchar(80) NOT NULL
);
IF OBJECT_ID('dw.DimDate','U') IS NULL
CREATE TABLE dw.DimDate (
 DateKey int PRIMARY KEY, CalendarDate date NOT NULL UNIQUE,
 CalendarYear smallint NOT NULL, CalendarMonth tinyint NOT NULL,
 DayOfMonth tinyint NOT NULL
);
IF OBJECT_ID('dw.FactPatientEncounter','U') IS NULL
CREATE TABLE dw.FactPatientEncounter (
 EncounterKey bigint IDENTITY PRIMARY KEY, EncounterId int NOT NULL UNIQUE,
 PatientKey int NOT NULL REFERENCES dw.DimPatient(PatientKey),
 DepartmentKey int NOT NULL REFERENCES dw.DimDepartment(DepartmentKey),
 DateKey int NOT NULL REFERENCES dw.DimDate(DateKey),
 EncounterCount tinyint NOT NULL DEFAULT 1 CHECK (EncounterCount=1),
 CostGBP decimal(12,2) NOT NULL CHECK (CostGBP>=0)
);
IF OBJECT_ID('etl.LoadAudit','U') IS NULL
CREATE TABLE etl.LoadAudit (
 RunId uniqueidentifier PRIMARY KEY, LoadedAtUTC datetime2 NOT NULL,
 ExtractRows int NOT NULL, PatientsInExtract int NOT NULL,
 EncountersInExtract int NOT NULL, CostGBP decimal(18,2) NOT NULL
);
GO
CREATE OR ALTER PROCEDURE etl.ResetStage
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 TRUNCATE TABLE stg.PatientExtract;
END;
GO
CREATE OR ALTER PROCEDURE etl.LoadPatientWarehouse
 @RunId uniqueidentifier,
 @ExpectedRows int
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  IF @ExpectedRows IS NULL OR @ExpectedRows <= 0
     OR (SELECT COUNT(*) FROM stg.PatientExtract) <> @ExpectedRows
   THROW 51000, 'Empty or incomplete extract; warehouse load stopped.', 1;
  IF EXISTS (SELECT EncounterId FROM stg.PatientExtract WHERE EncounterId IS NOT NULL
             GROUP BY EncounterId HAVING COUNT(*)>1)
   THROW 51001, 'Duplicate encounter identifiers.', 1;
  IF EXISTS (SELECT 1 FROM stg.PatientExtract WHERE
     DateOfBirth > CONVERT(date,SYSUTCDATETIME()) OR
     (EncounterId IS NOT NULL AND (EncounterDate IS NULL OR DepartmentId IS NULL
      OR DepartmentName IS NULL OR CostGBP IS NULL OR CostGBP<0 OR EncounterDate<DateOfBirth)))
   THROW 51002, 'Invalid patient or encounter data.', 1;

  SELECT DISTINCT PatientId,GivenName,FamilyName,DateOfBirth,City INTO #Patients
  FROM stg.PatientExtract;
  IF EXISTS (SELECT PatientId FROM #Patients GROUP BY PatientId HAVING COUNT(*)>1)
   THROW 51003, 'Conflicting patient attributes.', 1;
  SELECT DISTINCT DepartmentId,DepartmentName INTO #Departments
  FROM stg.PatientExtract WHERE DepartmentId IS NOT NULL;
  IF EXISTS (SELECT DepartmentId FROM #Departments GROUP BY DepartmentId HAVING COUNT(*)>1)
   THROW 51004, 'Conflicting department attributes.', 1;

  -- Type 1 dimensions: corrections replace current attributes, keys stay stable.
  UPDATE d SET GivenName=s.GivenName,FamilyName=s.FamilyName,
    DateOfBirth=s.DateOfBirth,City=s.City
  FROM dw.DimPatient d JOIN #Patients s ON s.PatientId=d.PatientId;
  INSERT dw.DimPatient (PatientId,GivenName,FamilyName,DateOfBirth,City)
  SELECT s.* FROM #Patients s
  WHERE NOT EXISTS (SELECT 1 FROM dw.DimPatient d WHERE d.PatientId=s.PatientId);
  UPDATE d SET DepartmentName=s.DepartmentName
  FROM dw.DimDepartment d JOIN #Departments s ON s.DepartmentId=d.DepartmentId;
  INSERT dw.DimDepartment (DepartmentId,DepartmentName)
  SELECT s.* FROM #Departments s
  WHERE NOT EXISTS (SELECT 1 FROM dw.DimDepartment d WHERE d.DepartmentId=s.DepartmentId);
  INSERT dw.DimDate (DateKey,CalendarDate,CalendarYear,CalendarMonth,DayOfMonth)
  SELECT DISTINCT CONVERT(int,CONVERT(char(8),s.EncounterDate,112)),s.EncounterDate,
         YEAR(s.EncounterDate),MONTH(s.EncounterDate),DAY(s.EncounterDate)
  FROM stg.PatientExtract s WHERE s.EncounterDate IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dw.DimDate d WHERE d.CalendarDate=s.EncounterDate);

  SELECT s.EncounterId,p.PatientKey,d.DepartmentKey,t.DateKey,s.CostGBP INTO #Facts
  FROM stg.PatientExtract s
  JOIN dw.DimPatient p ON p.PatientId=s.PatientId
  JOIN dw.DimDepartment d ON d.DepartmentId=s.DepartmentId
  JOIN dw.DimDate t ON t.CalendarDate=s.EncounterDate
  WHERE s.EncounterId IS NOT NULL;
  IF (SELECT COUNT(*) FROM #Facts) <>
     (SELECT COUNT(*) FROM stg.PatientExtract WHERE EncounterId IS NOT NULL)
   THROW 51005, 'Dimension lookup lost encounters.', 1;
  UPDATE f SET PatientKey=s.PatientKey,DepartmentKey=s.DepartmentKey,
    DateKey=s.DateKey,CostGBP=s.CostGBP
  FROM dw.FactPatientEncounter f JOIN #Facts s ON s.EncounterId=f.EncounterId;
  INSERT dw.FactPatientEncounter (EncounterId,PatientKey,DepartmentKey,DateKey,CostGBP)
  SELECT s.* FROM #Facts s
  WHERE NOT EXISTS (SELECT 1 FROM dw.FactPatientEncounter f WHERE f.EncounterId=s.EncounterId);
  IF EXISTS (SELECT EncounterId,PatientKey,DepartmentKey,DateKey,CostGBP FROM #Facts
             EXCEPT SELECT EncounterId,PatientKey,DepartmentKey,DateKey,CostGBP FROM dw.FactPatientEncounter)
   THROW 51006, 'Fact reconciliation failed.', 1;

  -- A retry of the same pipeline run updates its audit row instead of duplicating it.
  DELETE FROM etl.LoadAudit WHERE RunId=@RunId;
  INSERT etl.LoadAudit
  SELECT @RunId,SYSUTCDATETIME(),@ExpectedRows,(SELECT COUNT(*) FROM #Patients),
         COUNT(*),COALESCE(SUM(CONVERT(decimal(18,2),CostGBP)),0) FROM #Facts;
  COMMIT;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
