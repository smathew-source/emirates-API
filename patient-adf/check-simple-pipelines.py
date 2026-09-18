"""Inspect the three test runs and save their activity results."""
import json
from datetime import datetime,timedelta,timezone
from pathlib import Path
from diamond_sql import az,BASE

root=Path(__file__).with_name('simple-pipelines')
results=[]
for item in json.loads((root/'test-runs.json').read_text()):
    run=az('rest','--method','get','--url',BASE+'/pipelineruns/'+item['runId']+'?api-version=2018-06-01')
    record={**item,'status':run['status']}
    if run['status'] in ['Succeeded','Failed','Cancelled']:
        query=root/'activity-query.json'
        query.write_text(json.dumps({'lastUpdatedAfter':run['runStart'],'lastUpdatedBefore':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()}))
        activities=az('rest','--method','post','--url',BASE+'/pipelineruns/'+item['runId']+'/queryActivityruns?api-version=2018-06-01','--body','@'+str(query.resolve()))
        record['activities']=[{'name':a['activityName'],'status':a['status'],'error':a.get('error'),'resultSets':(a.get('output') or {}).get('resultSets')} for a in activities['value']]
    results.append(record)
    print(json.dumps(record),flush=True)
(root/'test-results.json').write_text(json.dumps(results,indent=2)+'\n')
