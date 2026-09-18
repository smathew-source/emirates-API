-- Diamond02 clinical source. All records are synthetic demonstration data.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF OBJECT_ID('dbo.Patient', 'U') IS NULL
CREATE TABLE dbo.Patient (
    PatientId int NOT NULL CONSTRAINT PK_Patient PRIMARY KEY,
    GivenName nvarchar(50) NOT NULL,
    FamilyName nvarchar(50) NOT NULL,
    DateOfBirth date NOT NULL,
    City nvarchar(80) NOT NULL,
    Email nvarchar(254) NULL,
    CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Patient_Created DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID('dbo.Doctor', 'U') IS NULL
CREATE TABLE dbo.Doctor (
    DoctorId int NOT NULL CONSTRAINT PK_Doctor PRIMARY KEY,
    GivenName nvarchar(50) NOT NULL,
    FamilyName nvarchar(50) NOT NULL,
    Specialty nvarchar(100) NOT NULL,
    Email nvarchar(254) NOT NULL CONSTRAINT UQ_Doctor_Email UNIQUE,
    IsActive bit NOT NULL CONSTRAINT DF_Doctor_Active DEFAULT 1
);
IF OBJECT_ID('dbo.Appointment', 'U') IS NULL
CREATE TABLE dbo.Appointment (
    AppointmentId int NOT NULL CONSTRAINT PK_Appointment PRIMARY KEY,
    PatientId int NOT NULL CONSTRAINT FK_Appointment_Patient REFERENCES dbo.Patient(PatientId),
    DoctorId int NOT NULL CONSTRAINT FK_Appointment_Doctor REFERENCES dbo.Doctor(DoctorId),
    StartsAtUtc datetime2(0) NOT NULL,
    EndsAtUtc datetime2(0) NOT NULL,
    Status varchar(20) NOT NULL CONSTRAINT CK_Appointment_Status CHECK (Status IN ('Scheduled','Completed','Cancelled','NoShow')),
    Reason nvarchar(200) NOT NULL,
    CostGBP decimal(10,2) NOT NULL CONSTRAINT CK_Appointment_Cost CHECK (CostGBP >= 0),
    CreatedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_Appointment_Created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Appointment_Time CHECK (EndsAtUtc > StartsAtUtc)
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Appointment') AND name='IX_Appointment_Patient')
CREATE INDEX IX_Appointment_Patient ON dbo.Appointment(PatientId, StartsAtUtc);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Appointment') AND name='IX_Appointment_Doctor')
CREATE INDEX IX_Appointment_Doctor ON dbo.Appointment(DoctorId, StartsAtUtc);

INSERT dbo.Patient (PatientId,GivenName,FamilyName,DateOfBirth,City,Email)
SELECT s.* FROM (VALUES
(1001,N'Demo',N'Patient One',CONVERT(date,'19850412'),N'London',N'patient1@example.com'),
(1002,N'Demo',N'Patient Two',CONVERT(date,'19901123'),N'Leeds',N'patient2@example.com'),
(1003,N'Demo',N'Patient Three',CONVERT(date,'19780706'),N'Bristol',N'patient3@example.com'),
(1004,N'Demo',N'Patient Four',CONVERT(date,'20010115'),N'York',N'patient4@example.com'),
(1005,N'Demo',N'Patient Five',CONVERT(date,'19650320'),N'Manchester',N'patient5@example.com'),
(1006,N'Demo',N'Patient Six',CONVERT(date,'19980908'),N'Bath',N'patient6@example.com')
) s(PatientId,GivenName,FamilyName,DateOfBirth,City,Email)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Patient p WHERE p.PatientId=s.PatientId);

INSERT dbo.Doctor (DoctorId,GivenName,FamilyName,Specialty,Email)
SELECT s.* FROM (VALUES
(201,N'Demo',N'Doctor One',N'General Practice',N'doctor1@example.com'),
(202,N'Demo',N'Doctor Two',N'Cardiology',N'doctor2@example.com'),
(203,N'Demo',N'Doctor Three',N'Dermatology',N'doctor3@example.com')
) s(DoctorId,GivenName,FamilyName,Specialty,Email)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Doctor d WHERE d.DoctorId=s.DoctorId);

INSERT dbo.Appointment (AppointmentId,PatientId,DoctorId,StartsAtUtc,EndsAtUtc,Status,Reason,CostGBP)
SELECT s.AppointmentId,s.PatientId,s.DoctorId,CONVERT(datetime2(0),s.StartsAtUtc,126),CONVERT(datetime2(0),s.EndsAtUtc,126),s.Status,s.Reason,s.CostGBP
FROM (VALUES
(5001,1001,201,'2026-09-01T09:00:00','2026-09-01T09:30:00','Completed',N'Demo routine consultation',60.00),
(5002,1001,202,'2026-09-02T10:00:00','2026-09-02T10:45:00','Completed',N'Demo cardiac review',150.00),
(5003,1002,203,'2026-09-03T11:00:00','2026-09-03T11:30:00','Completed',N'Demo skin review',90.00),
(5004,1003,201,'2026-09-04T14:00:00','2026-09-04T14:30:00','NoShow',N'Demo routine consultation',0.00),
(5005,1004,202,'2026-09-05T09:00:00','2026-09-05T09:45:00','Cancelled',N'Demo follow-up',0.00),
(5006,1005,201,'2026-09-14T10:00:00','2026-09-14T10:30:00','Scheduled',N'Demo health check',60.00),
(5007,1002,203,'2026-09-15T11:00:00','2026-09-15T11:30:00','Scheduled',N'Demo follow-up',75.00),
(5008,1003,202,'2026-09-16T14:00:00','2026-09-16T14:45:00','Scheduled',N'Demo cardiac review',150.00)
) s(AppointmentId,PatientId,DoctorId,StartsAtUtc,EndsAtUtc,Status,Reason,CostGBP)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Appointment a WHERE a.AppointmentId=s.AppointmentId);
COMMIT;
GO
CREATE OR ALTER VIEW dbo.vAppointmentDetails AS
SELECT a.AppointmentId,p.PatientId,p.GivenName AS PatientGivenName,p.FamilyName AS PatientFamilyName,
       d.DoctorId,d.GivenName AS DoctorGivenName,d.FamilyName AS DoctorFamilyName,d.Specialty,
       a.StartsAtUtc,a.EndsAtUtc,a.Status,a.Reason,a.CostGBP
FROM dbo.Appointment a
JOIN dbo.Patient p ON p.PatientId=a.PatientId
JOIN dbo.Doctor d ON d.DoctorId=a.DoctorId;
GO
