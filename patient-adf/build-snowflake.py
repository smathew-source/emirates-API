"""Generate migration and ADF ARM template for the existing Diamond SQL databases."""
import json
from pathlib import Path

ROOT = Path(__file__).parent
factory = 'adf-diamond-clinical-91685bfa'
host = 'diamond-clinical-91685bfa.database.windows.net'
sql = """-- Applied as one transaction by deploy-snowflake.py.
SET XACT_ABORT ON;
IF OBJECT_ID('dw.DimCity','U') IS NULL
 CREATE TABLE dw.DimCity(CityKey int IDENTITY PRIMARY KEY, CityName nvarchar(80) NOT NULL UNIQUE);
IF OBJECT_ID('dw.DimSpecialty','U') IS NULL
 CREATE TABLE dw.DimSpecialty(SpecialtyKey int IDENTITY PRIMARY KEY, SpecialtyName nvarchar(100) NOT NULL UNIQUE);
IF COL_LENGTH('dw.DimPatient','CityKey') IS NULL ALTER TABLE dw.DimPatient ADD CityKey int NULL;
IF COL_LENGTH('dw.DimDoctor','SpecialtyKey') IS NULL ALTER TABLE dw.DimDoctor ADD SpecialtyKey int NULL;
GO
IF COL_LENGTH('dw.DimPatient','City') IS NOT NULL
 EXEC(N'INSERT dw.DimCity(CityName) SELECT DISTINCT City FROM dw.DimPatient p WHERE NOT EXISTS(SELECT 1 FROM dw.DimCity c WHERE c.CityName=p.City);
 UPDATE p SET CityKey=c.CityKey FROM dw.DimPatient p JOIN dw.DimCity c ON c.CityName=p.City;');
IF COL_LENGTH('dw.DimDoctor','Specialty') IS NOT NULL
 EXEC(N'INSERT dw.DimSpecialty(SpecialtyName) SELECT DISTINCT Specialty FROM dw.DimDoctor d WHERE NOT EXISTS(SELECT 1 FROM dw.DimSpecialty s WHERE s.SpecialtyName=d.Specialty);
 UPDATE d SET SpecialtyKey=s.SpecialtyKey FROM dw.DimDoctor d JOIN dw.DimSpecialty s ON s.SpecialtyName=d.Specialty;');
ALTER TABLE dw.DimPatient ALTER COLUMN CityKey int NOT NULL;
ALTER TABLE dw.DimDoctor ALTER COLUMN SpecialtyKey int NOT NULL;
IF OBJECT_ID('dw.FK_DimPatient_City','F') IS NULL ALTER TABLE dw.DimPatient ADD CONSTRAINT FK_DimPatient_City FOREIGN KEY(CityKey) REFERENCES dw.DimCity(CityKey);
IF OBJECT_ID('dw.FK_DimDoctor_Specialty','F') IS NULL ALTER TABLE dw.DimDoctor ADD CONSTRAINT FK_DimDoctor_Specialty FOREIGN KEY(SpecialtyKey) REFERENCES dw.DimSpecialty(SpecialtyKey);
IF COL_LENGTH('dw.DimPatient','City') IS NOT NULL ALTER TABLE dw.DimPatient DROP COLUMN City;
IF COL_LENGTH('dw.DimDoctor','Specialty') IS NOT NULL ALTER TABLE dw.DimDoctor DROP COLUMN Specialty;
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl AUTHORIZATION dbo');
GO
IF OBJECT_ID('etl.LoadAudit','U') IS NULL
CREATE TABLE etl.LoadAudit(RunId uniqueidentifier PRIMARY KEY,LoadedAtUtc datetime2(0) NOT NULL DEFAULT SYSUTCDATETIME(),PatientRows int NOT NULL,DoctorRows int NOT NULL,AppointmentRows int NOT NULL,AppointmentAmountGBP decimal(18,2) NOT NULL);
GO
"""
base = (ROOT/'sql/06-diamond-warehouse.sql').read_text()
proc = base[base.index('CREATE OR ALTER PROCEDURE dw.LoadAppointments'):]
proc = proc.replace('dw.LoadAppointments\nAS', 'dw.LoadAppointments\n @RunId uniqueidentifier = NULL, @PatientRows int = NULL, @DoctorRows int = NULL, @AppointmentRows int = NULL\nAS')
proc = proc.replace("  IF NOT EXISTS(SELECT 1 FROM stg.Patient)", """  IF (@PatientRows IS NOT NULL AND @PatientRows<>(SELECT COUNT(*) FROM stg.Patient)) OR
     (@DoctorRows IS NOT NULL AND @DoctorRows<>(SELECT COUNT(*) FROM stg.Doctor)) OR
     (@AppointmentRows IS NOT NULL AND @AppointmentRows<>(SELECT COUNT(*) FROM stg.Appointment))
   THROW 51004,'Staging counts do not match copy activity counts.',1;
  IF NOT EXISTS(SELECT 1 FROM stg.Patient)""")
proc = proc.replace('  UPDATE d SET GivenName=s.GivenName,FamilyName=s.FamilyName,DateOfBirth', """  INSERT dw.DimCity(CityName) SELECT DISTINCT City FROM stg.Patient p WHERE NOT EXISTS(SELECT 1 FROM dw.DimCity c WHERE c.CityName=p.City);
  INSERT dw.DimSpecialty(SpecialtyName) SELECT DISTINCT Specialty FROM stg.Doctor d WHERE NOT EXISTS(SELECT 1 FROM dw.DimSpecialty s WHERE s.SpecialtyName=d.Specialty);
  UPDATE d SET GivenName=s.GivenName,FamilyName=s.FamilyName,DateOfBirth""")
proc = proc.replace('City=s.City','CityKey=c.CityKey').replace('Specialty=s.Specialty','SpecialtyKey=sp.SpecialtyKey')
proc = proc.replace('ON s.PatientId=d.PatientId;', 'ON s.PatientId=d.PatientId JOIN dw.DimCity c ON c.CityName=s.City;')
proc = proc.replace('ON s.DoctorId=d.DoctorId;', 'ON s.DoctorId=d.DoctorId JOIN dw.DimSpecialty sp ON sp.SpecialtyName=s.Specialty;')
proc = proc.replace('DateOfBirth,City,Email)', 'DateOfBirth,CityKey,Email)')
proc = proc.replace('SELECT PatientId,GivenName,FamilyName,DateOfBirth,City,Email FROM stg.Patient s', 'SELECT PatientId,GivenName,FamilyName,DateOfBirth,c.CityKey,Email FROM stg.Patient s JOIN dw.DimCity c ON c.CityName=s.City')
proc = proc.replace('FamilyName,Specialty,Email,IsActive)', 'FamilyName,SpecialtyKey,Email,IsActive)')
proc = proc.replace('SELECT DoctorId,GivenName,FamilyName,Specialty,Email,IsActive FROM stg.Doctor s', 'SELECT DoctorId,GivenName,FamilyName,sp.SpecialtyKey,Email,IsActive FROM stg.Doctor s JOIN dw.DimSpecialty sp ON sp.SpecialtyName=s.Specialty')
proc = proc.replace('  COMMIT;', """  IF @RunId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM etl.LoadAudit WHERE RunId=@RunId)
   INSERT etl.LoadAudit(RunId,PatientRows,DoctorRows,AppointmentRows,AppointmentAmountGBP)
   SELECT @RunId,(SELECT COUNT(*) FROM stg.Patient),(SELECT COUNT(*) FROM stg.Doctor),COUNT(*),COALESCE(SUM(CostGBP),0) FROM stg.Appointment;
  COMMIT;""")
sql += proc
for table in ['Patient','Doctor','Appointment']:
    sql += f'CREATE OR ALTER PROCEDURE etl.Reset{table} AS BEGIN SET NOCOUNT ON; DELETE FROM stg.{table}; END;\nGO\n'
sql += """CREATE OR ALTER VIEW dw.vAppointmentDetails AS
SELECT f.AppointmentId,p.PatientId,p.GivenName AS PatientGivenName,p.FamilyName AS PatientFamilyName,
 c.CityName,d.DoctorId,d.GivenName AS DoctorGivenName,d.FamilyName AS DoctorFamilyName,
 s.SpecialtyName,dt.CalendarDate,f.StartsAtUtc,f.EndsAtUtc,f.Status,f.Reason,f.AppointmentCount,f.CostGBP
FROM dw.FactAppointment f JOIN dw.DimPatient p ON p.PatientKey=f.PatientKey
JOIN dw.DimCity c ON c.CityKey=p.CityKey JOIN dw.DimDoctor d ON d.DoctorKey=f.DoctorKey
JOIN dw.DimSpecialty s ON s.SpecialtyKey=d.SpecialtyKey JOIN dw.DimDate dt ON dt.DateKey=f.DateKey;
GO
"""
(ROOT/'sql/07-diamond-snowflake.sql').write_text(sql)

ref = lambda kind,name: {'type':kind+'Reference','referenceName':name}
resource_id = lambda kind,name: f"[resourceId('Microsoft.DataFactory/factories/{kind}', '{factory}', '{name}')]"
resources = [{'type':'Microsoft.DataFactory/factories','apiVersion':'2018-06-01','name':factory,'location':'uksouth','identity':{'type':'SystemAssigned'},'properties':{}}]
fid = f"[resourceId('Microsoft.DataFactory/factories','{factory}')]"
def resource(kind,name,properties,dependencies):
    resources.append({'type':'Microsoft.DataFactory/factories/'+kind,'apiVersion':'2018-06-01','name':factory+'/'+name,'dependsOn':dependencies,'properties':properties})
for db in ['Diamond02','DiamondWarehouse']:
    resource('linkedservices','LS_'+db,{'type':'AzureSqlDatabase','typeProperties':{'server':host,'database':db,'authenticationType':'SystemAssignedManagedIdentity','encrypt':'mandatory','trustServerCertificate':False}},[fid])
resource('linkedservices','LS_DatabricksLearning',{
    'type':'AzureDatabricks',
    'parameters':{
        'workspaceUrl':{'type':'String'},
        'existingClusterId':{'type':'String'}
    },
    'typeProperties':{
        'domain':'@{linkedService().workspaceUrl}',
        'existingClusterId':'@{linkedService().existingClusterId}'
    }
},[fid])
columns = {
 'Patient':'PatientId,GivenName,FamilyName,DateOfBirth,City,Email,CreatedAtUtc',
 'Doctor':'DoctorId,GivenName,FamilyName,Specialty,Email,IsActive',
 'Appointment':'AppointmentId,PatientId,DoctorId,StartsAtUtc,EndsAtUtc,Status,Reason,CostGBP,CreatedAtUtc'}
policy = {'timeout':'0.00:15:00','retry':2,'retryIntervalInSeconds':30,'secureInput':True,'secureOutput':False}
activities=[]
deps=[]
previous=None
for table,names in columns.items():
    for side,db,schema in [('Source','Diamond02','dbo'),('Stage','DiamondWarehouse','stg')]:
        name=f'DS_{side}{table}'
        resource('datasets',name,{'type':'AzureSqlTable','linkedServiceName':ref('LinkedService','LS_'+db),'typeProperties':{'schema':schema,'table':table},'schema':[]},[resource_id('linkedservices','LS_'+db)])
        deps.append(resource_id('datasets',name))
    activity={'name':'Copy'+table,'type':'Copy','policy':policy,'dependsOn':([] if previous is None else [{'activity':previous,'dependencyConditions':['Succeeded']}]),'inputs':[ref('Dataset','DS_Source'+table)],'outputs':[ref('Dataset','DS_Stage'+table)],'typeProperties':{'source':{'type':'AzureSqlSource','sqlReaderQuery':f'SELECT {names} FROM dbo.{table}','partitionOption':'None','queryTimeout':'00:10:00'},'sink':{'type':'AzureSqlSink','preCopyScript':f'EXEC etl.Reset{table};','writeBehavior':'insert'},'enableStaging':False,'translator':{'type':'TabularTranslator','mappings':[{'source':{'name':n},'sink':{'name':n}} for n in names.split(',')]}}}
    activities.append(activity)
    previous=activity['name']
activities.append({
    'name':'LookupStagingAppointmentCount',
    'type':'Lookup',
    'policy':policy,
    'dependsOn':[{'activity':'CopyAppointment','dependencyConditions':['Succeeded']}],
    'linkedServiceName':ref('LinkedService','LS_DiamondWarehouse'),
    'typeProperties':{
        'source':{
            'type':'AzureSqlSource',
            'sqlReaderQuery':'SELECT COUNT(*) AS AppointmentRows FROM stg.Appointment'
        },
        'dataset':{
            'referenceName':'DS_StageAppointment',
            'type':'DatasetReference'
        },
        'firstRowOnly':True
    }
})
parameters={'RunId':{'type':'Guid','value':{'value':'@pipeline().RunId','type':'Expression'}}}
for table in columns:
    parameters[table+'Rows']={'type':'Int32','value':{'value':f"@activity('Copy{table}').output.rowsCopied",'type':'Expression'}}
parameters['AppointmentRows']={'type':'Int32','value':{'value':"@activity('LookupStagingAppointmentCount').output.firstRow.AppointmentRows",'type':'Expression'}}
activities.append({'name':'LoadSnowflake','type':'SqlServerStoredProcedure','policy':policy,'dependsOn':[{'activity':'LookupStagingAppointmentCount','dependencyConditions':['Succeeded']}],'linkedServiceName':ref('LinkedService','LS_DiamondWarehouse'),'typeProperties':{'storedProcedureName':'dw.LoadAppointments','storedProcedureParameters':parameters}})
activities.append({
    'name':'ValidateWarehouse',
    'type':'Script',
    'policy':policy,
    'dependsOn':[{'activity':'LoadSnowflake','dependencyConditions':['Succeeded']}],
    'linkedServiceName':ref('LinkedService','LS_DiamondWarehouse'),
    'typeProperties':{
        'scripts':[{
            'type':'Query',
            'text':"""IF EXISTS (SELECT 1 FROM dw.FactAppointment f
    LEFT JOIN dw.DimPatient p ON p.PatientKey=f.PatientKey
    LEFT JOIN dw.DimDoctor d ON d.DoctorKey=f.DoctorKey
    LEFT JOIN dw.DimDate t ON t.DateKey=f.DateKey
    WHERE p.PatientKey IS NULL OR d.DoctorKey IS NULL OR t.DateKey IS NULL
       OR f.CostGBP < 0 OR f.EndsAtUtc <= f.StartsAtUtc)
    THROW 51010, 'Warehouse validation failed.', 1;
SELECT COUNT(*) AS ValidatedFactRows, COALESCE(SUM(CostGBP), 0) AS ValidatedCostGBP
FROM dw.FactAppointment;"""
        }],
        'scriptBlockExecutionTimeout':'00:02:00'
    }
})
activities.append({
    'name':'DatabricksLearningStep',
    'type':'DatabricksNotebook',
    'state':'Disabled',
    'policy':policy,
    'dependsOn':[{'activity':'ValidateWarehouse','dependencyConditions':['Succeeded']}],
    'linkedServiceName':{
        'type':'LinkedServiceReference',
        'referenceName':'LS_DatabricksLearning',
        'parameters':{
            'workspaceUrl':{'value':'https://REPLACE-WITH-WORKSPACE.azuredatabricks.net','type':'String'},
            'existingClusterId':{'value':'REPLACE-WITH-CLUSTER-ID','type':'String'}
        }
    },
    'typeProperties':{
        'notebookPath':'/Shared/etl-learning/validate-warehouse',
        'baseParameters':{
            'pipelineRunId':{'value':'@pipeline().RunId','type':'Expression'}
        }
    }
})
resource('pipelines','PL_DiamondSnowflake',{'concurrency':1,'annotations':['Synthetic clinical data','Full refresh staging; Type 1 dimensions; manual trigger'],'activities':activities},deps)
resources.append({
    'type':'Microsoft.DataFactory/factories/triggers',
    'apiVersion':'2018-06-01',
    'name':factory+'/TR_DiamondSnowflake_Daily',
    'dependsOn':[resource_id('pipelines','PL_DiamondSnowflake')],
    'properties':{
        'type':'ScheduleTrigger',
        'runtimeState':'Stopped',
        'typeProperties':{
            'recurrence':{
                'frequency':'Day',
                'interval':1,
                'startTime':'2026-09-14T02:00:00Z',
                'timeZone':'UTC'
            }
        },
        'pipelines':[{
            'pipelineReference':{
                'type':'PipelineReference',
                'referenceName':'PL_DiamondSnowflake'
            },
            'parameters':{}
        }]
    }
})
template={'$schema':'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#','contentVersion':'1.0.0.0','resources':resources,'outputs':{'factoryPrincipalId':{'type':'string','value':f"[reference({fid[1:-1]}, '2018-06-01', 'Full').identity.principalId]"}}}
(ROOT/'diamond-adf.json').write_text(json.dumps(template,indent=2)+'\n')
print('Generated snowflake migration and ADF template')
