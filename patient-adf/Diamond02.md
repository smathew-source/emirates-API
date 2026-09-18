# Diamond02 clinical source

Created and verified in Azure on 2026-09-11.

- Resource group: `DiamondResourceGroup`
- SQL server: `diamond-clinical-91685bfa.database.windows.net`
- Database: `Diamond02`
- Region: UK South
- Service tier: Basic (billed Azure resource)
- Authentication: Microsoft Entra only; administrator `sinimannanathu@gmail.com`
- Network: public endpoint with a single-IP `ClinicalSetupClient` firewall rule for the setup connection. No allow-all-Azure-services rule.

| Table | Synthetic rows |
|---|---:|
| dbo.Patient | 6 |
| dbo.Doctor | 3 |
| dbo.Appointment | 8 |

`Appointment.PatientId` references `Patient.PatientId` and `Appointment.DoctorId` references `Doctor.DoctorId`. The appointment table checks valid statuses, positive duration and nonnegative cost. Times are UTC. Cost represents the example appointment amount, not necessarily collected revenue. One patient has no appointments. No overlapping-slot prevention is implemented.

`dbo.vAppointmentDetails` joins appointments to patient and doctor names and specialty. All names and email addresses are demonstration records.

Connect using SSMS or the Azure portal query editor with Microsoft Entra authentication, select `Diamond02`, then run:

```sql
SELECT * FROM dbo.Patient;
SELECT * FROM dbo.Doctor;
SELECT * FROM dbo.vAppointmentDetails ORDER BY StartsAtUtc;
```

Source: `sql/05-diamond02-source.sql`. It creates missing tables and inserts only missing sample IDs. It does not overwrite existing rows. The runner verifies sample counts, the joined view and enabled, trusted foreign keys. To rerun from this workspace:

```powershell
python -m pip install -r patient-adf/requirements-diamond02.txt
python patient-adf/run-diamond02.py
```

The runner uses the Azure CLI sign-in token in memory and validates the SQL server TLS certificate. The firewall rule may need updating if the client's SQL egress IP changes.

This database has been deployed separately from the original PatientSource/Encounter warehouse demo. Its appointment data feeds staging and the [Diamond snowflake warehouse](DiamondSnowflake.md) through the published `PL_DiamondSnowflake` pipeline. The original `PL_PatientWarehouse` template remains a separate, undeployed demo.
