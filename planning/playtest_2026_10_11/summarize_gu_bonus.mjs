// 計測K（具2種類の「ごちそう」チップ案）の集計。数字と事実だけを出す。判断・調整の提案は書かない。
// 使い方: node summarize_gu_bonus.mjs merge   … tmp_k_*.json を playthrough_results_gu_bonus.json にまとめる（tmp は消す）
//         node summarize_gu_bonus.mjs tables  … 表を標準出力へ（PLAYTHROUGH_RESULTS_GU_BONUS.md に貼る）
// 入力：tmp_k_<見分け>_<買い方>_<上乗せ>.json（playthroughs.gd。見分け＝p0／p50／p100＝情報量の実験の基本GOOD・各30シード。
//       買い方＝one／afford／always。上乗せ＝0／5／10／15）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const read = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const INFOS = [{ id: 'p0', label: 'p=0%' }, { id: 'p50', label: 'p=50%' }, { id: 'p100', label: 'p=100%' }];
const BUYS = [{ id: 'one', label: '味1具1のみ' }, { id: 'afford', label: '買える日は買う' }, { id: 'always', label: '常に買う' }];
const BONUS = [0, 5, 10, 15];
const RULE = { 0: 'a 現行（上乗せなし）', 5: 'b +5', 10: 'c +10', 15: 'd +15' };
const OUT = 'playthrough_results_gu_bonus.json';

if (process.argv[2] === 'merge') {
  const combos = [];
  let commit = '';
  for (const i of INFOS) for (const b of BUYS) for (const x of BONUS) {
    const f = `tmp_k_${i.id}_${b.id}_${x}.json`;
    const d = read(f);
    commit = d.commit;
    combos.push({ info: i.id, buy: b.id, bonus: x, tip_gu: d.tip_gu, info_levels: d.info_levels, runs: d.runs });
  }
  fs.writeFileSync(new URL(OUT, dir), JSON.stringify({ commit, daily_operating_cost: 75, reach: 'reach_true', seeds: 30,
    note: '計測K：ハーネスだけの設定（gu_mode・gu_bonus）。チップは現行（GOOD +5・GREAT +10）。具が2種類で GOOD 以上の丼に1杯あたり gu_bonus を足す。評価・評判の式・判定・SaleRule は変えていない。',
    combos }));
  for (const i of INFOS) for (const b of BUYS) for (const x of BONUS) fs.unlinkSync(new URL(`tmp_k_${i.id}_${b.id}_${x}.json`, dir));
  console.log('merged', combos.length, 'combos');
  process.exit(0);
}

const data = read(OUT);
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0;
const f0 = x => Math.round(x).toString();
const f1 = x => x.toFixed(1);
const f2 = x => x.toFixed(2);
const pct = x => (100 * x).toFixed(1) + '%';
const sgn = x => (x >= 0 ? '+' : '') + f0(x);
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const total = r => r.result_summary?.cash_plus_repair ?? r.cash;
function stat(runs) {
  const last = r => r.rows[r.rows.length - 1] ?? {};
  const cupsTwo = mean(runs.map(r => r.cups_two ?? 0)), cupsOne = mean(runs.map(r => r.cups_one ?? 0));
  const gTwo = mean(runs.map(r => r.cups_two_good ?? 0)), gOne = mean(runs.map(r => r.cups_one_good ?? 0));
  return { n: runs.length, cash: mean(runs.map(r => r.cash)),
    r1200: mean(runs.map(r => Number(total(r) >= 1200))), r1500: mean(runs.map(r => Number(total(r) >= 1500))),
    good: mean(runs.map(r => (r.result_summary?.good_plus_cups ?? 0) / Math.max(r.result_summary?.judged_cups ?? 0, 1))),
    market: mean(runs.map(r => r.rows.reduce((s, d) => s + (d.spend?.market ?? 0), 0))),
    topping: mean(runs.map(r => r.topping_spend ?? 0)), second: mean(runs.map(r => r.second_gu_spend ?? 0)),
    leftover: mean(runs.map(r => last(r).closing_stock_value ?? 0)), leftoverTop: mean(runs.map(r => last(r).closing_topping_value ?? 0)),
    leftoverAvg: mean(runs.map(r => mean(r.rows.map(d => d.closing_stock_value ?? 0)))),
    spoiled: mean(runs.map(r => sumRows(r, 'spoiled_value'))),
    bonus: mean(runs.map(r => r.gu_bonus ?? 0)), tips: mean(runs.map(r => r.tips ?? 0)),
    cupsTwo, cupsOne, shareTwo: cupsTwo / Math.max(cupsTwo + cupsOne, 1), goodTwo: gTwo / Math.max(cupsTwo, 1), goodOne: gOne / Math.max(cupsOne, 1),
    served: mean(runs.map(r => sumRows(r, 'served'))), rep: mean(runs.map(r => r.rep)),
    over: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0) };
}
const S = {};
for (const c of data.combos) S[`${c.info}_${c.buy}_${c.bonus}`] = stat(c.runs);
const out = [];
const w = s => out.push(s);

w('### 表1：全条件');
w('');
w('| 見分け | 買い方 | 案（具2の丼への上乗せ） | 周 | 平均最終現金 | 味1具1のみ・同じ案との差 | 1200到達率 | 1500到達率 | GOOD以上率 | 上乗せ総額（1周） | チップ総額（1周） | ゲームオーバー |');
w('|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
for (const i of INFOS) for (const b of BUYS) for (const x of BONUS) {
  const s = S[`${i.id}_${b.id}_${x}`], base = S[`${i.id}_one_${x}`];
  w(`| ${i.label} | ${b.label} | ${RULE[x]} | ${s.n} | ${f0(s.cash)} | ${b.id === 'one' ? '—' : sgn(s.cash - base.cash)} | ${pct(s.r1200)} | ${pct(s.r1500)} | ${pct(s.good)} | ${f0(s.bonus)} | ${f0(s.tips)} | ${s.over} |`);
}
w('');
w('### 表2：具の仕入れと余り（1周の平均。上乗せの額で仕入れの行動は変わるので案ごとに並べる）');
w('');
w('| 見分け | 買い方 | 案 | 市場の仕入れ総額 | 具の仕入れ額 | うち2つ目の具の候補（米麺・乾燥きくらげ・冬瓜・魚の浮き袋） | 最終日の余り在庫（評価額） | うち具 | 毎日の余り在庫の平均 | 傷んだ分の評価額（1週間の合計） |');
w('|---|---|---|---:|---:|---:|---:|---:|---:|---:|');
for (const i of INFOS) for (const b of BUYS) for (const x of BONUS) {
  const s = S[`${i.id}_${b.id}_${x}`];
  w(`| ${i.label} | ${b.label} | ${RULE[x]} | ${f0(s.market)} | ${f0(s.topping)} | ${f0(s.second)} | ${f0(s.leftover)} | ${f0(s.leftoverTop)} | ${f0(s.leftoverAvg)} | ${f0(s.spoiled)} |`);
}
w('');
w('### 表3：具2種類の丼の割合とGOOD以上率（具の数別。杯数は1周の平均）');
w('');
w('| 見分け | 買い方 | 案 | 具2種類以上の杯 | 具1種類の杯 | 具2種類の割合 | 具2種類のGOOD以上率 | 具1種類のGOOD以上率 | 全体のGOOD以上率（結果画面） |');
w('|---|---|---|---:|---:|---:|---:|---:|---:|');
for (const i of INFOS) for (const b of BUYS) for (const x of BONUS) {
  const s = S[`${i.id}_${b.id}_${x}`];
  w(`| ${i.label} | ${b.label} | ${RULE[x]} | ${f1(s.cupsTwo)} | ${f1(s.cupsOne)} | ${pct(s.shareTwo)} | ${pct(s.goodTwo)} | ${pct(s.goodOne)} | ${pct(s.good)} |`);
}
w('');
w('### 表4：「具2を買う」が「味1具1のみ」より得になる上乗せの額（平均最終現金の差＝買う − 買わない）');
w('');
w('同じ上乗せの案どうしで差を取る（30シードは対）。逆転点は、4つの案（0・5・10・15）の差を直線で当てはめて、差が 0 になる上乗せの額。0〜15 の外になるときは「外挿」と付ける。');
w('');
w('| 見分け | 買い方 | 差 @0 | 差 @5 | 差 @10 | 差 @15 | 逆転する上乗せ（1杯あたり） |');
w('|---|---|---:|---:|---:|---:|---|');
for (const i of INFOS) for (const b of BUYS.slice(1)) {
  const d = BONUS.map(x => S[`${i.id}_${b.id}_${x}`].cash - S[`${i.id}_one_${x}`].cash);
  // 最小二乗
  const mx = mean(BONUS), my = mean(d);
  const slope = BONUS.reduce((s, x, k) => s + (x - mx) * (d[k] - my), 0) / BONUS.reduce((s, x) => s + (x - mx) ** 2, 0);
  const icpt = my - slope * mx;
  let cross;
  if (slope <= 0) cross = '上乗せを増やしても差は縮まらない（傾き ' + f1(slope) + '）';
  else {
    const z = -icpt / slope;
    cross = z <= 0 ? '0 でもすでに得（当てはめ値 ' + f1(z) + '）' : (z > 15 ? `約 ${f1(z)}（外挿）` : `約 ${f1(z)}`);
  }
  w(`| ${i.label} | ${b.label} | ${sgn(d[0])} | ${sgn(d[1])} | ${sgn(d[2])} | ${sgn(d[3])} | ${cross}（上乗せを1増やすと差が +${f1(slope)}） |`);
}
w('');
console.log(out.join('\n'));
