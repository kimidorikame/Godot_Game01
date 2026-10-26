// 備蓄型の測り直し（k＝手元の個数。UI準備D）の集計。数字と事実だけを出す。判断・調整の提案は書かない。
// 使い方: node summarize_stockpile_pieces.mjs merge   … tmp_pc_*.json を playthrough_results_stockpile_pieces.json にまとめる（tmp は消す）
//         node summarize_stockpile_pieces.mjs tables  … PLAYTHROUGH_RESULTS_INFO.md の「備蓄型の測り直し」の表を標準出力へ
// 入力：tmp_pc_*.json（playthroughs.gd の info=stock・引数 pieces・方針 stockpile・各30シード）
//       playthrough_results_stockpile.json（先の備蓄型。k＝袋）／playthrough_results_info_levels.json（基本GOODの p＝0〜100%）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const read = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const COMBOS = [
  { id: 'k1', file: 'tmp_pc_k1.json', label: '備蓄型（個数）k=1（情報なし）' },
  { id: 'k2', file: 'tmp_pc_k2.json', label: '備蓄型（個数）k=2（情報なし）' },
  { id: 'k1p50', file: 'tmp_pc_k1p50.json', label: '備蓄型（個数）k=1＋生もの情報 p=50%' },
  { id: 'k1p100', file: 'tmp_pc_k1p100.json', label: '備蓄型（個数）k=1＋生もの情報 p=100%' },
  { id: 'k2p50', file: 'tmp_pc_k2p50.json', label: '備蓄型（個数）k=2＋生もの情報 p=50%' },
  { id: 'k2p100', file: 'tmp_pc_k2p100.json', label: '備蓄型（個数）k=2＋生もの情報 p=100%' },
];
const OUT = 'playthrough_results_stockpile_pieces.json';
// 終了時の在庫の評価額に使う単価（円/個）＝市場の標準の袋の値段÷個数（品目ごと）。現金には数えない目安。
const UNIT = { nam_prik_pao: 5, coconut_milk: 5, pickled_lime: 4, bitter_melon: 4, herbal_sauce: 5, offal: 10, meat_ball: 8, tendon_meat: 12,
  tofu: 8, winter_melon: 10, broken_wrapper: 6, rice_noodle: 8, cartilage: 8, dried_wood_ear: 10, shrimp: 18, clam: 16, fish_maw: 20 };

if (process.argv[2] === 'merge') {
  const combos = [];
  let commit = '';
  for (const c of COMBOS) {
    const d = read(c.file);
    commit = d.commit;
    combos.push({ id: c.id, label: c.label, k: d.info_stock.k, p_fresh: d.info_stock.p_fresh, unit: d.info_stock.unit, runs: d.runs, unserved_log: d.unserved_log });
  }
  fs.writeFileSync(new URL(OUT, dir), JSON.stringify({ commit, daily_operating_cost: 75, reach: 'reach_true', policy: 'stockpile', seeds: 30,
    note: '備蓄型の測り直し：k＝そのタグを満たす材料を手元に持つ個数（袋の数ではない）。日持ちする7材料と生もの3タグ（MELLOW＝ココナッツミルク・BITTER＝苦瓜・POWER＝肉団子）を、手元がk個を切ったら1袋買い足す。予報も見込みも読まない。', combos }));
  for (const c of COMBOS) fs.unlinkSync(new URL(c.file, dir));
  console.log('merged', combos.length, 'combos');
  process.exit(0);
}

const pieces = read(OUT);
const packs = read('playthrough_results_stockpile.json');
const levels = read('playthrough_results_info_levels.json');
const goals = JSON.parse(fs.readFileSync(new URL('../../data/campaigns/week7.json', dir), 'utf8')).goals;
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0;
const f0 = x => Math.round(x).toString();
const f1 = x => x.toFixed(1);
const pct = x => (100 * x).toFixed(1) + '%';
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const spend = (r, k) => r.rows.reduce((s, d) => s + (d.spend?.[k] ?? 0), 0);
const goodPlus = r => r.result_summary?.good_plus_cups ?? r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0);
const judged = r => r.result_summary?.judged_cups ?? sumRows(r, 'judged_demand');
const stockValue = r => Object.entries(r.closing_stock_units ?? {}).reduce((s, [id, n]) => s + (UNIT[id] ?? 0) * Number(n), 0);
function stat(runs, ulog) {
  const n = runs.length;
  const total = r => r.result_summary?.cash_plus_repair ?? r.cash;
  const ul = k => ulog.reduce((s, u) => s + (u[k] ?? 0), 0) / Math.max(n, 1);
  const cash = runs.map(r => r.cash);
  return { n, cash: mean(cash), min: Math.min(...cash), max: Math.max(...cash),
    good: mean(runs.map(r => goodPlus(r) / Math.max(judged(r), 1))),
    t1500: mean(runs.map(r => Number(total(r) >= goals.cash_standard))),
    over: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    market: mean(runs.map(r => spend(r, 'market'))), spoiled: mean(runs.map(r => sumRows(r, 'spoiled_value'))),
    sales: mean(runs.map(r => sumRows(r, 'sales'))),
    left: mean(runs.map(r => Object.values(r.closing_stock_units ?? {}).reduce((a, b) => a + Number(b), 0))),
    stock: mean(runs.map(stockValue)), cashPlusStock: mean(runs.map(r => r.cash + stockValue(r))),
    perDay: [2, 3, 4, 5, 6, 7].map(d => mean(runs.map(r => r.rows.find(x => x.day === d)?.spend?.market ?? 0))),
    unserved: mean(runs.map(r => sumRows(r, 'unserved'))), uIng: ul('ingredients'), uPot: ul('pot'), uDecl: ul('declined'), uNot: ul('not_arrived'),
    hasU: ulog.length > 0 };
}
const rows = [];
for (const c of pieces.combos) rows.push({ label: `**${c.label}**`, s: stat(c.runs, c.unserved_log) });
const k2packs = packs.combos.find(c => c.id === 'k2');
rows.push({ label: '備蓄型（袋）k=2（情報なし）（先の結果 4bd3010）', s: stat(k2packs.runs, k2packs.unserved_log) });
for (const id of ['p000', 'p050', 'p075', 'p100']) {
  const c = levels.combos.find(x => x.id === id);
  rows.push({ label: `補う版・基本GOOD・${c.label}（先の実験）`, s: stat(c.runs.filter(r => r.policy === 'forecast_good'), c.unserved_log.filter(u => u.policy === 'forecast_good')) });
}
const out = [];
const w = s => out.push(s);
w('| 方針・条件 | 周 | 平均最終現金 | 最小〜最大 | 1500達成 | GOOD以上率 | ゲームオーバー | 売上（1周） | 仕入れ費用（1周） | 廃棄額（1周） | 終了時の在庫（個） | 在庫の評価額（円） | 最終現金＋在庫評価額 | 出せなかった杯（1周）：合計 | 素材 | 鍋 | 断った | 来られなかった |');
w('|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
for (const { label, s } of rows) {
  w(`| ${label} | ${s.n} | ${f0(s.cash)} | ${s.min}〜${s.max} | ${pct(s.t1500)} | ${pct(s.good)} | ${s.over} | ${f0(s.sales)} | ${f0(s.market)} | ${f0(s.spoiled)} | ${f0(s.left)} | ${f0(s.stock)} | ${f0(s.cashPlusStock)} | ${f1(s.unserved)} | ${s.hasU ? f1(s.uIng) : '—'} | ${s.hasU ? f1(s.uPot) : '—'} | ${s.hasU ? f1(s.uDecl) : '—'} | ${s.hasU ? f1(s.uNot) : '—'} |`);
}
w('');
w('日ごとの仕入れ費用の平均（1周あたり。Day1は市場が閉まっていて仕入れが無い）');
w('');
w('| 方針・条件 | Day2 | Day3 | Day4 | Day5 | Day6 | Day7 | 合計 |');
w('|---|---:|---:|---:|---:|---:|---:|---:|');
for (const { label, s } of rows) {
  w(`| ${label} | ${s.perDay.map(f0).join(' | ')} | ${f0(s.perDay.reduce((a, b) => a + b, 0))} |`);
}
console.log(out.join('\n'));
