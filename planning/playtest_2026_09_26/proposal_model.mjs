// Independent planning model; does not load or modify the Godot game.
// Run: node planning/balance_comparison.mjs [number-of-seeds=1000]
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const ITEMS = {
 hot: [5,5,false,'HOT'], mellow:[5,3,true,'MELLOW'], sour:[4,5,false,'SOUR'],
 bitter:[4,3,true,'BITTER'], savory:[5,5,false,'SAVORY'],
 meat:[8,3,true,'POWER'], offal:[10,3,true,'POWER'], tofu:[8,3,true,'GENTLE'],
 melon:[10,5,false,'GENTLE'], wrapper:[6,3,true,'FILLING'], noodle:[8,5,false,'FILLING'],
 cartilage:[8,3,true,'BITE'], ear:[10,5,false,'BITE'], tendon:[12,3,true,'POWER','BITE'],
 clam:[16,3,true,'TREAT'], shrimp:[18,3,true,'TREAT'], maw:[20,5,false,'TREAT'],
};
const MAIN = {
 delivery:['hot','POWER','tofu'], thug:['mellow','GENTLE','meat'],
 granny:['savory','FILLING','offal'], officer:['sour','BITE','noodle'],
 lady:['bitter','TREAT','sour'], streamer:['mellow','BITE','shrimp'],
};
const MOB = [
 ['hot','POWER','FILLING'], ['savory','BITE','GENTLE'], ['mellow','GENTLE','POWER'],
 ['sour','FILLING','GENTLE'], ['bitter','GENTLE','FILLING'],
 ['hot','FILLING','POWER'], ['savory','TREAT','BITE'],
];
const DAYS = [
 ['delivery','thug','granny'], ['officer','delivery','granny'], ['lady','thug','officer'],
 ['streamer','granny','delivery'], ['officer','lady','thug'],
 ['streamer','officer','lady'], ['delivery','streamer','granny'],
];
// starterOffal: 初日セットのモツ個数を明示指定する（未指定なら従来どおり single/starterSingle から決まる）。
// 0＝初見向けセット210、1＝好物既知向けセット222、3＝旧稿240。
const DEFAULT = {single:false, fee:80, freshDays:2, price:45, topThreshold:75, starterSingle:true, partial:false};
const VARIANTS = {
 original:{...DEFAULT}, single_favorites:{...DEFAULT,single:true},
 top74_only:{...DEFAULT,topThreshold:74},
 single_store_only:{...DEFAULT,single:true,starterSingle:false},
 single_top74:{...DEFAULT,single:true,topThreshold:74},
 recommended:{...DEFAULT,single:true,topThreshold:74,partial:true},
 single_top73:{...DEFAULT,single:true,topThreshold:73},
 single_daily70:{...DEFAULT,single:true,fee:70},
 single_fresh3:{...DEFAULT,single:true,freshDays:3},
 single_price50:{...DEFAULT,single:true,price:50},
 // 2026-09-23の独立監査で採用した条件。境界71＋小口＋部分提供。
 // recommended71 は初日セット222（モツ1）、…_starter210 は初見向けセット210（モツ0）。
 recommended71:{...DEFAULT,single:true,topThreshold:71,partial:true},
 recommended71_starter210:{...DEFAULT,single:true,topThreshold:71,partial:true,starterOffal:0},
};
const POLICIES = {
 good:{}, great:{great:true}, first_great:{great:true,learn:true},
 balanced_eight:{great:true,learn:true,greatLimit:8},
 preserve:{preserve:true}, mean_good:{forecast:'mean'},
 two_bad:{mistakes:true}, refuse_group:{refusal:true}, all_stock:{overbuy:true},
  mob_extra:{great:true,mobExtra:true}, low_rep:{repShockDay2:10},
};
// Stateless random draws: changing a policy never consumes other streams' draws.
function draw(seed,day,stream) {
 let x=(seed ^ Math.imul(day,0x9e3779b9) ^ Math.imul(stream,0x85ebca6b))>>>0;
 x=Math.imul(x^(x>>>16),0x7feb352d); x=Math.imul(x^(x>>>15),0x846ca68b);
 return ((x^(x>>>16))>>>0)/4294967296;
}
const center = (r,cfg) => r<20?7:r<45?9:r<60?11:r<cfg.topThreshold?14:17;
const prepFor = n => n<=12?8:n<=15?11:14;
const qty = (inv,id,day,cfg,damaged=false) => inv.filter(b=>b.id===id &&
 (!ITEMS[id][2] || (damaged ? day-b.day===cfg.freshDays : day-b.day<cfg.freshDays)))
 .reduce((s,b)=>s+b.n,0);
const stockValue = inv => inv.reduce((s,b)=>s+b.n*b.unit,0);
function take(inv,id,n,day,cfg) {
 assert(qty(inv,id,day,cfg)>=n,`stock underflow ${id}`);
 let cost=0;
 for(const b of inv) {
  if(b.id!==id || (ITEMS[id][2]&&day-b.day>=cfg.freshDays))continue;
  const k=Math.min(n,b.n); b.n-=k; n-=k; cost+=k*b.unit;
  if(!n)break;
 }
 return cost;
}
function quote(id,short,cfg) {
 if(short<=0)return {cost:0,units:[]};
 const [unit,pack]=ITEMS[id];
 let best={cost:Math.ceil(short/pack)*pack*unit,units:[[Math.ceil(short/pack)*pack,unit]]};
 if(cfg.single && ['offal','shrimp'].includes(id)) {
  const packs=Math.floor(short/pack),singles=short%pack;
  const cost=packs*pack*unit+singles*(unit+2);
  if(cost<best.cost)best={cost,units:[[packs*pack,unit],[singles,unit+2]].filter(x=>x[0])};
 }
 return best;
}
function choose(inv,tag,n,day,cfg,policy,availableOnly=false) {
 const ids=Object.keys(ITEMS).filter(id=>ITEMS[id].slice(3).includes(tag));
 const candidates=ids.map(id=>({id,have:qty(inv,id,day,cfg),
  cost:quote(id,Math.max(0,n-qty(inv,id,day,cfg)),cfg).cost}));
 if(availableOnly)return candidates.filter(x=>x.have>=n)
  .sort((a,b)=>Number(ITEMS[b.id][2])-Number(ITEMS[a.id][2])||ITEMS[a.id][0]-ITEMS[b.id][0])[0]?.id;
 // Use already held stock first. When buying, the preservation policy prefers shelf-stable goods.
 candidates.sort((a,b)=>(a.have>=n?0:1)-(b.have>=n?0:1)||
  (policy.preserve?Number(ITEMS[a.id][2])-Number(ITEMS[b.id][2]):0)||a.cost-b.cost||ITEMS[a.id][0]-ITEMS[b.id][0]);
 return candidates[0].id;
}
function allocation(n,day) {
 const m=n-3,g=Math.ceil(m/4),groups=Array.from({length:g},(_,i)=>Math.floor(m/g)+(i<m%g?1:0));
 const phase=i=>day===7?(i<Math.ceil(g/2)?0:1):g===1?1:g===2?i:g===3?i:i===0||i===1?0:i-1;
 return groups.map((count,i)=>({count,phase:phase(i),group:i}));
}
function ordersFor(n,day,types) {
 if(day===1)return [
  {phase:0,n:2,key:'delivery',main:true,...recipe(MAIN.delivery)},
  {phase:0,n:1,key:'takeout',main:false,takeout:true,taste:'mellow',tag:'GENTLE'},
  {phase:0,n:2,key:'mob0',group:0,...recipe(MOB[0],true)},
  {phase:1,n:1,key:'thug',main:true,...recipe(MAIN.thug)},
  {phase:1,n:2,key:'mob1',group:1,...recipe(MOB[2],true)},
  {phase:2,n:1,key:'granny',main:true,...recipe(MAIN.granny)},
 ];
 const groups=allocation(n,day);
 const out=[];
 for(let p=0;p<3;p++) {
  const key=DAYS[day-1][p]; out.push({phase:p,n:1,key,main:true,...recipe(MAIN[key])});
  for(const g of groups.filter(x=>x.phase===p))out.push({phase:p,n:g.count,key:`mob${g.group}`,group:g.group,...recipe(MOB[types[g.group]],true)});
 }
 return out;
}
function recipe(arr,mob=false) {return {taste:arr[0],tag:arr[1],...(mob?{extra:arr[2]}:{favorite:arr[2]})};}
function potStep(pot,order) {
 const p={...pot};
 if(order.phase!==p.phase) {if(order.phase===2)p.s++; p.phase=order.phase;}
 while(p.v<order.n) {
  if(p.w===2||p.s<2||p.v+2>14)return null;
  p.w++; p.v+=2; p.s-=2;
  if(p.s<2) {if(p.d===0)return null;p.d--;p.used++;p.s+=2;}
 }
 if(p.s<2) {if(!p.d)return null;p.d--;p.used++;p.s+=2;}
 if(p.s>4)return null;
 p.v-=order.n;
 return p;
}
function requiredDoses(prep,orders) {
 let pot={v:prep,s:3,w:0,d:8,used:0,phase:0};
 for(const o of orders){pot=potStep(pot,o);if(!pot)return 99;}
 return pot.used;
}
export function simulate(seed,config={},policy={}) {
 const cfg={...DEFAULT,...config};
 let cash=600,rep=policy.initialRep??30,inv=[],doses=0;
 let income=0,purchases=0,foodPurchases=0,consumed=0,spoiled=0,fixed=0,potCosts=0,usedDoses=0;
 let demand=0,served=0,good=0,greatCups=0,greatVisits=0,fail=false,minCash=600;
 const known=new Set(policy.learn?[]:Object.keys(MAIN)),rows=[];
 let denied=0,water=0,endingSoup=0;
 function buy(id,n,day) {
  const q=quote(id,n,cfg); if(q.cost>cash)return false;
  cash-=q.cost;purchases+=q.cost;foodPurchases+=q.cost;
  for(const [count,unit]of q.units)inv.push({id,n:count,day,unit});
  return true;
 }
 for(let day=1;day<=7;day++) {
  if(day===2&&policy.repShockDay2!==undefined)rep=policy.repShockDay2;
  const openCash=cash,openRep=rep,openPurchases=purchases,openSpoiled=spoiled;
  const valid=[];
  for(const b of inv) {if(ITEMS[b.id][2]&&day-b.day>=cfg.freshDays+1)spoiled+=b.n*b.unit;else valid.push(b);}
  inv=valid;
  const mid=center(rep,cfg),u=draw(seed,day,1),n=day===1?9:mid+(u<.25?-1:u<.75?0:1);
  const g=day===1?2:allocation(n,day).length;
  const types=Array.from({length:g},(_,i)=>Math.floor(draw(seed,day,10+i)*7));
  const orders=ordersFor(n,day,types);demand+=n;
  // Only same-day announced party types and party-size intervals are visible to buying policy.
  const candidates=day===1?[9]:[mid-1,mid,mid+1].filter(k=>allocation(k,day).length===g);
  const weights=candidates.map(k=>k===mid?.5:.25);
  const meanForecast=Math.round(candidates.reduce((s,k,i)=>s+k*weights[i],0)/weights.reduce((s,w)=>s+w,0));
  const forecastN=policy.forecast==='mean'?meanForecast:Math.max(...candidates);
  const forecast=ordersFor(forecastN,day,types);
  const plannedRecipes=new Map();
  const plannedExtras=new Map();
  const prep=prepFor(day===1?9:mid+1),fees=cfg.fee+(day===1?140:0);
  let dayPoints=0,dayServed=0,dayGood=0,dayGreat=0,dayDenied=0;
  if(cash<fees+prep*10) {
   fail=true;rep=Math.round(rep*.7);denied+=n;
   rows.push({day,openCash,rep,openRep,n,served:0,closed:true,cash});continue;
  }
  cash-=fees+prep*10;fixed+=fees;potCosts+=prep*10;
  if(day===1) {
   for(const [id,k]of Object.entries({hot:5,mellow:6,savory:5,meat:6,tofu:6,wrapper:3,
    offal:cfg.starterOffal??(cfg.single&&cfg.starterSingle?1:3)}))assert(buy(id,k,day));
   cash-=16;purchases+=16;doses++;
  } else {
   // Pot forecast uses visible upper range, not actual party counts. Unused doses carry over.
   const want=Math.max(...candidates.map(k=>requiredDoses(prep,ordersFor(k,day,types))));
   const more=Math.max(0,want-doses);assert(more<5);
   const affordable=Math.min(more,Math.floor(cash/16));
   cash-=affordable*16;purchases+=affordable*16;doses+=affordable;
   // Reserve forecast portions virtually while buying, preventing repeated reuse of the same stock.
   const reserved=[];
   function reserve(id,count) {
    const already=reserved.filter(x=>x.id===id).reduce((s,x)=>s+x.n,0);
    const short=Math.max(0,count+already-qty(inv,id,day,cfg));
    if(short&&!buy(id,short,day))return false;
    reserved.push({id,n:count});return true;
   }
   function freeInventory() {
    const free=structuredClone(inv);for(const r of reserved)take(free,r.id,r.n,day,cfg);return free;
   }
   for(const o of forecast) {
    if(!reserve(o.taste,o.n))continue;
    const id=choose(freeInventory(),o.tag,o.n,day,cfg,policy);
    if(reserve(id,o.n))plannedRecipes.set(o.key,id);
   }
   if(policy.great)for(const o of forecast.filter(o=>o.main&&known.has(o.key)).slice(0,Math.max(0,(policy.greatLimit??99)-greatVisits)))reserve(o.favorite,o.n);
   if(policy.mobExtra)for(const o of forecast.filter(o=>o.extra)) {
    const id=choose(freeInventory(),o.extra,o.n,day,cfg,policy);
    if(reserve(id,o.n))plannedExtras.set(o.key,id);
   }
   if(policy.overbuy)for(const id of Object.keys(ITEMS))buy(id,ITEMS[id][1],day);
  }
  minCash=Math.min(minCash,cash);
  let pot={v:prep,s:3,w:0,d:doses,used:0,phase:0};
  for(const originalOrder of orders) {
   let o=originalOrder;
   const wasKnown=known.has(o.key);
   if(o.main)known.add(o.key);
   let refused=policy.refusal&&day===3&&o.group===0;
   const plannedTop=plannedRecipes.get(o.key);
   const selectTop=count=>plannedTop&&qty(inv,plannedTop,day,cfg)>=count?plannedTop:choose(inv,o.tag,count,day,cfg,policy,true);
   let top=selectTop(o.n),next=potStep(pot,o);
   if(!refused && cfg.partial && o.extra && (!top||qty(inv,o.taste,day,cfg)<o.n||!next)) {
    for(let n=o.n-1;n>=1;n--) {
     const t=selectTop(n),p=potStep(pot,{...o,n});
     if(t&&qty(inv,o.taste,day,cfg)>=n&&p){o={...o,n};top=t;next=p;break;}
    }
   }
   if(!top||qty(inv,o.taste,day,cfg)<o.n||!next)refused=true;
   if(refused){denied+=o.n;dayDenied+=o.n;continue;}
   denied+=originalOrder.n-o.n;dayDenied+=originalOrder.n-o.n;
   pot=next;
   consumed+=take(inv,o.taste,o.n,day,cfg)+take(inv,top,o.n,day,cfg);
   let score=75;
   if(policy.great&&o.main&&wasKnown&&greatVisits<(policy.greatLimit??99)&&qty(inv,o.favorite,day,cfg)>=o.n) {
    consumed+=take(inv,o.favorite,o.n,day,cfg);score=100;greatVisits++;
   }
   if(policy.mobExtra&&o.extra) {
    const plannedExtra=plannedExtras.get(o.key);
    const extra=plannedExtra&&qty(inv,plannedExtra,day,cfg)>=o.n?plannedExtra:choose(inv,o.extra,o.n,day,cfg,policy,true);
    if(extra){consumed+=take(inv,extra,o.n,day,cfg);score=100;}
   }
   if(policy.mistakes&&((day===3&&o.main&&o.phase===0)||(day===4&&o.group===0)))score=0;
   // Candidate only: list price stays fixed, BAD dishes refund their sales fully.
   const earned=o.n*(cfg.badRefund&&score===0?0:cfg.price);
   income+=earned;cash+=earned;served+=o.n;dayServed+=o.n;
   if(score>=75){good+=o.n;dayGood+=o.n;}
   if(score===100){greatCups+=o.n;dayGreat+=o.n;}
   dayPoints+=score*o.n;
  }
  doses=pot.d;usedDoses+=pot.used;water+=pot.w;endingSoup+=pot.v;
  rep=Math.round(rep*.7+.3*dayPoints/n);
  inv=inv.filter(b=>b.n>0);
  rows.push({day,openCash,openRep,n,forecastN,prep,served:dayServed,good:dayGood,great:dayGreat,
   denied:dayDenied,purchases:purchases-openPurchases,spoiled:spoiled-openSpoiled,water:pot.w,
   usedDoses:pot.used,rep,cash,stock:stockValue(inv)+doses*16});
 }
 const stock=stockValue(inv)+doses*16;
 const profit=income-consumed-spoiled-fixed-potCosts-usedDoses*16;
 assert.equal(cash,600+income-purchases-fixed-potCosts,'cash identity');
 assert.equal(cash+stock,600+profit,'cash + closing stock = initial capital + profit');
 assert.equal(foodPurchases,consumed+spoiled+stockValue(inv),'food inventory identity');
 assert.equal(demand,served+denied,'every potential order is served or unserved');
 assert(inv.every(b=>b.n>=0)&&cash>=0&&doses>=0,'nonnegative state');
 return {seed,cash,stock,profit,rep,demand,served,goodRate:good/demand,greatCups,greatVisits,
  refusedRate:denied/demand,spoilRate:foodPurchases?spoiled/foodPurchases:0,spoiled,foodPurchases,
  income,purchases,fail,minCash,water,endingSoup,day7High:rows[6].n>=16,rows};
}
function summary(runs) {
 const mean=f=>runs.reduce((s,r)=>s+f(r),0)/runs.length;
 const quantile=(key,p)=>runs.map(r=>r[key]).sort((a,b)=>a-b)[Math.floor((runs.length-1)*p)];
 return {runs:runs.length,meanCash:mean(r=>r.cash),cashP10:quantile('cash',.1),cashMedian:quantile('cash',.5),
  cashP90:quantile('cash',.9),meanProfit:mean(r=>r.profit),meanStock:mean(r=>r.stock),
  meanRep:mean(r=>r.rep),meanCups:mean(r=>r.served),goodRate:mean(r=>r.goodRate),
  refusedRate:mean(r=>r.refusedRate),spoilRate:mean(r=>r.spoilRate),meanSpoiled:mean(r=>r.spoiled),
  meanGreatVisits:mean(r=>r.greatVisits),bankruptRate:mean(r=>Number(r.fail)),
  day7HighRate:mean(r=>Number(r.day7High)),
  belowInitialCashRate:mean(r=>Number(r.cash<600)),cash1500Rate:mean(r=>Number(r.cash>=1500)),
  cash1200Rate:mean(r=>Number(r.cash>=1200)),quality85Rate:mean(r=>Number(r.goodRate>=.85)),
  minOpeningAfterShopping:Math.min(...runs.map(r=>r.minCash))};
}
function checks() {
 assert.equal(quote('shrimp',1,DEFAULT).cost,54);
 assert.equal(quote('shrimp',1,{...DEFAULT,single:true}).cost,20);
 assert.equal(quote('shrimp',3,{...DEFAULT,single:true}).cost,54);
 assert.equal(qty([{id:'tofu',n:3,day:1,unit:8}],'tofu',3,DEFAULT),0);
 assert.equal(qty([{id:'tofu',n:3,day:1,unit:8}],'tofu',3,DEFAULT,true),3);
 assert.equal(requiredDoses(14,ordersFor(18,7,[0,1,2,3])),2);
 assert.equal(requiredDoses(8,ordersFor(9,1,[])),0);
 const day1=simulate(1,{}, {great:true}).rows[0];
 assert.equal(day1.cash,465);assert.equal(day1.stock,91);assert.equal(day1.good,9);
 const newcomer=simulate(1,{}, {great:true,learn:true});assert.equal(newcomer.rows[0].great,0);
 assert(simulate(1,{fee:999}).fail,'insufficient capital must close the business');
 return 12;
}
function reputationPaths(topThreshold,learn) {
 const paths=[];
 function walk(day,rep,weight,cups,day7Rep) {
  if(day===8){paths.push({weight,cups,day7Rep});return;}
  for(const [noise,w]of day===1?[[0,1]]:[[-1,.25],[0,.5],[1,.25]]) {
   const n=day===1?9:center(rep,{topThreshold})+noise;
   const great=learn?[0,2,2,2,3,3,3][day-1]:(day===1?4:3);
   walk(day+1,Math.round(.7*rep+.3*(75+25*great/n)),weight*w,cups+n,day===7?rep:day7Rep);
  }
 }
 walk(1,30,1,0,null);
 return {paths:paths.length,probabilityMass:paths.reduce((s,p)=>s+p.weight,0),
  day7OpeningRepRange:[Math.min(...paths.map(p=>p.day7Rep)),Math.max(...paths.map(p=>p.day7Rep))],
  day7HighProbability:paths.reduce((s,p)=>s+p.weight*Number(p.day7Rep>=topThreshold),0),
  meanCups:paths.reduce((s,p)=>s+p.weight*p.cups,0)};
}
export function runComparison(count=1000) {
 const result={modelVersion:2,seeds:count,selfChecks:checks(),variants:VARIANTS,policies:POLICIES,results:{},examples:{},
  reputationEnumeration:{firstTime75:reputationPaths(75,true),firstTime74:reputationPaths(74,true),experienced75:reputationPaths(75,false)}};
 for(const [name,cfg]of Object.entries(VARIANTS)) {
  result.results[name]={};
  for(const [p,policy]of Object.entries(POLICIES)) {
   const runs=Array.from({length:count},(_,i)=>simulate(i+1,cfg,policy));
   result.results[name][p]=summary(runs);
   if(p==='great'||p==='first_great')result.examples[`${name}_${p}`]=runs[0];
  }
 }
 return result;
}
if(process.argv[1]===fileURLToPath(import.meta.url)) {
 const n=Number(process.argv[2]??1000);assert(Number.isInteger(n)&&n>0);
 const result=runComparison(n);
 fs.writeFileSync(new URL('./balance_comparison_results.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
 for(const [v,ps]of Object.entries(result.results))for(const [p,r]of Object.entries(ps))
  console.log(`${v.padEnd(17)} ${p.padEnd(13)} cash=${r.meanCash.toFixed(0)} p10=${r.cashP10} good=${(100*r.goodRate).toFixed(1)}% loss=${(100*r.spoilRate).toFixed(1)}% fail=${(100*r.bankruptRate).toFixed(1)}% rep=${r.meanRep.toFixed(1)} great=${r.meanGreatVisits.toFixed(1)}`);
}
