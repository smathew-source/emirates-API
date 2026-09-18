"""Create staging/warehouse objects and manually load a consistent Diamond02 snapshot."""
import json
import re
import subprocess
from pathlib import Path
import certifi
import pytds

AZ = r'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
SERVER = 'diamond-clinical-91685bfa.database.windows.net'

def token():
    response = subprocess.run([AZ, 'account', 'get-access-token', '--resource',
                               'https://database.windows.net/', '-o', 'json'],
                              check=True, capture_output=True, text=True)
    return json.loads(response.stdout)['accessToken']

def connect(database):
    return pytds.connect(SERVER, database=database, access_token_callable=token,
                         cafile=certifi.where(), validate_host=True, autocommit=True,
                         login_timeout=60, timeout=60)

columns = {
    'Patient': 'PatientId,GivenName,FamilyName,DateOfBirth,City,Email,CreatedAtUtc',
    'Doctor': 'DoctorId,GivenName,FamilyName,Specialty,Email,IsActive',
    'Appointment': 'AppointmentId,PatientId,DoctorId,StartsAtUtc,EndsAtUtc,Status,Reason,CostGBP,CreatedAtUtc',
}
with connect('DiamondWarehouse') as target:
    cur = target.cursor()
    cur.execute("SELECT COL_LENGTH('dw.DimPatient','CityKey')")
    if cur.fetchone()[0] is not None:
        raise SystemExit('Warehouse uses the snowflake schema. Run python patient-adf/run-diamond-pipeline.py instead; the old manual loader is disabled.')
snapshot = {}
with connect('Diamond02') as source:
    cur = source.cursor()
    cur.execute('SET TRANSACTION ISOLATION LEVEL SNAPSHOT; BEGIN TRANSACTION;')
    for table, names in columns.items():
        cur.execute(f'SELECT {names} FROM dbo.{table}')
        snapshot[table] = cur.fetchall()
    cur.execute('COMMIT;')

with connect('DiamondWarehouse') as target:
    cur = target.cursor()
    sql = Path(__file__).with_name('sql').joinpath('06-diamond-warehouse.sql').read_text()
    for batch in re.split(r'^GO\s*$', sql, flags=re.MULTILINE):
        if batch.strip():
            cur.execute(batch)
    try:
        cur.execute("SET XACT_ABORT ON; BEGIN TRANSACTION; DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource='DiamondWarehouseLoad',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000; IF @r<0 THROW 51000,'Could not lock staging load.',1;")
        for table, names in columns.items():
            cur.execute(f'DELETE FROM stg.{table}')
            if snapshot[table]:
                placeholders = ','.join(['%s'] * len(names.split(',')))
                cur.executemany(f'INSERT stg.{table}({names}) VALUES({placeholders})', snapshot[table])
        cur.execute('EXEC dw.LoadAppointments;')
        cur.execute('COMMIT;')
    except Exception:
        cur.execute('IF @@TRANCOUNT>0 ROLLBACK;')
        raise
    def verify():
        counts = {}
        for table in ['stg.Patient','stg.Doctor','stg.Appointment','dw.DimPatient','dw.DimDoctor','dw.DimDate','dw.FactAppointment']:
            cur.execute(f'SELECT COUNT(*) FROM {table}')
            counts[table] = cur.fetchone()[0]
        for table in columns:
            assert counts['stg.'+table] == len(snapshot[table])
        cur.execute('SELECT AppointmentId,CostGBP FROM dw.FactAppointment')
        facts = dict(cur.fetchall())
        assert all(facts[row[0]] == row[7] for row in snapshot['Appointment'])
        cur.execute('SELECT COUNT(*) FROM dw.FactAppointment f JOIN dw.DimPatient p ON p.PatientKey=f.PatientKey JOIN dw.DimDoctor d ON d.DoctorKey=f.DoctorKey JOIN dw.DimDate dt ON dt.DateKey=f.DateKey')
        assert cur.fetchone()[0] == counts['dw.FactAppointment']
        return counts, facts
    first = verify()
    cur.execute('SELECT PatientId,PatientKey FROM dw.DimPatient')
    patient_keys = dict(cur.fetchall())
    cur.execute('EXEC dw.LoadAppointments;')
    assert verify() == first, 'Rerun changed counts or amounts'
    cur.execute('SELECT PatientId,PatientKey FROM dw.DimPatient')
    assert dict(cur.fetchall()) == patient_keys, 'Rerun changed patient keys'
    print(json.dumps(first[0]))
    print('Appointment amount GBP:', sum(first[1].values()))
    print('PASS: source copy, fact amounts, relationships, repeat load and stable patient keys')
