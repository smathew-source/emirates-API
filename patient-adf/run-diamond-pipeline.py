"""Trigger the published ADF pipeline; use status RUN_ID to inspect it."""
import json
import sys
import tempfile
from pathlib import Path
from datetime import datetime, timedelta, timezone
from diamond_sql import az,BASE

if len(sys.argv)>1 and sys.argv[1]=='activities':
    run=az('rest','--method','get','--url',BASE+'/pipelineruns/'+sys.argv[2]+'?api-version=2018-06-01')
    body={'lastUpdatedAfter':run['runStart'],'lastUpdatedBefore':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()}
    with tempfile.TemporaryDirectory() as temp:
        path=Path(temp)/'query.json'
        path.write_text(json.dumps(body))
        result=az('rest','--method','post','--url',BASE+'/pipelineruns/'+sys.argv[2]+'/queryActivityruns?api-version=2018-06-01','--body','@'+str(path))
    print(json.dumps([{'activity':r['activityName'],'status':r['status'],'error':r.get('error'),'rowsCopied':(r.get('output') or {}).get('rowsCopied')} for r in result['value']],indent=2))
elif len(sys.argv)>1 and sys.argv[1]=='status':
    result=az('rest','--method','get','--url',BASE+'/pipelineruns/'+sys.argv[2]+'?api-version=2018-06-01')
    print(json.dumps({k:result.get(k) for k in ['runId','pipelineName','status','message','runStart','runEnd']},indent=2))
else:
    print(json.dumps(az('rest','--method','post','--url',BASE+'/pipelines/PL_DiamondSnowflake/createRun?api-version=2018-06-01'),indent=2))
