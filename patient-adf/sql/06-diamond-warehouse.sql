-- Run in DiamondWarehouse. Source data is copied separately from Diamond02.
SET XACT_ABORT ON;
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg AUTHORIZATION dbo');
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw AUTHORIZATION dbo');
GO
IF OBJECT_ID('stg.Patient','U') IS NULL
CREATE TABLE stg.Patient (
 PatientId int NOT NULL PRIMARY KEY, GivenName nvarchar(50) NOT NULL,
 FamilyName nvarchar(50) NOT NULL, DateOfBirth date NOT NULL, City nvarchar(80) NOT NULL,
 Email nvarchar(254) NULL, CreatedAtUtc datetime2(0) NOT NULL
);
IF OBJECT_ID('stg.Doctor','U') IS NULL
CREATE TABLE stg.Doctor (
 DoctorId int NOT NULL PRIMARY KEY, GivenName nvarchar(50) NOT NULL,
 FamilyName nvarchar(50) NOT NULL, Specialty nvarchar(100) NOT NULL,
 Email nvarchar(254) NOT NULL, IsActive bit NOT NULL
);
IF OBJECT_ID('stg.Appointment','U') IS NULL
CREATE TABLE stg.Appointment (
 AppointmentId int NOT NULL PRIMARY KEY, PatientId int NOT NULL, DoctorId int NOT NULL,
 StartsAtUtc datetime2(0) NOT NULL, EndsAtUtc datetime2(0) NOT NULL,
 Status varchar(20) NOT NULL, Reason nvarchar(200) NOT NULL,
 CostGBP decimal(10,2) NOT NULL, CreatedAtUtc datetime2(0) NOT NULL
);
IF OBJECT_ID('dw.DimPatient','U') IS NULL
CREATE TABLE dw.DimPatient (
 PatientKey int IDENTITY PRIMARY KEY, PatientId int NOT NULL UNIQUE,
 GivenName nvarchar(50) NOT NULL, FamilyName nvarchar(50) NOT NULL,
 DateOfBirth date NOT NULL, City nvarchar(80) NOT NULL, Email nvarchar(254) NULL
);
IF OBJECT_ID('dw.DimDoctor','U') IS NULL
CREATE TABLE dw.DimDoctor (
 DoctorKey int IDENTITY PRIMARY KEY, DoctorId int NOT NULL UNIQUE,
 GivenName nvarchar(50) NOT NULL, FamilyName nvarchar(50) NOT NULL,
 Specialty nvarchar(100) NOT NULL, Email nvarchar(254) NOT NULL, IsActive bit NOT NULL
);
IF OBJECT_ID('dw.DimDate','U') IS NULL
CREATE TABLE dw.DimDate (
 DateKey int NOT NULL PRIMARY KEY, CalendarDate date NOT NULL UNIQUE,
 CalendarYear smallint NOT NULL, CalendarMonth tinyint NOT NULL, DayOfMonth tinyint NOT NULL
);
IF OBJECT_ID('dw.FactAppointment','U') IS NULL
CREATE TABLE dw.FactAppointment (
 AppointmentKey bigint IDENTITY PRIMARY KEY, AppointmentId int NOT NULL UNIQUE,
 PatientKey int NOT NULL REFERENCES dw.DimPatient(PatientKey),
 DoctorKey int NOT NULL REFERENCES dw.DimDoctor(DoctorKey),
 DateKey int NOT NULL REFERENCES dw.DimDate(DateKey),
 StartsAtUtc datetime2(0) NOT NULL, EndsAtUtc datetime2(0) NOT NULL,
 Status varchar(20) NOT NULL CHECK(Status IN ('Scheduled','Completed','Cancelled','NoShow')),
 Reason nvarchar(200) NOT NULL, AppointmentCount tinyint NOT NULL DEFAULT 1 CHECK(AppointmentCount=1),
 CostGBP decimal(10,2) NOT NULL CHECK(CostGBP>=0),
 CHECK(EndsAtUtc>StartsAtUtc)
);
GO
CREATE OR ALTER PROCEDURE dw.LoadAppointments
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @lockResult int;
  EXEC @lockResult=sys.sp_getapplock @Resource='DiamondWarehouseLoad',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @lockResult<0 THROW 51000,'Could not lock warehouse load.',1;
  IF NOT EXISTS(SELECT 1 FROM stg.Patient) OR NOT EXISTS(SELECT 1 FROM stg.Doctor)
   THROW 51001,'Patient and doctor staging data must not be empty.',1;
  IF EXISTS(SELECT 1 FROM stg.Appointment a LEFT JOIN stg.Patient p ON p.PatientId=a.PatientId LEFT JOIN stg.Doctor d ON d.DoctorId=a.DoctorId WHERE p.PatientId IS NULL OR d.DoctorId IS NULL)
   THROW 51002,'An appointment references a missing patient or doctor.',1;
  IF EXISTS(SELECT 1 FROM stg.Appointment WHERE EndsAtUtc<=StartsAtUtc OR CostGBP<0 OR Status NOT IN ('Scheduled','Completed','Cancelled','NoShow'))
   THROW 51003,'Invalid appointment time, cost or status.',1;
  UPDATE d SET GivenName=s.GivenName,FamilyName=s.FamilyName,DateOfBirth=s.DateOfBirth,City=s.City,Email=s.Email
  FROM dw.DimPatient d JOIN stg.Patient s ON s.PatientId=d.PatientId;
  INSERT dw.DimPatient(PatientId,GivenName,FamilyName,DateOfBirth,City,Email)
  SELECT PatientId,GivenName,FamilyName,DateOfBirth,City,Email FROM stg.Patient s WHERE NOT EXISTS(SELECT 1 FROM dw.DimPatient d WHERE d.PatientId=s.PatientId);
  UPDATE d SET GivenName=s.GivenName,FamilyName=s.FamilyName,Specialty=s.Specialty,Email=s.Email,IsActive=s.IsActive
  FROM dw.DimDoctor d JOIN stg.Doctor s ON s.DoctorId=d.DoctorId;
  INSERT dw.DimDoctor(DoctorId,GivenName,FamilyName,Specialty,Email,IsActive)
  SELECT DoctorId,GivenName,FamilyName,Specialty,Email,IsActive FROM stg.Doctor s WHERE NOT EXISTS(SELECT 1 FROM dw.DimDoctor d WHERE d.DoctorId=s.DoctorId);
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
  COMMIT;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
