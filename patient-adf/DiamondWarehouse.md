# DiamondWarehouse

**Historical star-schema setup, superseded by [DiamondSnowflake.md](DiamondSnowflake.md).** The warehouse now normalizes city and specialty into separate dimensions and loads through the published ADF pipeline. Use the new document's queries and commands; the original manual loader below is disabled for this schema.

Created and loaded in Azure on 2026-09-11, on server `diamond-clinical-91685bfa.database.windows.net`, resource group `DiamondResourceGroup`, UK South. This is an additional billed Basic Azure SQL database. Connect with Microsoft Entra authentication using the same administrator as Diamond02.

The flow is `Diamond02.dbo` -> `DiamondWarehouse.stg` -> `DiamondWarehouse.dw`.

| Object | Verified rows |
|---|---:|
| stg.Patient | 6 |
| stg.Doctor | 3 |
| stg.Appointment | 8 |
| dw.DimPatient | 6 |
| dw.DimDoctor | 3 |
| dw.DimDate | 8 |
| dw.FactAppointment | 8 |

Staging retains a copy of the three source tables. The dimensions have stable surrogate keys; facts reference patient, doctor and date keys. The fact grain is one appointment, with status, UTC times, appointment count and amount in GBP. The total appointment amount is GBP 585 across all statuses, including scheduled appointments; it is not collected revenue. DimDate contains dates present in appointments, not a continuous calendar.

`dw.LoadAppointments` validates staging references, appointment times, statuses and costs before loading. Existing dimension attributes are overwritten (Type 1); existing appointment facts are updated by source AppointmentId. Source deletions are not propagated to the warehouse.

The manual Python loader reads all three source tables in one snapshot transaction, then replaces staging and loads the warehouse in one destination transaction. A transaction-scoped application lock serializes cooperating loaders. If the load fails, the staging replacement and warehouse changes roll back together. Other loaders must use this same lock or an equivalent single-writer arrangement.

Run from the workspace root:

```powershell
python -m pip install -r patient-adf/requirements-diamond02.txt
python patient-adf/run-diamond-warehouse.py
```

The loader uses the existing Azure CLI sign-in without saving tokens or passwords. It verifies staging counts against the source snapshot, fact amounts, dimension relationships, and a repeated load with stable patient keys and unchanged counts/amounts. The sample data was loaded and these checks passed against Azure.

Query in DiamondWarehouse:

```sql
SELECT * FROM stg.Patient;
SELECT * FROM dw.DimPatient;
SELECT f.AppointmentId, p.GivenName, p.FamilyName,
       d.Specialty, dt.CalendarDate, f.Status, f.CostGBP
FROM dw.FactAppointment f
JOIN dw.DimPatient p ON p.PatientKey = f.PatientKey
JOIN dw.DimDoctor d ON d.DoctorKey = f.DoctorKey
JOIN dw.DimDate dt ON dt.DateKey = f.DateKey
ORDER BY f.AppointmentId;
```

Schema and stored procedure: `sql/06-diamond-warehouse.sql`.
This is a manual load; no ADF pipeline or schedule has been deployed for these tables.
