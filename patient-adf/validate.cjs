const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const read=name=>fs.readFileSync(path.join(__dirname,name),'utf8');
const arm=JSON.parse(read('azuredeploy.json'));
const example=JSON.parse(read('azuredeploy.parameters.example.json'));
let checks=0;
function check(name,fn){fn();checks++;console.log('PASS '+name);}
check('parameter example matches template',()=>{
 for(const name of Object.keys(example.parameters)) assert(name in arm.parameters,name);
 for(const [name,p] of Object.entries(arm.parameters))
  assert('defaultValue' in p || name in example.parameters,'Missing '+name);
 assert.notEqual(example.parameters.sourceDatabase.value,example.parameters.warehouseDatabase.value);
});
const resources=arm.resources;
const pipe=resources.find(r=>r.type.endsWith('/pipelines')).properties;
const [copy,load]=pipe.activities;
check('two databases and a factory identity are defined',()=>{
 assert.equal(resources.filter(r=>r.type.endsWith('/databases')).length,2);
 assert.equal(resources.find(r=>r.type==='Microsoft.DataFactory/factories').identity.type,'SystemAssigned');
});
check('datasets and activities resolve existing linked services',()=>{
 const linked=resources.filter(r=>r.type.endsWith('/linkedservices'));
 const datasets=resources.filter(r=>r.type.endsWith('/datasets'));
 for(const dataset of datasets) assert(linked.some(r=>r.name.includes('/'+dataset.properties.linkedServiceName.referenceName+"'")));
 for(const ref of [...copy.inputs,...copy.outputs]) assert(datasets.some(r=>r.name.includes('/'+ref.referenceName+"'")));
 assert(linked.some(r=>r.name.includes('/'+load.linkedServiceName.referenceName+"'")));
});
check('retries reset staging and warehouse loading requires successful copy',()=>{
 assert.equal(pipe.concurrency,1);
 assert.equal(copy.typeProperties.sink.preCopyScript,'EXEC etl.ResetStage;');
 assert.deepEqual(load.dependsOn,[{activity:copy.name,dependencyConditions:['Succeeded']}]);
 assert.equal(load.typeProperties.storedProcedureParameters.ExpectedRows.value.value,"@activity('CopyPatientSnapshot').output.rowsCopied");
 assert.equal(load.typeProperties.storedProcedureParameters.RunId.value.value,'@pipeline().RunId');
});
check('all ten source columns are explicitly mapped into staging',()=>{
 const mappings=copy.typeProperties.translator.mappings;
 assert.equal(mappings.length,10);
 assert.equal(new Set(mappings.map(m=>m.sink.name)).size,10);
 for(const m of mappings){
  assert.equal(m.source.name,m.sink.name);
  assert(read('sql/01-source.sql').includes(m.source.name));
  assert(read('sql/02-warehouse.sql').includes(m.sink.name));
 }
});
check('managed identity, encrypted connections, and manual execution',()=>{
 for(const r of resources.filter(r=>r.type.endsWith('/linkedservices'))){
  assert.equal(r.properties.typeProperties.authenticationType,'SystemAssignedManagedIdentity');
  assert.equal(r.properties.typeProperties.encrypt,'mandatory');
  assert.equal(r.properties.typeProperties.trustServerCertificate,false);
 }
 assert(!resources.some(r=>r.type.endsWith('/triggers')));
 assert.equal(arm.parameters.allowAzureServices.defaultValue,false);
});
console.log(`${checks} static checks passed. Azure deployment and SQL execution have NOT been tested.`);
