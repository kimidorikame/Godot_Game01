// Standalone planning arithmetic, NOT Godot implementation.
// Run: node planning/balance_model.mjs
// Assumptions: all orders filled, optimal pot actions, no spoilage/purchase rounding.
function scheduledOrders(n, day) {
 if(day===1)return [[3,2],[1,2],[1]];
 const total=n-3,g=Math.ceil(total/4),arr=Array.from({length:g},(_,i)=>Math.floor(total/g)+(i<total%g?1:0));
 let slots=[[],[],[]];
 if(day===7){arr.forEach((v,i)=>slots[i<Math.ceil(g/2)?0:1].push(v));}
 else if(g===1)slots[1]=arr;
 else if(g===2){slots[0]=[arr[0]];slots[1]=[arr[1]];}
 else if(g===3)slots=arr.map(v=>[v]);
 else slots=[[arr[0],arr[1]],[arr[2]],[arr[3]]];
 return slots.map(x=>[1,...x]);
}

function cheapestPot(prep,n,day){
 let states=[{v:prep,s:3,w:0,b:0}];
 function closure(input){
   const best=new Map(),queue=[...input];
   while(queue.length){
    const z=queue.shift(),key=[z.v,z.s,z.w].join(",");
    if(best.has(key)&&best.get(key).b<=z.b)continue;
    best.set(key,z);
    if(z.w<2 && z.s>=2 && z.v+2<=14)queue.push({...z,v:z.v+2,s:z.s-2,w:z.w+1});
    if(z.s+2<=5)queue.push({...z,s:z.s+2,b:z.b+1});
   }
   return [...best.values()];
 }
 const slots=scheduledOrders(n,day);
 slots.forEach((orders,p)=>{
  if(p===2)states=states.map(x=>({...x,s:x.s+1})).filter(x=>x.s<=5);
  for(const count of orders)states=closure(states).filter(x=>x.v>=count&&x.s>=2&&x.s<=4).map(x=>({...x,v:x.v-count}));
 });
 states.sort((a,b)=>a.b-b.b||a.w-b.w);
 if(!states[0])throw Error(`no path ${prep},${n},${day}`);
 return {baseCost:prep*10+states[0].b*16,concentrate:states[0].b,water:states[0].w,orders:slots};
}

function meanDemand(r) { return r < 20 ? 7 : r < 45 ? 9 : r < 60 ? 11 : r < 75 ? 14 : 17; }
const main = [63, 36, 45, 37, 45, 45, 37];
const favorites = [34, 26, 20, 36, 20, 30, 36];
const meanMob = 93 / 7; // Seven uniformly selected types: 13,13,13,10,12,11,21.
const result = {};
for (const strategy of ["GOOD", "MAIN_GREAT"]) {
  const great = strategy === "MAIN_GREAT";
  let reputation = 30;
  const representativeDays = [];
  function dayResult(day, rep, noise) {
    const cups = day === 1 ? 9 : meanDemand(rep) + noise;
    const forecastHigh = day === 1 ? 9 : meanDemand(rep) + 1;
    const prep = forecastHigh <= 12 ? 8 : forecastHigh <= 15 ? 11 : 14;
    const pot = cheapestPot(prep, cups, day);
    const quality = 75 + (great ? 25 * (day === 1 ? 4 : 3) / cups : 0);
    const ingredients = main[day - 1] + (day === 1 ? 52 : (cups - 3) * meanMob)
      + (great ? favorites[day - 1] : 0);
    const nextRep = Math.floor(0.7 * rep + 0.3 * quality + 0.5);
    return { day, openingRep: rep, cups, prep, ...pot, quality, nextRep,
      ingredients, profit: cups * 45 - ingredients - pot.baseCost - 80 - 20 };
  }
  for (let day = 1; day <= 7; day++) {
    const row = dayResult(day, reputation, 0);
    representativeDays.push(row);
    reputation = row.nextRep;
  }
  const cases = [];
  function enumerate(day, rep, probability, cups, profit, day7High) {
    if (day === 8) { cases.push({ probability, cups, profit, rep, day7High }); return; }
    for (const [noise, chance] of day === 1 ? [[0, 1]] : [[-1, .25], [0, .5], [1, .25]]) {
      const row = dayResult(day, rep, noise);
      enumerate(day + 1, row.nextRep, probability * chance, cups + row.cups,
        profit + row.profit, day === 7 ? rep >= 75 : day7High);
    }
  }
  enumerate(1, 30, 1, 0, 0, false);
  const weighted = fn => cases.reduce((sum, x) => sum + x.probability * fn(x), 0);
  result[strategy] = {
    representativeDays,
    representativeTotals: {
      cups: representativeDays.reduce((s, x) => s + x.cups, 0),
      profit: representativeDays.reduce((s, x) => s + x.profit, 0)
    },
    enumeration: {
      cases: cases.length, probabilityMass: weighted(() => 1),
      meanCups: weighted(x => x.cups), meanProfit: weighted(x => x.profit),
      meanClosingRep: weighted(x => x.rep),
      day7HighDemandProbability: weighted(x => Number(x.day7High)),
      cupsRange: [Math.min(...cases.map(x => x.cups)), Math.max(...cases.map(x => x.cups))]
    }
  };
}
result.boundaries = {
  finalDay18Cups: cheapestPot(14, 18, 7),
  earlyRush10Cups: cheapestPot(8, 10, 2),
  starterBasket: 224, starterConcentrate: 16,
  day1OpeningCashAfterCosts: 600 - 140 - 80 - 80 - 224 - 16,
  day1ClosingCash: 600 - 140 - 80 - 80 - 224 - 16 + 9 * 45
};
console.log(JSON.stringify(result, null, 2));

