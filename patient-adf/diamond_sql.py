"""Shared authenticated SQL access. Tokens remain in memory."""
import json
import re
import subprocess
from pathlib import Path
import certifi
import pytds

AZ = r'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
SERVER = 'diamond-clinical-91685bfa.database.windows.net'
FACTORY = 'adf-diamond-clinical-91685bfa'
BASE = '/subscriptions/91685bfa-3af7-4c2e-ab65-e7afa7ec47f7/resourceGroups/DiamondResourceGroup/providers/Microsoft.DataFactory/factories/'+FACTORY

def az(*args):
    result = subprocess.run([AZ,*args,'-o','json'],capture_output=True,text=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout) if result.stdout.strip() else None

def token():
    return az('account','get-access-token','--resource','https://database.windows.net/')['accessToken']

def connect(db='DiamondWarehouse'):
    return pytds.connect(SERVER,database=db,access_token_callable=token,cafile=certifi.where(),validate_host=True,autocommit=True,login_timeout=60,timeout=90)

def batches(cursor,filename):
    for sql in re.split(r'^GO\s*$',Path(filename).read_text(),flags=re.MULTILINE):
        if sql.strip(): cursor.execute(sql)
