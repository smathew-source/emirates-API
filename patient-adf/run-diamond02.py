"""Apply the synthetic source SQL using the current Azure CLI identity; no stored credentials."""
import json
import re
import subprocess
from pathlib import Path

import certifi
import pytds

AZ = r"C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"

def token():
    result = subprocess.run([AZ, 'account', 'get-access-token', '--resource',
                             'https://database.windows.net/', '-o', 'json'],
                            check=True, capture_output=True, text=True)
    return json.loads(result.stdout)['accessToken']

with pytds.connect('diamond-clinical-91685bfa.database.windows.net', database='Diamond02',
                   access_token_callable=token, cafile=certifi.where(), validate_host=True,
                   autocommit=True, login_timeout=60, timeout=60) as connection:
    cursor = connection.cursor()
    source = Path(__file__).with_name('sql').joinpath('05-diamond02-source.sql').read_text()
    for batch in re.split(r'^GO\s*$', source, flags=re.MULTILINE):
        if batch.strip():
            cursor.execute(batch)
    cursor.execute("SELECT 'Patient', COUNT(*) FROM dbo.Patient UNION ALL SELECT 'Doctor', COUNT(*) FROM dbo.Doctor UNION ALL SELECT 'Appointment', COUNT(*) FROM dbo.Appointment")
    counts = dict(cursor.fetchall())
    print(json.dumps(counts))
    assert counts == {'Patient': 6, 'Doctor': 3, 'Appointment': 8}, counts
    cursor.execute('SELECT COUNT(*) FROM dbo.vAppointmentDetails')
    assert cursor.fetchone()[0] == 8
    cursor.execute("SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID('dbo.Appointment') AND is_disabled=0 AND is_not_trusted=0")
    assert cursor.fetchone()[0] == 2
    print('PASS: sample counts, joined view and trusted foreign keys')
