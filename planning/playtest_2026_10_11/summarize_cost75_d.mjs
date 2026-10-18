// 運営費75（データ反映後）の新しい基準（D）と修繕基金（R3）の集計。数字と事実だけを出す。
// 使い方: node summarize_cost75_d.mjs   （PLAYTHROUGH_RESULTS_COST75_V2.md を書く）
// 入力：playthrough_results_regulars_v2.json（データ75・reach_true・13方針×30）
//       playthrough_results_reach_true_cost75.json／_cost75_rest.json（A：運営費75を引数で上書き）
//       playthrough_results_regulars.json（旧基準：運営費65・12/13/14）
//       playthrough_results_fund_v3.json（データ75・reach_true・基準方針＋基金3方針×30）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const load = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const v2 = load('playthrough_results_regulars_v2.json');
const a1 = load('playthrough_results_reach_true_cost75.json');
const a2 = load('playthrough_results_reach_true_cost75_rest.json');
const old = load('playthrough_results_regulars.json');
const f3 = load('playthrough_results_fund_v3.json');
const goals = JSON.parse(fs.readFileSync(new URL('../../data/campaigns/week7.json', dir), 'utf8')).goals;
const NAMES = { forecast_good: '予報＋基本GOOD', forecast_favorites: '予報＋既知好物', always_small: '小仕込み固定',
  always_large: '大仕込み固定', cheap_valid: '安い完成料理だけ', bare_broth: '空の椀', forecast_mistakes: 'Day3・5に取り違え',
  favorite_oracle: '初回から好物（上限の目安）', no_split: '団体を分割しない', strength_neglect: '濃さ・鮮度のミス',
  decline_one_group: '毎日1組を断る', decline_once: '3日目に1組だけ断る', two_failures: '品質失敗2件',
  fund_final_only: 'fund_final_only（最終日の夜だけ積めるだけ）', fund_steady: 'fund_steady（毎晩、刻みの中央値を1回）',
  fund_max_safe: 'fund_max_safe（毎晩、積めるだけ）' };
const f0 = x => Math.round(x).toString();
const f1 = x => x.toFixed(1);
const pct = x => (100 * x).toFixed(1) + '%';
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0;
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const goodPlus = r => r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0);
const runsOf = (res, p) => res.runs.filter(r => r.policy === p);
const out = [];
const w = s => out.push(s);

w('# 運営費75（データ反映後）の新しい基準と修繕基金');
w('');
w('> 数字と事実の報告です。**75は暫定値**で、フェーズ5の最初の人の試遊のあとに見直します。');
w('');
w('## 1. D 新しい基準（運営費75をデータに反映・reach_true・13方針×30シード）');
w('');
w(`- 結果ファイル: \`playthrough_results_regulars_v2.json\`（コミット \`${v2.commit.slice(0, 7)}\`、運営費${v2.daily_operating_cost}、データ上の運営費${v2.daily_operating_cost_data}、上書き: ${v2.daily_operating_cost_overridden}、reach: ${v2.reach}）。`);
// A（引数で上書き）との全キー比較
const aRuns = [...a1.runs, ...a2.runs];
let n = 0; const bad = [];
for (const r of v2.runs) {
  const o = aRuns.find(x => x.policy === r.policy && x.seed === r.seed);
  if (!o) { bad.push(['missing', r.policy, r.seed]); continue; }
  n++;
  for (const k of new Set([...Object.keys(o), ...Object.keys(r)])) if (JSON.stringify(o[k]) !== JSON.stringify(r[k])) bad.push([r.policy, r.seed, k]);
}
w(`- **Aの結果（運営費を引数で75に上書き）との全キー比較: ${n}／${v2.runs.length}周を比較、不一致 ${bad.length}**${bad.length ? '：' + JSON.stringify(bad.slice(0, 10)) : ''}。`);
w('- 旧 `playthrough_results_regulars.json`（運営費65・12/13/14）は上書きしていません。データが75・reach_true になったので、旧結果との全キー一致は意図して崩れています。');
w('');
w('| 方針 | 周 | 最終現金 平均（旧→新） | 最小〜最大（新） | 1500達成（旧→新） | 1600達成（旧→新） | GOOD以上率（新） | ゲームオーバー | 早期閉店の夜 |');
w('|---|---:|---|---|---:|---:|---:|---:|---:|');
for (const p of v2.policies) {
  const o = runsOf(old, p), r = runsOf(v2, p);
  const cash = x => x.map(q => q.cash);
  const t = (rs, th) => mean(rs.map(q => Number((q.result_summary?.cash_plus_repair ?? q.cash) >= th)));
  const gr = rs => mean(rs.map(q => goodPlus(q) / Math.max(q.result_summary?.judged_cups ?? sumRows(q, 'judged_demand'), 1)));
  w(`| ${NAMES[p]} | ${r.length} | ${f0(mean(cash(o)))}→${f0(mean(cash(r)))} | ${Math.min(...cash(r))}〜${Math.max(...cash(r))} | ${pct(t(o, goals.cash_standard))}→${pct(t(r, goals.cash_standard))} | ${pct(t(o, goals.cash_challenge))}→${pct(t(r, goals.cash_challenge))} | ${pct(gr(r))} | ${r.reduce((s, q) => s + q.incidents.filter(i => i.type === 'game_over').length, 0)} | ${r.reduce((s, q) => s + q.rows.filter(d => d.closed_early).length, 0)} |`);
}
w('');
w('10.13の判定（項目1・1b・2・3・4・D1）は、Aの結果と全周が一致するので `PLAYTHROUGH_RESULTS_COST75.md` §1.1 と同じです（すべて合格）。');
w('');

// ---- R3 ----
w('## 2. R3 修繕基金（運営費75をデータに反映・reach_true・基準方針＋基金3方針×30シード）');
w('');
w(`- 結果ファイル: \`playthrough_results_fund_v3.json\`（コミット \`${f3.commit.slice(0, 7)}\`、運営費${f3.daily_operating_cost}、reach: ${f3.reach}）。`);
const fc = f3.fund_checks;
w(`- 実行時の検査: 基準方針の対（${fc.control_pairs}組）、基金の周 ${fc.fund_runs}、\`cash_plus_repair\` が基準方針の最終現金と一致しない周 **${fc.cash_plus_repair_mismatch.length}**、1〜6日目の行が基準方針と違う周 **${fc.days_1_to_6_rows_mismatch.length}**、ゲームオーバー **${fc.game_over_incidents}**、完走しなかった周 **${fc.incomplete_runs.length}**、進行停止 **${fc.stalled_runs}**。`);
if (fc.cash_plus_repair_mismatch.length) w('  - 一致しなかった周: ' + JSON.stringify(fc.cash_plus_repair_mismatch));
w('');
const goalOf = (p, seed, id) => f3.goals_by_run.find(g => g.policy === p && g.seed === seed)?.goals.find(g => g.id === id)?.achieved ?? false;
w('| 方針 | 周 | 最終現金 平均 | 修繕額 平均 | 現金＋修繕額 平均 | 最小〜最大 | 標準（≥1500） | 挑戦（≥1600） | 安全上限が1晩の上限（30）未満だった夜 | 積んだ夜の合計 |');
w('|---|---:|---:|---:|---:|---|---:|---:|---:|---:|');
for (const p of f3.policies) {
  const rs = runsOf(f3, p);
  const total = r => r.result_summary?.cash_plus_repair ?? r.cash;
  const paid = r => r.result_summary?.repair_paid ?? 0;
  const below = rs.reduce((s, r) => s + (r.fund_log ?? []).filter(l => l.safe_limit < 30).length, 0);
  const nights = rs.reduce((s, r) => s + (r.fund_log ?? []).filter(l => l.amount > 0).length, 0);
  w(`| ${NAMES[p]} | ${rs.length} | ${f0(mean(rs.map(r => r.cash)))} | ${f0(mean(rs.map(paid)))} | ${f0(mean(rs.map(total)))} | ${Math.min(...rs.map(total))}〜${Math.max(...rs.map(total))} | ${pct(mean(rs.map(r => Number(goalOf(p, r.seed, 'cash_standard')))))} | ${pct(mean(rs.map(r => Number(goalOf(p, r.seed, 'cash_challenge')))))} | ${p === 'forecast_good' ? '-' : below} | ${p === 'forecast_good' ? '-' : nights} |`);
}
w('');
// 安全上限が効いた夜（積む前の安全上限が1晩の上限30未満）の内訳
w('### 2.1 安全上限が効いた夜（積む前の安全上限＜30）');
w('');
for (const p of f3.policies.filter(x => x !== 'forecast_good')) {
  const rs = runsOf(f3, p);
  const by = {};
  for (const r of rs) for (const l of (r.fund_log ?? [])) if (l.safe_limit < 30) { by[l.day] = (by[l.day] || 0) + 1; }
  const entries = Object.keys(by).sort((a, b) => a - b).map(d => `Day${d}×${by[d]}`);
  w(`- ${NAMES[p]}: ${entries.length ? entries.join('、') : 'なし'}`);
}
w('');
fs.writeFileSync(new URL('PLAYTHROUGH_RESULTS_COST75_V2.md', dir), out.join('\n') + '\n');
console.log(out.join('\n'));
