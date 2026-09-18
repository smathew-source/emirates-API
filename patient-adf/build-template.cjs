// Generate a resource-group ARM template. No Azure calls or dependencies.
const fs = require('node:fs');
const path = require('node:path');
const p = name => `[parameters('${name}')]`;
const factoryId = "[resourceId('Microsoft.DataFactory/factories', parameters('factoryName'))]";
const serverId = "[resourceId('Microsoft.Sql/servers', parameters('sqlServerName'))]";
const childName = name => `[concat(parameters('factoryName'), '/${name}')]`;
const childId = (kind,name) => `[resourceId('Microsoft.DataFactory/factories/${kind}', parameters('factoryName'), '${name}')]`;
const ref = (type,name) => ({type,referenceName:name});
const policy = {timeout:'0.00:30:00',retry:2,retryIntervalInSeconds:30,secureInput:true,secureOutput:true};
const template = {
 $schema:'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#',
 contentVersion:'1.0.0.0',
 parameters:{
  location:{type:'string',defaultValue:'[resourceGroup().location]'},
  factoryName:{type:'string'},sqlServerName:{type:'string'},
  sourceDatabase:{type:'string',defaultValue:'PatientSource'},
  warehouseDatabase:{type:'string',defaultValue:'PatientWarehouse'},
  entraAdminName:{type:'string'},entraAdminObjectId:{type:'string'},
  entraAdminPrincipalType:{type:'string',defaultValue:'User',allowedValues:['User','Group']},
  operatorIPv4:{type:'string',metadata:{description:'Your public IPv4 for SQL setup. No broad client firewall range.'}},
  allowAzureServices:{type:'bool',defaultValue:false,metadata:{description:'Demo only: permits public Azure-origin connections, still requiring SQL authentication. Set true for the default Azure IR or configure private networking before running.'}}
 },
 resources:[
  {type:'Microsoft.Sql/servers',apiVersion:'2023-08-01',name:p('sqlServerName'),location:p('location'),properties:{
    version:'12.0',minimalTlsVersion:'1.2',publicNetworkAccess:'Enabled',
    administrators:{administratorType:'ActiveDirectory',azureADOnlyAuthentication:true,
     login:p('entraAdminName'),sid:p('entraAdminObjectId'),tenantId:'[subscription().tenantId]',principalType:p('entraAdminPrincipalType')}
  }},
  ...['sourceDatabase','warehouseDatabase'].map(db=>({
   type:'Microsoft.Sql/servers/databases',apiVersion:'2023-08-01',
   name:`[concat(parameters('sqlServerName'), '/', parameters('${db}'))]`,location:p('location'),
   dependsOn:[serverId],sku:{name:'Basic',tier:'Basic',capacity:5},
   properties:{collation:'SQL_Latin1_General_CP1_CI_AS',maxSizeBytes:2147483648}
  })),
  {type:'Microsoft.Sql/servers/firewallRules',apiVersion:'2023-08-01',
   name:"[concat(parameters('sqlServerName'), '/OperatorSetup')]",dependsOn:[serverId],
   properties:{startIpAddress:p('operatorIPv4'),endIpAddress:p('operatorIPv4')}},
  {condition:p('allowAzureServices'),type:'Microsoft.Sql/servers/firewallRules',apiVersion:'2023-08-01',
   name:"[concat(parameters('sqlServerName'), '/AllowAzureServicesDemo')]",dependsOn:[serverId],
   properties:{startIpAddress:'0.0.0.0',endIpAddress:'0.0.0.0'}},
  {type:'Microsoft.DataFactory/factories',apiVersion:'2018-06-01',name:p('factoryName'),
   location:p('location'),identity:{type:'SystemAssigned'},properties:{}}
 ],
 outputs:{
  sqlHost:{type:'string',value:"[concat(parameters('sqlServerName'), '.database.windows.net')]"},
  factoryPrincipalId:{type:'string',value:"[reference(resourceId('Microsoft.DataFactory/factories', parameters('factoryName')), '2018-06-01', 'Full').identity.principalId]"},
  pipelineName:{type:'string',value:'PL_PatientWarehouse'}
 }
};
for (const [name,db] of [['LS_PatientSource','sourceDatabase'],['LS_PatientWarehouse','warehouseDatabase']]) {
 template.resources.push({type:'Microsoft.DataFactory/factories/linkedservices',apiVersion:'2018-06-01',
  name:childName(name),dependsOn:[factoryId,`[resourceId('Microsoft.Sql/servers/databases', parameters('sqlServerName'), parameters('${db}'))]`],
  properties:{type:'AzureSqlDatabase',typeProperties:{
   server:"[concat(parameters('sqlServerName'), '.database.windows.net')]",database:p(db),
   authenticationType:'SystemAssignedManagedIdentity',encrypt:'mandatory',trustServerCertificate:false
  }}
 });
}
for (const [name,ls,schema,table] of [
 ['DS_PatientExtract','LS_PatientSource','dbo','vPatientExtract'],
 ['DS_PatientStage','LS_PatientWarehouse','stg','PatientExtract']]) {
 template.resources.push({type:'Microsoft.DataFactory/factories/datasets',apiVersion:'2018-06-01',
  name:childName(name),dependsOn:[childId('linkedservices',ls)],
  properties:{linkedServiceName:ref('LinkedServiceReference',ls),type:'AzureSqlTable',schema:[],typeProperties:{schema,table}}
 });
}
template.resources.push({type:'Microsoft.DataFactory/factories/pipelines',apiVersion:'2018-06-01',
 name:childName('PL_PatientWarehouse'),
 dependsOn:[childId('datasets','DS_PatientExtract'),childId('datasets','DS_PatientStage')],
 properties:{concurrency:1,annotations:['Synthetic patient demo','Manual trigger','Full extract; Type 1 dimensions'],activities:[
  {name:'CopyPatientSnapshot',type:'Copy',policy,
   inputs:[ref('DatasetReference','DS_PatientExtract')],outputs:[ref('DatasetReference','DS_PatientStage')],
   typeProperties:{source:{type:'AzureSqlSource',sqlReaderQuery:'SELECT PatientId,GivenName,FamilyName,DateOfBirth,City,EncounterId,EncounterDate,DepartmentId,DepartmentName,CostGBP FROM dbo.vPatientExtract',queryTimeout:'00:10:00',partitionOption:'None'},
    sink:{type:'AzureSqlSink',preCopyScript:'EXEC etl.ResetStage;',writeBehavior:'insert',sqlWriterUseTableLock:false},
    enableStaging:false,translator:{type:'TabularTranslator',typeConversion:true,
     mappings:['PatientId','GivenName','FamilyName','DateOfBirth','City','EncounterId','EncounterDate','DepartmentId','DepartmentName','CostGBP'].map(name=>({source:{name},sink:{name}}))}
   }},
  {name:'LoadDimensionsAndFacts',type:'SqlServerStoredProcedure',policy,
   dependsOn:[{activity:'CopyPatientSnapshot',dependencyConditions:['Succeeded']}],
   linkedServiceName:ref('LinkedServiceReference','LS_PatientWarehouse'),
   typeProperties:{storedProcedureName:'etl.LoadPatientWarehouse',storedProcedureParameters:{
    RunId:{value:{value:'@pipeline().RunId',type:'Expression'},type:'Guid'},
    ExpectedRows:{value:{value:"@activity('CopyPatientSnapshot').output.rowsCopied",type:'Expression'},type:'Int32'}
   }}}
 ]}
});
fs.writeFileSync(path.join(__dirname,'azuredeploy.json'),JSON.stringify(template,null,2)+'\n');
console.log(`Generated azuredeploy.json with ${template.resources.length} resources.`);
