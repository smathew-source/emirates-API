"""Generate a native SSIS Execute SQL learning package and matching preview data."""
import json
import uuid
from pathlib import Path
from xml.etree import ElementTree as E

ROOT=Path(__file__).parent
D='www.microsoft.com/SqlServer/Dts'
S='www.microsoft.com/sqlserver/dts/tasks/sqltask'
E.register_namespace('DTS',D)
E.register_namespace('SQLTask',S)
def guid(label): return '{'+str(uuid.uuid5(uuid.NAMESPACE_URL,'diamond-ssis/'+label)).upper()+'}'
def attrs(**values): return {'{'+D+'}'+k:str(v) for k,v in values.items()}
def node(parent,name,**values): return E.SubElement(parent,'{'+D+'}'+name,attrs(**values))

steps=[
 {'name':'Read source counts','database':'Diamond02','variable':'SourceSummary',
  'description':'Execute SQL Task: count the source rows and store one summary string in a package variable.',
  'sql':"SELECT CONCAT('Patients: ',(SELECT COUNT(*) FROM dbo.Patient),'; Doctors: ',(SELECT COUNT(*) FROM dbo.Doctor),'; Appointments: ',(SELECT COUNT(*) FROM dbo.Appointment)) AS Summary;",
  'example':'Patients: 6; Doctors: 3; Appointments: 8'},
 {'name':'Check warehouse quality','database':'DiamondWarehouse','variable':'QualitySummary',
  'description':'Execute SQL Task: run the existing validation procedure. A SQL error fails the task and stops the success path.',
  'sql':"SET NOCOUNT ON; DECLARE @results TABLE(QualityStatus varchar(20),AppointmentRows int,AppointmentAmountGBP decimal(18,2)); INSERT @results EXEC etl.CheckWarehouseQuality; SELECT CONCAT(QualityStatus,'; Appointments: ',AppointmentRows,'; Amount GBP: ',AppointmentAmountGBP) AS Summary FROM @results;",
  'example':'Passed; Appointments: 8; Amount GBP: 585.00'},
 {'name':'Read latest load audit','database':'DiamondWarehouse','variable':'LatestLoadSummary',
  'description':'Execute SQL Task: read the latest successful load and save its summary. No audit row is reported as No successful load yet.',
  'sql':"SELECT COALESCE((SELECT TOP (1) CONCAT('Run: ',CONVERT(varchar(36),RunId),'; Loaded UTC: ',CONVERT(varchar(19),LoadedAtUtc,126),'; Appointments: ',AppointmentRows) FROM etl.LoadAudit ORDER BY LoadedAtUtc DESC,RunId DESC),'No successful load yet') AS Summary;",
  'example':'Latest successful load: 8 appointments (illustrative output)'}]

package=E.Element('{'+D+'}Executable',attrs(refId='Package',CreationName='Microsoft.Package',DTSID=guid('package'),ExecutableType='Microsoft.Package',ObjectName='Diamond_SSIS_Learning',ProtectionLevel=0,DelayValidation='True',MaxConcurrentExecutables=1,MaxErrorCount=1,VersionMajor=1,VersionMinor=0,Description='Read-only SSIS learning package. Three Execute SQL tasks; no ETL writes.'))
node(package,'Property',Name='PackageFormatVersion').text='8'
connections=node(package,'ConnectionManagers')
for db in ['Diamond02','DiamondWarehouse']:
    cm=node(connections,'ConnectionManager',refId=f'Package.ConnectionManagers[CM_{db}]',CreationName='OLEDB',DTSID=guid(db),ObjectName='CM_'+db,DelayValidation='True')
    data=node(cm,'ObjectData')
    node(data,'ConnectionManager',ConnectionString=f'Provider=MSOLEDBSQL19;Data Source=diamond-clinical-91685bfa.database.windows.net;Initial Catalog={db};Authentication=ActiveDirectoryInteractive;User ID=sinimannanathu@gmail.com;Use Encryption for Data=Mandatory;Trust Server Certificate=False;Persist Security Info=False;',Retain='True')
variables=node(package,'Variables')
for step in steps:
    v=node(variables,'Variable',DTSID=guid(step['variable']),Namespace='User',ObjectName=step['variable'])
    node(v,'VariableValue',DataType=8).text='Not run'
tasks=node(package,'Executables')
for step in steps:
    task=node(tasks,'Executable',refId='Package\\'+step['name'],CreationName='Microsoft.ExecuteSQLTask',DTSID=guid(step['name']),ExecutableType='Microsoft.ExecuteSQLTask',ObjectName=step['name'],Description=step['description'],DelayValidation='True',FailPackageOnFailure='True')
    node(task,'Variables')
    data=node(task,'ObjectData')
    sql=E.SubElement(data,'{'+S+'}SqlTaskData',{'{'+S+'}'+k:v for k,v in {'Connection':guid(step['database']),'SqlStatementSource':step['sql'],'ResultType':'ResultSetType_SingleRow','BypassPrepare':'True','TimeOut':'60'}.items()})
    E.SubElement(sql,'{'+S+'}ResultBinding',{'{'+S+'}ResultName':'0','{'+S+'}DtsVariableName':'User::'+step['variable']})
constraints=node(package,'PrecedenceConstraints')
for i in range(2):
    node(constraints,'PrecedenceConstraint',refId=f'Package.PrecedenceConstraints[Success{i+1}]',DTSID=guid('edge'+str(i)),ObjectName='Success'+str(i+1),From='Package\\'+steps[i]['name'],To='Package\\'+steps[i+1]['name'],Value=0,EvalOp=2,LogicalAnd='True')
E.indent(package,space='  ')
E.ElementTree(package).write(ROOT/'Diamond_SSIS_Learning.dtsx',encoding='utf-8',xml_declaration=True)
(ROOT/'preview-data.js').write_text('window.packageSteps = '+json.dumps(steps,indent=2)+';\n')
(ROOT/'queries.json').write_text(json.dumps(steps,indent=2)+'\n')
print('Generated Diamond_SSIS_Learning.dtsx and matching preview data')
