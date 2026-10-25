// 情報量の実験（UI準備D）の集計。数字と事実だけを出す。判断・調整の提案は書かない。
// 使い方: node summarize_info_levels.mjs merge   … tmp_lv_*.json を playthrough_results_info_levels.json にまとめる（tmp は消す）
//         node summarize_info_levels.mjs tables  … PLAYTHROUGH_RESULTS_INFO.md の表の部分を標準出力へ
// 入力：tmp_lv_*.json（playthroughs.gd の info=levels。方針は forecast_good と favorite_oracle の2つ・各30シード）
//       playthrough_results_regulars_v2.json（予報あり＝100%相当の確認用）／playthrough_results_regulars_v3_improvise.json（補う版＝p=0の確認用）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const read = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const COMBOS = [
  { id: 'p000', file: 'tmp_lv_p000.json', label: 'p=0%（全員を知らない）' },
  { id: 'p025', file: 'tmp_lv_p025.json', label: 'p=25%' },
  { id: 'p050', file: 'tmp_lv_p050.json', label: 'p=50%' },
  { id: 'p075', file: 'tmp_lv_p075.json', label: 'p=75%' },
  { id: 'p100', file: 'tmp_lv_p100.json', label: 'p=100%（全員を知る）' },
  { id: 'reg100', file: 'tmp_lv_reg100.json', label: '常連だけ100%・モブ0%' },
  { id: 'mob100', file: 'tmp_lv_mob100.json', label: 'モブだけ100%・常連0%' },
  { id: 'p100ft', file: 'tmp_lv_p100ft.json', label: '（確認）p=100%＋見込み杯数も予報' },
];
const OUT = 'playthrough_results_info_levels.json';
const POLICIES = ['forecast_good', 'favorite_oracle'];
const NAMES = { forecast_good: '基本GOOD', favorite_oracle: '初回から好物（oracle）' };

if (process.argv[2] === 'merge') {
  const combos = [];
  let commit = '';
  for (const c of COMBOS) {
    const d = read(c.file);
    commit = d.commit;
    combos.push({ id: c.id, label: c.label, p_regular: d.info_levels.p_regular, p_mob: d.info_levels.p_mob,
      forecast_target: d.info_levels.forecast_target, runs: d.runs, unserved_log: d.unserved_log });
  }
  const out = { commit, daily_operating_cost: 75, reach: 'reach_true', policies: POLICIES, seeds: 30,
    note: '補う版（visible_improvise）が土台。仕入れの必要数（旧予報の上限案のタグ別必要数）の1単位ごとに、確率pで前もって知っている。知らない分は前の晩までに受けた注文のタグの割合（v3）で置き換える。',
    combos };
  fs.writeFileSync(new URL(OUT, dir), JSON.stringify(out));
  for (const c of COMBOS) fs.unlinkSync(new URL(c.file, dir));
  console.log('merged', combos.length, 'combos');
  process.exit(0);
}

const data = read(OUT);
const v2 = read('playthrough_results_regulars_v2.json');
const v3i = read('playthrough_results_regulars_v3_improvise.json');
const goals = JSON.parse(fs.readFileSync(new URL('../../data/campaigns/week7.json', dir), 'utf8')).goals;
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
    market: mean(runs.map(r => spend(r, 'market'))),
    uIng: ul('ingredients'), uPot: ul('pot'), uDecl: ul('declined'), uNot: ul('not_arrived'), unserved: mean(runs.map(r => sumRows(r, 'unserved'))) };
}
const of = (combo, p) => stat(combo.runs.filter(r => r.policy === p), combo.unserved_log.filter(u => u.policy === p));
const refStat = (res, p) => stat(res.runs.filter(r => r.policy === p), (res.unserved_log || []).filter(u => u.policy === p));

const out = [];
const w = s => out.push(s);
for (const p of POLICIES) {
  w(`### ${NAMES[p]}`);
  w('');
  w('| 組み合わせ | 周 | 平均最終現金 | 最小〜最大 | 1500達成 | GOOD以上率 | ゲームオーバー | 仕入れ費用（1周） | 出せなかった杯（1周）：合計 | 素材 | 鍋 | 断った | 来られなかった |');
  w('|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (const c of data.combos) {
    const s = of(c, p);
    w(`| ${c.label} | ${s.n} | ${f0(s.cash)} | ${s.min}〜${s.max} | ${pct(s.t1500)} | ${pct(s.good)} | ${s.over} | ${f0(s.market)} | ${f1(s.unserved)} | ${f1(s.uIng)} | ${f1(s.uPot)} | ${f1(s.uDecl)} | ${f1(s.uNot)} |`);
  }
  const refs = [['v2（予報あり）', v2], ['補う版（visible_improvise。v3）', v3i]];
  for (const [label, res] of refs) {
    const s = refStat(res, p);
    const hasU = (res.unserved_log || []).length > 0;
    w(`| （参考）${label} | ${s.n} | ${f0(s.cash)} | ${s.min}〜${s.max} | ${pct(s.t1500)} | ${pct(s.good)} | ${s.over} | ${f0(s.market)} | ${f1(s.unserved)} | ${hasU ? f1(s.uIng) : '—'} | ${hasU ? f1(s.uPot) : '—'} | ${hasU ? f1(s.uDecl) : '—'} | ${hasU ? f1(s.uNot) : '—'} |`);
  }
  w('');
}
w('### pの表（グラフにする用。全員に同じ割合 p）');
w('');
w('| p | 基本GOOD 平均最終現金 | 基本GOOD 1500達成 | oracle 平均最終現金 | oracle 1500達成 |');
w('|---:|---:|---:|---:|---:|');
for (const id of ['p000', 'p025', 'p050', 'p075', 'p100']) {
  const c = data.combos.find(x => x.id === id);
  const a = of(c, 'forecast_good'), b = of(c, 'favorite_oracle');
  w(`| ${Math.round(c.p_regular * 100)}% | ${f0(a.cash)} | ${pct(a.t1500)} | ${f0(b.cash)} | ${pct(b.t1500)} |`);
}
w('');
w('```');
const maxCash = 1700;
for (const p of POLICIES) {
  w(`${NAMES[p]}（平均最終現金。| が 1500）`);
  for (const id of ['p000', 'p025', 'p050', 'p075', 'p100']) {
    const c = data.combos.find(x => x.id === id);
    const s = of(c, p);
    const width = 50;
    const bar = Math.round(width * s.cash / maxCash);
    const mark = Math.round(width * 1500 / maxCash);
    let line = '';
    for (let i = 0; i <= width; i++) line += i === mark ? '|' : (i < bar ? '#' : ' ');
    w(`  p=${String(Math.round(c.p_regular * 100)).padStart(3)}%  ${line}  ${f0(s.cash)}`);
  }
  w('');
}
w('```');
w('');
w('### 常連だけ／モブだけ（基本GOOD・oracle）');
w('');
w('| | 平均最終現金（基本GOOD） | 平均最終現金（oracle） |');
w('|---|---:|---:|');
for (const id of ['p000', 'reg100', 'mob100', 'p100']) {
  const c = data.combos.find(x => x.id === id);
  w(`| ${c.label} | ${f0(of(c, 'forecast_good').cash)} | ${f0(of(c, 'favorite_oracle').cash)} |`);
}
w('');
// 確認：p=0 が補う版と一致するか
const check = [];
for (const p of POLICIES) {
  const c0 = data.combos.find(x => x.id === 'p000');
  let same = 0, n = 0;
  for (const r of c0.runs.filter(r => r.policy === p)) {
    const o = v3i.runs.find(x => x.policy === p && x.seed === r.seed);
    n++;
    if (o && r.cash === o.cash && JSON.stringify(r.rows) === JSON.stringify(o.rows)) same++;
  }
  check.push(`${NAMES[p]}：p=0% と補う版の一致 ${same}/${n}周`);
}
w('確認：' + check.join(' ／ '));
console.log(out.join('\n'));
