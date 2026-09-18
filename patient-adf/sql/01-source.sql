-- Run in PatientSource. Synthetic demonstration data only.
SET XACT_ABORT ON;
GO
IF OBJECT_ID('dbo.Patient', 'U') IS NULL
CREATE TABLE dbo.Patient (
    PatientId int NOT NULL PRIMARY KEY,
    GivenName nvarchar(50) NOT NULL,
    FamilyName nvarchar(50) NOT NULL,
    DateOfBirth date NOT NULL,
    City nvarchar(80) NOT NULL
);
IF OBJECT_ID('dbo.Department', 'U') IS NULL
CREATE TABLE dbo.Department (
    DepartmentId int NOT NULL PRIMARY KEY,
    DepartmentName nvarchar(80) NOT NULL
);
IF OBJECT_ID('dbo.Encounter', 'U') IS NULL
CREATE TABLE dbo.Encounter (
    EncounterId int NOT NULL PRIMARY KEY,
    PatientId int NOT NULL REFERENCES dbo.Patient(PatientId),
    DepartmentId int NOT NULL REFERENCES dbo.Department(DepartmentId),
    EncounterDate date NOT NULL,
    CostGBP decimal(12,2) NOT NULL CHECK (CostGBP >= 0)
);
GO
BEGIN TRANSACTION;
INSERT dbo.Patient (PatientId, GivenName, FamilyName, DateOfBirth, City)
SELECT s.* FROM (VALUES
 (1001,N'Demo',N'Patient One',CONVERT(date,'19850412'),N'London'),
 (1002,N'Demo',N'Patient Two',CONVERT(date,'19901123'),N'Leeds'),
 (1003,N'Demo',N'Patient Three',CONVERT(date,'19780706'),N'Bristol'),
 (1004,N'Demo',N'Patient Four',CONVERT(date,'20010115'),N'York')
) s(PatientId,GivenName,FamilyName,DateOfBirth,City)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Patient p WHERE p.PatientId=s.PatientId);
INSERT dbo.Department (DepartmentId, DepartmentName)
SELECT s.* FROM (VALUES (10,N'Outpatients'),(20,N'Radiology')) s(DepartmentId,DepartmentName)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Department d WHERE d.DepartmentId=s.DepartmentId);
INSERT dbo.Encounter (EncounterId,PatientId,DepartmentId,EncounterDate,CostGBP)
SELECT s.* FROM (VALUES
 (5001,1001,10,CONVERT(date,'20260901'),CONVERT(decimal(12,2),120)),
 (5002,1001,20,CONVERT(date,'20260902'),CONVERT(decimal(12,2),250)),
 (5003,1002,10,CONVERT(date,'20260902'),CONVERT(decimal(12,2),100)),
 (5004,1003,20,CONVERT(date,'20260903'),CONVERT(decimal(12,2),300))
) s(EncounterId,PatientId,DepartmentId,EncounterDate,CostGBP)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Encounter e WHERE e.EncounterId=s.EncounterId);
COMMIT;
GO
-- One consistent extract; LEFT JOIN also includes patients with no encounters.
CREATE OR ALTER VIEW dbo.vPatientExtract AS
SELECT p.PatientId,p.GivenName,p.FamilyName,p.DateOfBirth,p.City,
       e.EncounterId,e.EncounterDate,e.DepartmentId,d.DepartmentName,e.CostGBP
FROM dbo.Patient p
LEFT JOIN dbo.Encounter e ON e.PatientId=p.PatientId
LEFT JOIN dbo.Department d ON d.DepartmentId=e.DepartmentId;
GO
