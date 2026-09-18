"""Publish three read-only learning pipelines and trigger one test run each."""
import json
import re
from pathlib import Path
import certifi
import pytds
from diamond_sql import az,BASE,SERVER,token,batches

ROOT=Path(__file__).parent
def connection():
    return pytds.connect(SERVER,database='DiamondWarehouse',access_token_callable=token,
        cafile=certifi.where(),validate_host=True,autocommit=True,
        login_timeout=15,timeout=60,disable_connect_retry=True)
try:
    db=connection()
except (pytds.Error, TimeoutError) as error:
    match=re.search(r"Client with IP address '([0-9.]+)' is not allowed",str(error.__cause__ or error))
    if not match: raise
    ip=match.group(1)
    az('sql','server','firewall-rule','update','-g','DiamondResourceGroup','-s',SERVER.split('.')[0],
       '-n','ClinicalSetupClient','--start-ip-address',ip,'--end-ip-address',ip)
    print('Updated existing single-client firewall rule for current SQL egress IP',flush=True)
    db=connection()
with db:
    cur=db.cursor()
    cur.execute('SET XACT_ABORT ON; BEGIN TRANSACTION;')
    try:
        batches(cur,ROOT/'sql/08-simple-pipelines.sql')
        cur.execute('COMMIT;')
    except Exception:
        cur.execute('IF @@TRANCOUNT>0 ROLLBACK;')
        raise

definitions=[
 ('PL_SourceRowCounts','CountSourceRows','Diamond02',
  "SELECT 'Patient' AS TableName, COUNT(*) AS [RowCount] FROM dbo.Patient UNION ALL SELECT 'Doctor',COUNT(*) FROM dbo.Doctor UNION ALL SELECT 'Appointment',COUNT(*) FROM dbo.Appointment;",
  'Show patient, doctor and appointment row counts in the activity output.'),
 ('PL_WarehouseQualityCheck','CheckWarehouseQuality','DiamondWarehouse','EXEC etl.CheckWarehouseQuality;',
  'Fail on an empty appointment warehouse or invalid appointment relationships and values; otherwise show totals.'),
 ('PL_LatestLoadAudit','ReadLatestLoadAudit','DiamondWarehouse','EXEC etl.GetLatestLoadAudit;',
  'Show the latest successful warehouse load and its age in minutes. No result rows means no successful load.')]
folder=ROOT/'simple-pipelines'
folder.mkdir(exist_ok=True)
runs=[]
for name,activity,db,sql,description in definitions:
    body={'properties':{'description':description,'folder':{'name':'Simple examples'},'concurrency':1,
        'annotations':['Read only','Manual trigger'],
        'activities':[{'name':activity,'type':'Script',
            'policy':{'timeout':'0.00:05:00','retry':0,'secureInput':False,'secureOutput':False},
            'linkedServiceName':{'type':'LinkedServiceReference','referenceName':'LS_'+db},
            'typeProperties':{'scripts':[{'type':'Query','text':sql}],'scriptBlockExecutionTimeout':'00:02:00'}}]}}
    path=folder/(name+'.json')
    path.write_text(json.dumps(body,indent=2)+'\n')
    az('rest','--method','put','--url',BASE+'/pipelines/'+name+'?api-version=2018-06-01','--body','@'+str(path.resolve()))
    run=az('rest','--method','post','--url',BASE+'/pipelines/'+name+'/createRun?api-version=2018-06-01')
    runs.append({'pipeline':name,'runId':run['runId']})
    print(json.dumps(runs[-1]),flush=True)
(folder/'test-runs.json').write_text(json.dumps(runs,indent=2)+'\n')
