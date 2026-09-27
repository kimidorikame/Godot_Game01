import fs from 'node:fs';
import assert from 'node:assert/strict';
const result=JSON.parse(fs.readFileSync(new URL('./current_playthrough_results.json',import.meta.url)));
const rows=[];
let dayChecks=0;
for(const policy of result.policies){
 const rs=result.runs.filter(r=>r.policy===policy);
 for(const r of rs)for(const d of r.rows){
  assert.equal(d.served+d.unserved,d.demand,'demand accounting');
  assert.equal(d.sales,d.served*45,'sales accounting');
  assert.equal(Object.values(d.grades).reduce((a,b)=>a+b,0),d.served,'quality accounting');
  assert(d.cash>=0&&d.soup_left>=0,'nonnegative cash and soup');
  dayChecks++;
 }
 const mean=f=>rs.reduce((s,r)=>s+f(r),0)/rs.length;
 const cash=rs.map(r=>r.cash).sort((a,b)=>a-b);
 const sum=(r,key)=>r.rows.reduce((s,d)=>s+d[key],0);
 const quality=r=>r.rows.reduce((s,d)=>s+d.grades.GOOD+d.grades.GREAT,0)/r.rows.reduce((s,d)=>s+d.demand-(d.grades['']??0),0);
 rows.push({policy,n:rs.length,completed:rs.filter(r=>r.completed).length,stalled:rs.filter(r=>r.stalled).length,
  meanCash:mean(r=>r.cash),minCash:cash[0],maxCash:cash.at(-1),p10:cash[Math.floor(cash.length*.1)],p90:cash[Math.floor(cash.length*.9)],
  rep:mean(r=>r.rep),goodRate:mean(quality),served:mean(r=>sum(r,'served')),unserved:mean(r=>sum(r,'unserved')),
  spoiled:mean(r=>sum(r,'spoiled_value')),target1500:mean(r=>Number(r.cash>=1500)),target1600:mean(r=>Number(r.cash>=1600)),
  clicks:mean(r=>r.clicks),textSteps:mean(r=>r.actions.next_text_event??0),day1Cash:mean(r=>r.rows[0]?.cash??0),
  day1Good:mean(r=>r.rows[0]?.grades.GOOD??0),day1Served:mean(r=>r.rows[0]?.served??0)});
}
const summary={commit:result.commit,seeds:result.seeds,totalRuns:result.runs.length,dayAccountingChecks:dayChecks,policies:rows};
fs.writeFileSync(new URL('./playthrough_summary.json',import.meta.url),JSON.stringify(summary,null,2)+'\n');
console.table(rows.map(r=>({policy:r.policy,runs:r.n,complete:r.completed,stalled:r.stalled,cash:Math.round(r.meanCash),min:r.minCash,max:r.maxCash,good:(100*r.goodRate).toFixed(1),rep:r.rep.toFixed(1),served:r.served.toFixed(1),unserved:r.unserved.toFixed(1),target1500:(100*r.target1500).toFixed(1),clicks:Math.round(r.clicks)})));
console.log('days validated',dayChecks);
