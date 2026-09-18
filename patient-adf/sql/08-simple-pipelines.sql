-- Read-only reporting procedures in DiamondWarehouse.
CREATE OR ALTER PROCEDURE etl.CheckWarehouseQuality AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM dw.FactAppointment)
  THROW 51100,'Warehouse has no appointments. Run PL_DiamondSnowflake first.',1;
 IF EXISTS(SELECT 1 FROM dw.FactAppointment f
  LEFT JOIN dw.DimPatient p ON p.PatientKey=f.PatientKey
  LEFT JOIN dw.DimCity c ON c.CityKey=p.CityKey
  LEFT JOIN dw.DimDoctor d ON d.DoctorKey=f.DoctorKey
  LEFT JOIN dw.DimSpecialty s ON s.SpecialtyKey=d.SpecialtyKey
  LEFT JOIN dw.DimDate dt ON dt.DateKey=f.DateKey
  WHERE p.PatientKey IS NULL OR c.CityKey IS NULL OR d.DoctorKey IS NULL
   OR s.SpecialtyKey IS NULL OR dt.DateKey IS NULL
   OR dt.CalendarDate<>CAST(f.StartsAtUtc AS date)
   OR f.CostGBP<0 OR f.EndsAtUtc<=f.StartsAtUtc
   OR f.Status NOT IN ('Scheduled','Completed','Cancelled','NoShow') OR f.AppointmentCount<>1)
  THROW 51101,'Invalid appointment relationship, date, status, count or amount.',1;
 IF EXISTS(SELECT AppointmentId FROM dw.FactAppointment GROUP BY AppointmentId HAVING COUNT(*)>1)
  THROW 51102,'Duplicate appointment IDs found.',1;
 SELECT 'Passed' AS QualityStatus,COUNT(*) AS AppointmentRows,SUM(CostGBP) AS AppointmentAmountGBP
 FROM dw.FactAppointment;
END;
GO
CREATE OR ALTER PROCEDURE etl.GetLatestLoadAudit AS
BEGIN
 SET NOCOUNT ON;
 SELECT TOP (1) RunId,LoadedAtUtc,PatientRows,DoctorRows,AppointmentRows,AppointmentAmountGBP,
 DATEDIFF(MINUTE,LoadedAtUtc,SYSUTCDATETIME()) AS MinutesSinceLoad
 FROM etl.LoadAudit ORDER BY LoadedAtUtc DESC,RunId DESC;
END;
GO
GRANT EXECUTE ON OBJECT::etl.CheckWarehouseQuality TO [adf-diamond-clinical-91685bfa];
GRANT EXECUTE ON OBJECT::etl.GetLatestLoadAudit TO [adf-diamond-clinical-91685bfa];
