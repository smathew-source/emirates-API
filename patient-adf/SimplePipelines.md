# Simple pipeline examples

Factory: `adf-diamond-clinical-91685bfa`  
ADF Author folder: **Simple examples**

| Pipeline | What it teaches | Output |
|---|---|---|
| `PL_SourceRowCounts` | Run a SQL query against the source | Counts for Patient, Doctor and Appointment |
| `PL_WarehouseQualityCheck` | Validate data and fail a pipeline on an issue | Pass status, appointment count and total appointment amount |
| `PL_LatestLoadAudit` | Read operational metadata | Latest successful warehouse-load ID, time, counts, amount and age in minutes |

Each pipeline contains one Script activity, uses the existing managed-identity SQL linked services, runs manually and does not modify patient or warehouse data. There are no schedules. They can run independently of each other. Normal ADF activity charges apply.

The quality check rejects an empty appointment fact table, missing appointment dimension references, a date-key/calendar mismatch, invalid statuses, invalid appointment count, negative amounts, nonpositive duration or duplicate appointment IDs. It validates the warehouse internally; it does not prove freshness or reconcile every source row. Run `PL_DiamondSnowflake` first if the warehouse has not been loaded.

The audit example returns the latest successful ETL load, not the latest attempted pipeline run. It succeeds with an empty result set when no load audit exists. Failed runs are available in ADF Monitor.

## Run and view results

1. Open ADF Studio -> Author -> Pipelines -> **Simple examples**.
2. Select a pipeline -> **Trigger now**.
3. Open Monitor -> Pipeline runs -> select the run.
4. Open the Script activity's **Output** and expand `resultSets[0].rows`.

Only aggregate counts and load metadata are returned; patient names and other patient details are not included in activity output.

JSON definitions are in `simple-pipelines/`. SQL procedures and their narrowly scoped EXECUTE grants are in `sql/08-simple-pipelines.sql`. `deploy-simple-pipelines.py` publishes the pipelines and starts one test run per pipeline; `check-simple-pipelines.py` inspects those runs and saves `simple-pipelines/test-results.json`.

The existing `PL_DiamondSnowflake` ETL pipeline is unchanged.
