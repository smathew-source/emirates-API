-- Run in PatientWarehouse after the first successful pipeline run.
-- Exact counts apply to the initial synthetic fixture only.
IF (SELECT COUNT(*) FROM dw.DimPatient)<>4
 THROW 51100,'Expected four patients, including the patient with no visits.',1;
IF (SELECT COUNT(*) FROM dw.DimDepartment)<>2
 THROW 51101,'Expected two departments.',1;
IF (SELECT COUNT(*) FROM dw.DimDate)<>3
 THROW 51102,'Expected three encounter dates.',1;
IF (SELECT COUNT(*) FROM dw.FactPatientEncounter)<>4
 THROW 51103,'Expected four encounter facts.',1;
IF (SELECT SUM(CostGBP) FROM dw.FactPatientEncounter)<>770.00
 THROW 51104,'Expected GBP 770 total cost.',1;
IF EXISTS(SELECT 1 FROM dw.FactPatientEncounter f JOIN dw.DimPatient p
 ON p.PatientKey=f.PatientKey WHERE p.PatientId=1004)
 THROW 51105,'Patient 1004 should not have a fabricated encounter.',1;
IF NOT EXISTS(SELECT 1 FROM etl.LoadAudit WHERE ExtractRows=5
 AND PatientsInExtract=4 AND EncountersInExtract=4 AND CostGBP=770)
 THROW 51106,'Expected a reconciled successful load audit.',1;
SELECT d.CalendarDate,dep.DepartmentName,SUM(f.EncounterCount) AS Encounters,
 SUM(f.CostGBP) AS TotalCostGBP
FROM dw.FactPatientEncounter f
JOIN dw.DimDate d ON d.DateKey=f.DateKey
JOIN dw.DimDepartment dep ON dep.DepartmentKey=f.DepartmentKey
GROUP BY d.CalendarDate,dep.DepartmentName ORDER BY d.CalendarDate,dep.DepartmentName;
SELECT * FROM etl.LoadAudit ORDER BY LoadedAtUTC DESC;
-- Run the ADF pipeline a second time, then run this script again.
-- Counts and cost must stay unchanged; the second run adds one audit record.
