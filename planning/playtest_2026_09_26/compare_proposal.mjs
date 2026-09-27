// Numeric design model, separate from the actual Godot playthroughs.
// Run: node planning/playtest_2026_09_26/compare_proposal.mjs [seeds=1000]
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {simulate} from './proposal_model.mjs';
const count=Number(process.argv[2]??1000);
const policies={good:{},eight:{great:true,learn:true,greatLimit:8},nine:{great:true,learn:true,greatLimit:9},favorites:{great:true,learn:true},mean:{forecast:'mean'},preserve:{preserve:true},two_bad:{mistakes:true},refuse:{refusal:true},low_rep:{repShockDay2:10},overbuy:{overbuy:true}};
const base={single:true,partial:true,topThreshold:71,starterOffal:0};
const settings={recommended:base,bad_refund:{...base,badRefund:true},fee70:{...base,fee:70},fee90:{...base,fee:90},fee100:{...base,fee:100},price40:{...base,price:40},price50:{...base,price:50}};
const result={scope:'Independent design model: fixed 7-day schedule, 9 cups Day1, paid starter210, no free starting stock, announced groups with count ranges; not the shipped game.',seeds:count,settings,policies,results:[]};
for(const [setting,cfg]of Object.entries(settings))for(const [policy,p]of Object.entries(policies)){
 if(setting!=='recommended'&&!['good','favorites','two_bad'].includes(policy))continue;
 const runs=Array.from({length:count},(_,i)=>simulate(i+1,cfg,p));
 const mean=f=>runs.reduce((s,r)=>s+f(r),0)/count;
 const cash=runs.map(r=>r.cash).sort((a,b)=>a-b);
 assert(runs.every(r=>r.rows[0].cash===495+9*((cfg.price??45)-45)-((cfg.fee??80)-80)),'starter210 day1 cash');
 result.results.push({setting,policy,cash:mean(r=>r.cash),p10:cash[Math.floor(count*.1)],p90:cash[Math.floor(count*.9)],
  rep:mean(r=>r.rep),served:mean(r=>r.served),spoil:mean(r=>r.spoiled),goodRate:mean(r=>r.goodRate),
  cash1500:mean(r=>Number(r.cash>=1500)),cash1600:mean(r=>Number(r.cash>=1600)),bankrupt:mean(r=>Number(r.fail))});
}
fs.writeFileSync(new URL('./proposal_results.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
console.table(result.results.map(r=>({setting:r.setting,policy:r.policy,cash:Math.round(r.cash),p10:r.p10,p90:r.p90,good:(100*r.goodRate).toFixed(1),target1500:(100*r.cash1500).toFixed(1),fail:r.bankrupt})));
