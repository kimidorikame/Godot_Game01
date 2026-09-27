// Independent static arithmetic audit of Night_Broth_Balance_Proposal_ClaudeCode.md.
// This models proposed numbers combined with the retained 1..5 clamp, not Godot play.
// Run: node planning/claude_audit.mjs
import assert from 'node:assert/strict';

const ingredients = [
  ['nam_prik_pao',5,['HOT']], ['coconut_milk',5,['MELLOW']],
  ['pickled_lime',5,['SOUR']], ['bitter_melon',5,['BITTER']],
  ['herbal_sauce',5,['SAVORY']], ['meat_ball',3,['POWER']],
  ['offal',6,['POWER']], ['broken_wrapper',3,['FILLING']],
  ['rice_noodle',5,['FILLING']], ['tofu',4,['GENTLE']],
  ['winter_melon',6,['GENTLE']], ['cartilage',5,['BITE']],
  ['dried_wood_ear',7,['BITE']], ['tendon_meat',8,['BITE','POWER']],
  ['clam',11,['TREAT']], ['shrimp',12,['TREAT']],
  ['fish_maw',14,['TREAT','FILLING']],
].map(([id,cost,tags])=>({id,cost,tags}));
const tastes = new Set(['HOT','MELLOW','SOUR','BITTER','SAVORY']);
const recipes = [];
function generate(start, items) {
  if(items.length) recipes.push({ids:items.map(x=>x.id), cost:items.reduce((s,x)=>s+x.cost,0),
    tags:new Set(items.flatMap(x=>x.tags))});
  if(items.length===3)return;
  for(let i=start;i<ingredients.length;i++)generate(i+1,[...items,ingredients[i]]);
}
generate(0,[]);
const mobs = [
 ['dock_workers',['HOT','POWER','FILLING']],
 ['inn_clerk',['MELLOW','GENTLE','POWER']],
 ['market_porter',['SAVORY','FILLING','POWER']],
 ['security_guard',['SAVORY','BITE','GENTLE']],
 ['street_cleaners',['SOUR','FILLING','GENTLE']],
 ['general_store_clerk',['BITTER','GENTLE','FILLING']],
 ['long_haul_driver',['SAVORY','TREAT','BITE']],
];
function cheapest(wanted, minimumMatches, requireTaste=false, requireBasic=false) {
  const eligible = recipes.filter(r=>[...r.tags].some(t=>!tastes.has(t))
    && wanted.filter(t=>r.tags.has(t)).length>=minimumMatches
    && (!requireTaste||[...r.tags].some(t=>tastes.has(t)))
    && (!requireBasic||(r.tags.has(wanted[0])&&r.tags.has(wanted[1]))));
  const minimum = Math.min(...eligible.map(r=>r.cost));
  return {cost:minimum, recipes:eligible.filter(r=>r.cost===minimum).map(r=>r.ids)};
}
const mobRecipes = mobs.map(([id,wanted])=>({id,wanted,
  good:cheapest(wanted,2), goodRequiringTaste:cheapest(wanted,2,true),
  goodRequiringBasic:cheapest(wanted,2,true,true), great:cheapest(wanted,3)}));
const mean = key=>mobRecipes.reduce((s,m)=>s+m[key].cost,0)/mobs.length;
assert.equal(mobRecipes.reduce((s,m)=>s+m.good.cost,0),52);
assert.equal(mobRecipes.reduce((s,m)=>s+m.great.cost,0),93);
assert.equal(mobRecipes.reduce((s,m)=>s+m.goodRequiringBasic.cost,0),68);

function potTrace(operations) {
  let servings=8, strength=3, waters=0, bases=0;
  const trace=[{op:'prepare',servings,strength}];
  for(const op of operations){
    if(op==='water'){assert.ok(waters<3);waters++;servings+=3;strength=Math.max(1,strength-2);}
    else if(op==='base'){bases++;servings++;strength=Math.min(5,strength+1);}
    else if(op==='time'){strength=Math.min(5,strength+1);}
    else throw new Error(op);
    trace.push({op,servings,strength});
  }
  return {servings,strength,waters,bases,consumedAdditionalCost:waters*20+bases*16,
    reservePurchaseCashIfNoneOwned:80*Math.ceil(bases/5),trace};
}
const fifteen = potTrace(['water','water','base']);
const eighteen = potTrace(['water','water','water','base']);
assert.equal(fifteen.servings,15);assert.equal(fifteen.strength,2);
assert.equal(fifteen.consumedAdditionalCost,56);
assert.equal(eighteen.servings,18);assert.equal(eighteen.strength,2);
// Two initial base additions reach strength 5. Further additions have no added
// concentration effect. One water restores strength 3 regardless of their count.
const upperClampExamples = [2,7,22].map(n=>potTrace([...Array(n).fill('base'),'water']));
const dailyInputs = [
 [1,0,9,140,150,560], [2,8,8,240,0,720], [3,17,11,290,0,980],
 [4,26,14,400,300,980], [5,35,14,380,0,1300],
 [6,44,14,380,0,1620], [7,53,11,320,700,1150],
];
let money=400;
const cashArithmetic=dailyInputs.map(([day,openingRep,demand,purchases,rent,claimedClosingCash])=>{
  money+=demand*50-purchases-rent;
  assert.equal(money,claimedClosingCash);
  return {day,openingRep,demand,purchases,rent,closingCash:money};
});
const result={
 assumptions:{recipeSlots:3,uniqueIngredientCombinations:recipes.length,
   retainedClamp:[1,5],potVolumeCap:null,maximumWaterUses:3,
   initialFreeReserveUnitsInCurrentCode:10,reserveUnitsPerAddition:2,
   warning:'Consumes reserve at16 per addition; actual purchases are80 per5 additions. Existing initial reserve is free unless explicitly removed.'},
 potCounterexamples:{fifteen,eighteen,upperClampExamples,
   unboundedSupplyFormula:'For any base additions b >= 2 before one water: volume=11+b, strength=3, additional consumed cost=20+16*b. Bounded by cash and morning inventory, not by water supply.'},
 mobRecipes,
 recipeMeans:{good:mean('good'),goodRequiringTaste:mean('goodRequiringTaste'),
   goodRequiringBasic:mean('goodRequiringBasic'),great:mean('great'),
   greatToGood:mean('great')/mean('good'),greatToTasteRequiredGood:mean('great')/mean('goodRequiringTaste'),
   greatToBasicRequiredGood:mean('great')/mean('goodRequiringBasic')},
 dualTagItems:{
   tendon:{combinedPackPrice:40,separatePackPrice:15+25,
     simultaneousRequiredTagMatch:mobs.filter(([,w])=>w.includes('POWER')&&w.includes('BITE')).map(([id])=>id)},
   fishMaw:{combinedPackPrice:70,separatePackPrice:55+15,
     simultaneousRequiredTagMatch:mobs.filter(([,w])=>w.includes('TREAT')&&w.includes('FILLING')).map(([id])=>id)},
   limitation:'Separate same-age five-unit packs weakly dominate the combined five-unit pack for listed demands when no inventory-slot limit exists.'},
 cashArithmetic,
 cashConclusion:'Column arithmetic matches1150, but item-level baskets, reserve stock, water fees, customer draws and spoilage are unspecified; this is not a reproducible gameplay simulation.',
 currentCodeScopeDependencies:[
  'BASE_PRICE is shared by ordinary prep and reserve purchase;120 versus80 needs separation.',
  'Daily rent150/300/700 needs both collection-day logic and price lookup; current is_collection_day only permits Day1.',
  'The water-stall fee also calls is_collection_day; changing that function changes water bills unless separated.',
  'reserve_base_purchase_remaining/day hold only one batch; unlimited purchases need multi-batch expiry or an explicit nonperishable rule.',
  '_no_resources_left checks only water, and pot UI can lock base until water when empty; volume-granting base needs shortage/UI updates.',
  'Daily telemetry and deterministic headless comparison are new work outside the six-row mutation list.',
 ],
};
console.log(JSON.stringify(result,null,2));
