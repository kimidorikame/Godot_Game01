// 備蓄型の実験（UI準備D）の集計。数字と事実だけを出す。判断・調整の提案は書かない。
// 使い方: node summarize_stockpile.mjs merge   … tmp_st_*.json を playthrough_results_stockpile.json にまとめる（tmp は消す）
//         node summarize_stockpile.mjs tables  … PLAYTHROUGH_RESULTS_INFO.md の「備蓄型」の表を標準出力へ
// 入力：tmp_st_*.json（playthroughs.gd の info=stock・方針 stockpile・各30シード）
//       playthrough_results_info_levels.json（先の実験。基本GOODの p＝0〜100%）／playthrough_results_regulars_v2.json（予報あり）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const read = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const COMBOS = [
  { id: 'k2', file: 'tmp_st_k2.json', label: '備蓄型 k=2（情報なし）' },
  { id: 'k3', file: 'tmp_st_k3.json', label: '備蓄型 k=3（情報なし）' },
  { id: 'k2p50', file: 'tmp_st_k2p50.json', label: '備蓄型 k=2＋生もの3タグの情報 p=50%' },
  { id: 'k2p100', file: 'tmp_st_k2p100.json', label: '備蓄型 k=2＋生もの3タグの情報 p=100%' },
];
const OUT = 'playthrough_results_stockpile.json';

if (process.argv[2] === 'merge') {
  const combos = [];
  let commit = '';
  for (const c of COMBOS) {
    const d = read(c.file);
    commit = d.commit;
    combos.push({ id: c.id, label: c.label, k: d.info_stock.k, p_fresh: d.info_stock.p_fresh, runs: d.runs, unserved_log: d.unserved_log });
  }
  fs.writeFileSync(new URL(OUT, dir), JSON.stringify({ commit, daily_operating_cost: 75, reach: 'reach_true', policy: 'stockpile', seeds: 30,
    note: '備蓄型：日持ちする7材料（HOT・SOUR・SAVORY・GENTLE・FILLING・BITE・TREAT）と生もの3タグ（MELLOW・BITTER・POWER）を、k単位（購入単位＝1袋）ぶん手元に置く。予報も見込みも読まない。', combos }));
  for (const c of COMBOS) fs.unlinkSync(new URL(c.file, dir));
  console.log('merged', combos.length, 'combos');
  process.exit(0);
}

const stock = read(OUT);
const levels = read('playthrough_results_info_levels.json');
const v2 = read('playthrough_results_regulars_v2.json');
// 目標の基準は計測した当時の値に固定する（データの goals は UI準備J で 1200／1500／70%／4杯 に変わった。過去の表を作り直しても当時と同じ数字が出るように）
const goals = { cash_standard: 1500, cash_challenge: 1600, good_rate: 0.85, regular_great: 8 };
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0;
const f0 = x => Math.round(x).toString();
const f1 = x => x.toFixed(1);
const pct = x => (100 * x).toFixed(1) + '%';
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const spend = (r, k) => r.rows.reduce((s, d) => s + (d.spend?.[k] ?? 0), 0);
const goodPlus = r => r.result_summary?.good_plus_cups ?? r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0);
const judged = r => r.result_summary?.judged_cups ?? sumRows(r, 'judged_demand');
function stat(runs, ulog) {
  const n = runs.length;
  const cash = runs.map(r => r.cash);
  const total = r => r.result_summary?.cash_plus_repair ?? r.cash;
  const ul = k => ulog.reduce((s, u) => s + (u[k] ?? 0), 0) / Math.max(n, 1);
  return { n, cash: mean(cash), min: Math.min(...cash), max: Math.max(...cash),
    good: mean(runs.map(r => goodPlus(r) / Math.max(judged(r), 1))),
    t1500: mean(runs.map(r => Number(total(r) >= goals.cash_standard))),
    over: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    market: mean(runs.map(r => spend(r, 'market'))), spoiled: mean(runs.map(r => sumRows(r, 'spoiled_value'))),
    sales: mean(runs.map(r => sumRows(r, 'sales'))), left: mean(runs.map(r => Object.values(r.closing_stock_units ?? {}).reduce((a, b) => a + Number(b), 0))),
    unserved: mean(runs.map(r => sumRows(r, 'unserved'))), uIng: ul('ingredients'), uPot: ul('pot'), uDecl: ul('declined'), uNot: ul('not_arrived'),
    hasU: ulog.length > 0 };
}
const out = [];
const w = s => out.push(s);
w('| 方針・条件 | 周 | 平均最終現金 | 最小〜最大 | 1500達成 | GOOD以上率 | ゲームオーバー | 売上（1周） | 仕入れ費用（1周） | 廃棄額（1周） | 終了時の在庫（個） | 出せなかった杯（1周）：合計 | 素材 | 鍋 | 断った | 来られなかった |');
w('|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
const row = (label, s) => w(`| ${label} | ${s.n} | ${f0(s.cash)} | ${s.min}〜${s.max} | ${pct(s.t1500)} | ${pct(s.good)} | ${s.over} | ${f0(s.sales)} | ${f0(s.market)} | ${f0(s.spoiled)} | ${f0(s.left)} | ${f1(s.unserved)} | ${s.hasU ? f1(s.uIng) : '—'} | ${s.hasU ? f1(s.uPot) : '—'} | ${s.hasU ? f1(s.uDecl) : '—'} | ${s.hasU ? f1(s.uNot) : '—'} |`);
for (const c of stock.combos) row(`**${c.label}**`, stat(c.runs, c.unserved_log));
for (const id of ['p000', 'p025', 'p050', 'p075', 'p100']) {
  const c = levels.combos.find(x => x.id === id);
  row(`基本GOOD・${c.label}（先の実験）`, stat(c.runs.filter(r => r.policy === 'forecast_good'), c.unserved_log.filter(u => u.policy === 'forecast_good')));
}
row('（参考）基本GOOD・v2（予報あり）', stat(v2.runs.filter(r => r.policy === 'forecast_good'), (v2.unserved_log || []).filter(u => u.policy === 'forecast_good')));
console.log(out.join('\n'));
