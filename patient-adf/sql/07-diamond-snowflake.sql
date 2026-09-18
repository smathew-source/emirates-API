-- Applied as one transaction by deploy-snowflake.py.
SET XACT_ABORT ON;
IF OBJECT_ID('dw.DimCity','U') IS NULL
 CREATE TABLE dw.DimCity(CityKey int IDENTITY PRIMARY KEY, CityName nvarchar(80) NOT NULL UNIQUE);
IF OBJECT_ID('dw.DimSpecialty','U') IS NULL
 CREATE TABLE dw.DimSpecialty(SpecialtyKey int IDENTITY PRIMARY KEY, SpecialtyName nvarchar(100) NOT NULL UNIQUE);
IF COL_LENGTH('dw.DimPatient','CityKey') IS NULL ALTER TABLE dw.DimPatient ADD CityKey int NULL;
IF COL_LENGTH('dw.DimDoctor','SpecialtyKey') IS NULL ALTER TABLE dw.DimDoctor ADD SpecialtyKey int NULL;
GO
IF COL_LENGTH('dw.DimPatient','City') IS NOT NULL
 EXEC(N'INSERT dw.DimCity(CityName) SELECT DISTINCT City FROM dw.DimPatient p WHERE NOT EXISTS(SELECT 1 FROM dw.DimCity c WHERE c.CityName=p.City);
 UPDATE p SET CityKey=c.CityKey FROM dw.DimPatient p JOIN dw.DimCity c ON c.CityName=p.City;');
IF COL_LENGTH('dw.DimDoctor','Specialty') IS NOT NULL
 EXEC(N'INSERT dw.DimSpecialty(SpecialtyName) SELECT DISTINCT Specialty FROM dw.DimDoctor d WHERE NOT EXISTS(SELECT 1 FROM dw.DimSpecialty s WHERE s.SpecialtyName=d.Specialty);
 UPDATE d SET SpecialtyKey=s.SpecialtyKey FROM dw.DimDoctor d JOIN dw.DimSpecialty s ON s.SpecialtyName=d.Specialty;');
ALTER TABLE dw.DimPatient ALTER COLUMN CityKey int NOT NULL;
ALTER TABLE dw.DimDoctor ALTER COLUMN SpecialtyKey int NOT NULL;
IF OBJECT_ID('dw.FK_DimPatient_City','F') IS NULL ALTER TABLE dw.DimPatient ADD CONSTRAINT FK_DimPatient_City FOREIGN KEY(CityKey) REFERENCES dw.DimCity(CityKey);
IF OBJECT_ID('dw.FK_DimDoctor_Specialty','F') IS NULL ALTER TABLE dw.DimDoctor ADD CONSTRAINT FK_DimDoctor_Specialty FOREIGN KEY(SpecialtyKey) REFERENCES dw.DimSpecialty(SpecialtyKey);
IF COL_LENGTH('dw.DimPatient','City') IS NOT NULL ALTER TABLE dw.DimPatient DROP COLUMN City;
IF COL_LENGTH('dw.DimDoctor','Specialty') IS NOT NULL ALTER TABLE dw.DimDoctor DROP COLUMN Specialty;
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl AUTHORIZATION dbo');
GO
IF OBJECT_ID('etl.LoadAudit','U') IS NULL
CREATE TABLE etl.LoadAudit(RunId uniqueidentifier PRIMARY KEY,LoadedAtUtc datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),PatientRows int NOT NULL,DoctorRows int NOT NULL,AppointmentRows int NOT NULL,AppointmentAmountGBP decimal(18,2) NOT NULL);
GO
CREATE OR ALTER PROCEDURE dw.LoadAppointments
 @RunId uniqueidentifier = NULL, @PatientRows int = NULL, @DoctorRows int = NULL, @AppointmentRows int = NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @lockResult int;
  EXEC @lockResult=sys.sp_getapplock @Resource='DiamondWarehouseLoad',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @lockResult<0 THROW 51000,'Could not lock warehouse load.',1;
  IF (@PatientRows IS NOT NULL AND @PatientRows<>(SELECT COUNT(*) FROM stg.Patient)) OR
     (@DoctorRows IS NOT NULL AND @DoctorRows<>(SELECT COUNT(*) FROM stg.Doctor)) OR
     (@AppointmentRows IS NOT NULL AND @AppointmentRows<>(SELECT COUNT(*) FROM stg.Appointment))
   THROW 51004,'Staging counts do not match copy activity counts.',1;
  IF NOT EXISTS(SELECT 1 FROM stg.Patient) OR NOT EXISTS(SELECT 1 FROM stg.Doctor)
   THROW 51001,'Patient and doctor staging data must not be empty.',1;
  IF EXISTS(SELECT 1 FROM stg.Appointment a LEFT JOIN stg.Patient p ON p.PatientId=a.PatientId LEFT JOIN stg.Doctor d ON d.DoctorId=a.DoctorId WHERE p.PatientId IS NULL OR d.DoctorId IS NULL)
   THROW 51002,'An appointment references a missing patient or doctor.',1;
  IF EXISTS(SELECT 1 FROM stg.Appointment WHERE EndsAtUtc<=StartsAtUtc OR CostGBP<0 OR Status NOT IN ('Scheduled','Completed','Cancelled','NoShow'))
   THROW 51003,'Invalid appointment time, cost or status.',1;
  INSERT dw.DimCity(CityName) SELECT DISTINCT City FROM stg.Patient p WHERE NOT EXISTS(SELECT 1 FROM dw.DimCity c WHERE c.CityName=p.City);
  INSERT dw.DimSpecialty(SpecialtyName) SELECT DISTINCT Specialty FROM stg.Doctor d WHERE NOT EXISTS(SELECT 1 FROM dw.DimSpecialty s WHERE s.SpecialtyName=d.Specialty);
  UPDATE d SET GivenName=s.GivenName,FamilyName=s.FamilyName,DateOfBirth=s.DateOfBirth,CityKey=c.CityKey,Email=s.Email
  FROM dw.DimPatient d JOIN stg.Patient s ON s.PatientId=d.PatientId JOIN dw.DimCity c ON c.CityName=s.City;
  INSERT dw.DimPatient(PatientId,GivenName,FamilyName,DateOfBirth,CityKey,Email)
  SELECT PatientId,GivenName,FamilyName,DateOfBirth,c.CityKey,Email FROM stg.Patient s JOIN dw.DimCity c ON c.CityName=s.City WHERE NOT EXISTS(SELECT 1 FROM dw.DimPatient d WHERE d.PatientId=s.PatientId);
  UPDATE d SET GivenName=s.GivenName,FamilyName=s.FamilyName,SpecialtyKey=sp.SpecialtyKey,Email=s.Email,IsActive=s.IsActive
  FROM dw.DimDoctor d JOIN stg.Doctor s ON s.DoctorId=d.DoctorId JOIN dw.DimSpecialty sp ON sp.SpecialtyName=s.Specialty;
  INSERT dw.DimDoctor(DoctorId,GivenName,FamilyName,SpecialtyKey,Email,IsActive)
  SELECT DoctorId,GivenName,FamilyName,sp.SpecialtyKey,Email,IsActive FROM stg.Doctor s JOIN dw.DimSpecialty sp ON sp.SpecialtyName=s.Specialty WHERE NOT EXISTS(SELECT 1 FROM dw.DimDoctor d WHERE d.DoctorId=s.DoctorId);
  INSERT dw.DimDate(DateKey,CalendarDate,CalendarYear,CalendarMonth,DayOfMonth)
  SELECT DISTINCT CONVERT(int,CONVERT(char(8),StartsAtUtc,112)),CAST(StartsAtUtc AS date),YEAR(StartsAtUtc),MONTH(StartsAtUtc),DAY(StartsAtUtc)
  FROM stg.Appointment s WHERE NOT EXISTS(SELECT 1 FROM dw.DimDate d WHERE d.CalendarDate=CAST(s.StartsAtUtc AS date));
  UPDATE f SET PatientKey=p.PatientKey,DoctorKey=d.DoctorKey,DateKey=CONVERT(int,CONVERT(char(8),s.StartsAtUtc,112)),
   StartsAtUtc=s.StartsAtUtc,EndsAtUtc=s.EndsAtUtc,Status=s.Status,Reason=s.Reason,CostGBP=s.CostGBP
  FROM dw.FactAppointment f JOIN stg.Appointment s ON s.AppointmentId=f.AppointmentId
  JOIN dw.DimPatient p ON p.PatientId=s.PatientId JOIN dw.DimDoctor d ON d.DoctorId=s.DoctorId;
  INSERT dw.FactAppointment(AppointmentId,PatientKey,DoctorKey,DateKey,StartsAtUtc,EndsAtUtc,Status,Reason,CostGBP)
  SELECT s.AppointmentId,p.PatientKey,d.DoctorKey,CONVERT(int,CONVERT(char(8),s.StartsAtUtc,112)),s.StartsAtUtc,s.EndsAtUtc,s.Status,s.Reason,s.CostGBP
  FROM stg.Appointment s JOIN dw.DimPatient p ON p.PatientId=s.PatientId JOIN dw.DimDoctor d ON d.DoctorId=s.DoctorId
  WHERE NOT EXISTS(SELECT 1 FROM dw.FactAppointment f WHERE f.AppointmentId=s.AppointmentId);
  IF @RunId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM etl.LoadAudit WHERE RunId=@RunId)
   INSERT etl.LoadAudit(RunId,PatientRows,DoctorRows,AppointmentRows,AppointmentAmountGBP)
   SELECT @RunId,(SELECT COUNT(*) FROM stg.Patient),(SELECT COUNT(*) FROM stg.Doctor),COUNT(*),COALESCE(SUM(CostGBP),0) FROM stg.Appointment;
  COMMIT;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE etl.ResetPatient AS BEGIN SET NOCOUNT ON; DELETE FROM stg.Patient; END;
GO
CREATE OR ALTER PROCEDURE etl.ResetDoctor AS BEGIN SET NOCOUNT ON; DELETE FROM stg.Doctor; END;
GO
CREATE OR ALTER PROCEDURE etl.ResetAppointment AS BEGIN SET NOCOUNT ON; DELETE FROM stg.Appointment; END;
GO
CREATE OR ALTER VIEW dw.vAppointmentDetails AS
SELECT f.AppointmentId,p.PatientId,p.GivenName AS PatientGivenName,p.FamilyName AS PatientFamilyName,
 c.CityName,d.DoctorId,d.GivenName AS DoctorGivenName,d.FamilyName AS DoctorFamilyName,
 s.SpecialtyName,dt.CalendarDate,f.StartsAtUtc,f.EndsAtUtc,f.Status,f.Reason,f.AppointmentCount,f.CostGBP
FROM dw.FactAppointment f JOIN dw.DimPatient p ON p.PatientKey=f.PatientKey
JOIN dw.DimCity c ON c.CityKey=p.CityKey JOIN dw.DimDoctor d ON d.DoctorKey=f.DoctorKey
JOIN dw.DimSpecialty s ON s.SpecialtyKey=d.SpecialtyKey JOIN dw.DimDate dt ON dt.DateKey=f.DateKey;
GO
