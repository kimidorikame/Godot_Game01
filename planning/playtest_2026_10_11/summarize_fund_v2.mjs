// 4-9④-③ 修繕基金（見直し後）の別枠方針の集計。基準方針（forecast_good）と、同じ実行・同じシードの基金の方針を並べ、
// 見直し前（4-9③の playthrough_summary_fund.json）との比較も付ける。
// 使い方: node summarize_fund_v2.mjs [入力JSON名(既定playthrough_results_fund_v2.json)]
// 出力: playthrough_summary_fund_v2.json（機械可読）／PLAYTHROUGH_RESULTS_FUND_V2.md（人が読む要約）。
// 見直し前の結果（playthrough_results_fund.json・playthrough_summary_fund.json・PLAYTHROUGH_RESULTS_FUND.md）は上書きしない。
// 数値の調整は提案しない。測った結果を事実として並べるだけ。
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const inName = process.argv[2] ?? 'playthrough_results_fund_v2.json';
const result = JSON.parse(fs.readFileSync(new URL(inName, dir)));
const v1 = fs.existsSync(new URL('playthrough_summary_fund.json', dir)) ? JSON.parse(fs.readFileSync(new URL('playthrough_summary_fund.json', dir))) : null;
const BASE = 'forecast_good';
const FUND = ['fund_final_only', 'fund_steady', 'fund_max_safe'];
const policies = [BASE, ...FUND].filter(p => result.policies.includes(p));
const mean = (a, f) => a.length ? a.reduce((s, x) => s + f(x), 0) / a.length : 0;
const min = (a, f) => a.length ? Math.min(...a.map(f)) : 0;
const max = (a, f) => a.length ? Math.max(...a.map(f)) : 0;
const median = a => { if (!a.length) return 0; const b = [...a].sort((x, y) => x - y); const m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2; };
const pct = x => (100 * x).toFixed(1) + '%';
const f1 = x => x.toFixed(1);
const runsOf = p => result.runs.filter(r => r.policy === p);
const goalsOf = (p, seed) => result.goals_by_run.find(g => g.policy === p && g.seed === seed)?.goals ?? [];
const achieved = (p, seed, id) => !!goalsOf(p, seed).find(g => g.id === id)?.achieved;
const goalIds = ['complete', 'cash_standard', 'cash_challenge', 'good_rate', 'regular_great'];
const goalLabel = { complete: '完走', cash_standard: '標準（現金＋修繕1500）', cash_challenge: '挑戦（現金＋修繕1600）',
  good_rate: '料理（GOOD以上85%）', regular_great: '常連（GREAT8杯）' };
const sum = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
// 完走しなかった周は結果画面（Result.summarize）に到達せず result_summary が空。その周は営業した日の行から組む。
const summ = r => {
  if (r.result_summary && Object.keys(r.result_summary).length > 0) return r.result_summary;
  const paid = (r.fund_log ?? []).length ? r.fund_log.at(-1).paid_after : 0;
  return { cash: r.cash, repair_paid: paid, cash_plus_repair: r.cash + paid, days: r.rows.length,
    served_cups: sum(r, 'served'), unserved_cups: sum(r, 'unserved'), judged_cups: sum(r, 'judged_demand'),
    good_plus_cups: r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0),
    regular_great: sum(r, 'regular_great'), early_close_days: r.rows.filter(d => d.closed_early).length,
    spoiled_value: sum(r, 'spoiled_value'), incomplete: true };
};
const names = { forecast_good: '基準：forecast_good（基金なし）', fund_final_only: 'fund_final_only（最終日の夜だけ積めるだけ）',
  fund_steady: 'fund_steady（毎晩、1晩の上限ぶんを積めるときだけ）', fund_max_safe: 'fund_max_safe（毎晩、積めるだけ）' };
const targetLabel = { sign: '手書きの看板（150）', shelf: '棚（200）', awning: '雨よけ（200）', owner: '屋台を自分の名義に（600）' };
const targetIds = ['sign', 'shelf', 'awning', 'owner'];

const rows = [];
for (const p of policies) {
  const rs = runsOf(p);
  const sm = r => summ(r);
  const goodPlus = r => sm(r).good_plus_cups ?? 0, judged = r => sm(r).judged_cups ?? 0;
  const repairedBy = Object.fromEntries(targetIds.map(id => [id, rs.filter(r => (r.repaired ?? []).includes(id)).length]));
  const repairedDays = Object.fromEntries(targetIds.map(id => [id, rs.map(r => (r.stage_days ?? {})[id]).filter(v => v !== undefined)]));
  rows.push({
    policy: p, n: rs.length,
    completed: rs.filter(r => r.completed).length, stalled: rs.filter(r => r.stalled).length,
    gameOver: rs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    cash: { mean: mean(rs, r => sm(r).cash), min: min(rs, r => sm(r).cash), max: max(rs, r => sm(r).cash) },
    repair: { mean: mean(rs, r => sm(r).repair_paid), min: min(rs, r => sm(r).repair_paid), max: max(rs, r => sm(r).repair_paid) },
    cashPlusRepair: { mean: mean(rs, r => sm(r).cash_plus_repair), min: min(rs, r => sm(r).cash_plus_repair), max: max(rs, r => sm(r).cash_plus_repair) },
    goalRate: Object.fromEntries(goalIds.map(id => [id, mean(rs, r => Number(achieved(p, r.seed, id)))])),
    goodRate: rs.reduce((s, r) => s + goodPlus(r), 0) / Math.max(rs.reduce((s, r) => s + judged(r), 0), 1),
    served: mean(rs, r => sm(r).served_cups), unserved: mean(rs, r => sm(r).unserved_cups),
    regularGreat: mean(rs, r => sm(r).regular_great),
    earlyCloseNights: rs.reduce((s, r) => s + (sm(r).early_close_days ?? 0), 0),
    spoiled: mean(rs, r => sm(r).spoiled_value), rep: mean(rs, r => r.rep),
    fundNights: mean(rs, r => (r.fund_log ?? []).filter(l => l.amount > 0).length),
    repairedBy, repairedDays,
    targetPaidMean: Object.fromEntries(targetIds.map(id => [id, mean(rs, r => (r.target_paid ?? {})[id] ?? 0)])),
    servedByDay: Array.from({ length: 7 }, (_, i) => { const a = rs.filter(r => r.rows[i]); return a.length ? mean(a, r => r.rows[i].served) : null; }),
    cashByDay: Array.from({ length: 7 }, (_, i) => { const a = rs.filter(r => r.rows[i]); return a.length ? mean(a, r => r.rows[i].cash) : null; }),
    nByDay: Array.from({ length: 7 }, (_, i) => rs.filter(r => r.rows[i]).length),
    fundByDay: Array.from({ length: 7 }, (_, i) => { const a = rs.filter(r => (r.fund_log ?? [])[i]); return a.length ? mean(a, r => r.fund_log[i].amount) : null; }),
    safeByDay: Array.from({ length: 7 }, (_, i) => { const a = rs.filter(r => (r.fund_log ?? [])[i]); return a.length ? { mean: mean(a, r => r.fund_log[i].safe_limit), min: min(a, r => r.fund_log[i].safe_limit), reserve: mean(a, r => r.fund_log[i].reserve) } : null; }),
    nightsSafeBelowNightly: rs.reduce((s, r) => s + (r.fund_log ?? []).filter(l => l.safe_limit < 30).length, 0),
  });
}
const by = Object.fromEntries(rows.map(r => [r.policy, r]));

const paired = {};
for (const p of FUND.filter(x => by[x])) {
  const diffs = [];
  for (const r of runsOf(p)) {
    const base = runsOf(BASE).find(b => b.seed === r.seed);
    if (!base) continue;
    diffs.push({ seed: r.seed,
      cpr: summ(r).cash_plus_repair - summ(base).cash_plus_repair,
      cash: summ(r).cash - summ(base).cash,
      served: summ(r).served_cups - summ(base).served_cups,
      unserved: summ(r).unserved_cups - summ(base).unserved_cups,
      standardLost: achieved(BASE, r.seed, 'cash_standard') && !achieved(p, r.seed, 'cash_standard'),
      standardGained: !achieved(BASE, r.seed, 'cash_standard') && achieved(p, r.seed, 'cash_standard'),
      anyGoalLost: goalIds.some(id => achieved(BASE, r.seed, id) && !achieved(p, r.seed, id)) });
  }
  paired[p] = {
    pairs: diffs.length,
    cprMean: mean(diffs, d => d.cpr), cprMin: min(diffs, d => d.cpr), cprMax: max(diffs, d => d.cpr),
    cprNonZero: diffs.filter(d => d.cpr !== 0).length,
    cashMean: mean(diffs, d => d.cash), servedMean: mean(diffs, d => d.served), unservedMean: mean(diffs, d => d.unserved),
    standardLost: diffs.filter(d => d.standardLost).map(d => d.seed),
    standardGained: diffs.filter(d => d.standardGained).map(d => d.seed),
    anyGoalLost: diffs.filter(d => d.anyGoalLost).map(d => d.seed),
  };
}

const summary = { source: inName, commit: result.commit, tracked_changes: result.tracked_changes,
  seeds: Math.max(...rows.map(r => r.n)), fund_checks: result.fund_checks, rows, paired };

// ---- 人が読む要約（PLAYTHROUGH_RESULTS_FUND_V2.md） ----
const L = [];
L.push('# 修繕基金の自動試遊（4-9④-③・見直し後）');
L.push('');
L.push(`- 入力: \`${inName}\`（コミット \`${String(result.commit).slice(0, 7)}\`・${rows[0]?.n} シード/方針。基準方針も同じ実行で走らせ、同じシード同士を対にした）`);
L.push('- 見直し後の仕様: 修繕の対象を看板（150）・棚（200）・雨よけ（200）・名義（600。他の3つが修繕済みになるまで積めない）に分け、1晩に積める額は合計30まで（最終日にも掛かる）、刻みは10と30。安全上限は「使える現金 − 翌日の確保額（運営費・翌日の請求・翌日の仕込み・翌日の材料費）」。');
L.push('- 基金の方針は、仕入れ・仕込み・調理・接客を基準方針と同じにし、CLOSE の基金の操作だけが違う。積む先は毎回「最初の未修繕の対象」（まず看板）。');
L.push('- 数値の調整はしていない。測った結果を事実として並べる。');
L.push('- 既定の13方針×3シードは、基金の方針を足した後も `playthrough_results_regulars.json` と全キー差分0（別途確認）。');
L.push('- 見直し前（4-9③）の結果は `PLAYTHROUGH_RESULTS_FUND.md` ほかに残してあり、上書きしていない。');
L.push('');
L.push('## 実行時の検査（fund_checks）');
L.push('');
const fc = result.fund_checks ?? {};
L.push(`- 対照実験（fund_final_only と基準方針）: ${fc.control_pairs ?? 0} 組。cash_plus_repair が一致しない組 ${(fc.cash_plus_repair_mismatch ?? []).length}、1〜6日目の日別の行が一致しない組 ${(fc.days_1_to_6_rows_mismatch ?? []).length}`);
L.push(`- 基金の全方針・全シード（${fc.fund_runs ?? 0} 周）: ゲームオーバー ${fc.game_over_incidents ?? '?'} 件・停止 ${fc.stalled_runs ?? '?'} 周・未完走 ${(fc.incomplete_runs ?? []).length} 周`);
L.push('');
L.push('## 検査3（基金の全方針・全シードでゲームオーバー0・全周完走）');
L.push('');
const goInfo = p => {
  const rs = runsOf(p);
  const overs = rs.map(r => r.incidents.find(i => i.type === 'game_over')).filter(Boolean);
  return { p, n: rs.length, completed: rs.filter(r => r.completed).length, gameOver: overs.length,
    days: [...new Set(overs.map(o => o.day))].sort() };
};
const check3 = FUND.filter(p => by[p]).map(goInfo);
L.push(`検査3は**${check3.every(x => x.gameOver === 0 && x.completed === x.n) ? '成り立った' : '成り立たなかった'}**。`);
L.push('');
L.push('| 方針 | 周 | 完走 | ゲームオーバー | 起きた日（WAKE） |');
L.push('|---|---:|---:|---:|---|');
for (const x of check3) L.push(`| ${names[x.p]} | ${x.n} | ${x.completed} | ${x.gameOver} | ${x.days.length ? x.days.map(d => 'Day' + d).join('・') : '—'} |`);
L.push('');
L.push('## 最終の現金・修繕額・現金＋修繕額');
L.push('');
L.push('| 方針 | 周 | 現金 平均（最小〜最大） | 支払済み修繕額 平均（最小〜最大） | 現金＋修繕 平均（最小〜最大） |');
L.push('|---|---:|---|---|---|');
for (const r of rows) L.push(`| ${names[r.policy]} | ${r.n} | ${r.cash.mean.toFixed(0)}（${r.cash.min}〜${r.cash.max}） | ${r.repair.mean.toFixed(0)}（${r.repair.min}〜${r.repair.max}） | ${r.cashPlusRepair.mean.toFixed(0)}（${r.cashPlusRepair.min}〜${r.cashPlusRepair.max}） |`);
L.push('');
L.push('## 目標の達成率（実装の Result.judge_goals で判定）');
L.push('');
L.push(`| 方針 | ${goalIds.map(id => goalLabel[id]).join(' | ')} |`);
L.push(`|---|${goalIds.map(() => '---:').join('|')}|`);
for (const r of rows) L.push(`| ${names[r.policy]} | ${goalIds.map(id => pct(r.goalRate[id])).join(' | ')} |`);
L.push('');
L.push('## 営業への影響の目安');
L.push('');
L.push('| 方針 | GOOD以上率 | 提供杯数 平均 | 未提供杯数 平均 | 早期閉店の夜（合計） | 廃棄額 平均 | 常連GREAT 平均 | 最終評判 平均 | 積んだ夜 平均 |');
L.push('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
for (const r of rows) L.push(`| ${names[r.policy]} | ${pct(r.goodRate)} | ${f1(r.served)} | ${f1(r.unserved)} | ${r.earlyCloseNights} | ${r.spoiled.toFixed(0)} | ${f1(r.regularGreat)} | ${f1(r.rep)} | ${f1(r.fundNights)} |`);
L.push('');
L.push('## 基準方針との対（同じシード同士の差）');
L.push('');
L.push('| 方針 | 組 | 現金＋修繕 差の平均（最小〜最大） | 差が0でない組 | 現金 差の平均 | 提供杯数 差の平均 | 未提供 差の平均 | 標準目標を失ったシード | 標準目標を得たシード | いずれかの目標を失ったシード数 |');
L.push('|---|---:|---|---:|---:|---:|---:|---|---|---:|');
for (const p of FUND.filter(x => paired[x])) {
  const q = paired[p];
  L.push(`| ${names[p]} | ${q.pairs} | ${q.cprMean.toFixed(1)}（${q.cprMin}〜${q.cprMax}） | ${q.cprNonZero} | ${q.cashMean.toFixed(1)} | ${q.servedMean.toFixed(2)} | ${q.unservedMean.toFixed(2)} | ${q.standardLost.length ? q.standardLost.join(',') : 'なし'} | ${q.standardGained.length ? q.standardGained.join(',') : 'なし'} | ${q.anyGoalLost.length} |`);
}
L.push('');
L.push('## 修繕済みになった対象と、その日（何夜目に直るか）');
L.push('');
L.push('各セルは「修繕済みになった周の数 ／ その夜（Day）の平均（最早〜最遅）」。積む先は毎回最初の未修繕の対象。');
L.push('');
L.push(`| 方針 | ${targetIds.map(id => targetLabel[id]).join(' | ')} |`);
L.push(`|---|${targetIds.map(() => '---').join('|')}|`);
for (const r of rows.filter(x => FUND.includes(x.policy))) {
  const cell = id => { const d = r.repairedDays[id]; return d.length ? `${r.repairedBy[id]}周 ／ ${f1(mean(d, x => x))}（${Math.min(...d)}〜${Math.max(...d)}）` : `${r.repairedBy[id]}周`; };
  L.push(`| ${names[r.policy]} | ${targetIds.map(cell).join(' | ')} |`);
}
L.push('');
L.push('最終日の時点の各対象への支払済み額の平均:');
L.push('');
L.push(`| 方針 | ${targetIds.map(id => targetLabel[id]).join(' | ')} |`);
L.push(`|---|${targetIds.map(() => '---:').join('|')}|`);
for (const r of rows.filter(x => FUND.includes(x.policy))) L.push(`| ${names[r.policy]} | ${targetIds.map(id => f1(r.targetPaidMean[id])).join(' | ')} |`);
L.push('');
L.push('## 夜ごとに積んだ額と、安全上限（積む前）・翌日の確保額');
L.push('');
L.push('平均（積んだ額／安全上限の最小）。安全上限＝使える現金 − 翌日の確保額。確保額は翌日の運営費＋請求＋仕込み＋材料費。最終日（Day7）の確保額は0。');
L.push('');
L.push('| 方針 | ' + Array.from({ length: 7 }, (_, i) => `Day${i + 1}`).join(' | ') + ' |');
L.push('|---|' + Array.from({ length: 7 }, () => '---:').join('|') + '|');
for (const r of rows.filter(x => FUND.includes(x.policy))) L.push(`| ${names[r.policy]} | ${r.fundByDay.map((f, i) => f === null ? '—' : `${f.toFixed(1)}／安全${r.safeByDay[i].min}・確保${r.safeByDay[i].reserve.toFixed(0)}`).join(' | ')} |`);
L.push('');
L.push(`安全上限が1晩の上限（30）より小さかった夜の数（全周の合計）: ${FUND.filter(x => by[x]).map(p => `${p}＝${by[p].nightsSafeBelowNightly}`).join('、')}`);
L.push('');
L.push('## 日ごとの平均（提供杯数／夜の終わりの現金）');
L.push('');
L.push('その日の行のある周だけの平均。行のある周が全シードに満たない日は（N周）を付ける。ゲームオーバーで営業しなかった日は「—」。');
L.push('');
L.push('| 方針 | Day1 | Day2 | Day3 | Day4 | Day5 | Day6 | Day7 |');
L.push('|---|---:|---:|---:|---:|---:|---:|---:|');
for (const r of rows) L.push(`| ${names[r.policy]} | ${r.servedByDay.map((s, i) => s === null ? '—' : `${s.toFixed(1)} / ${r.cashByDay[i].toFixed(0)}${r.nByDay[i] < r.n ? `（${r.nByDay[i]}周）` : ''}`).join(' | ')} |`);
L.push('');
// ---- 見直し前（4-9③）との比較 ----
if (v1) {
  L.push('## 見直し前（4-9③）との比較');
  L.push('');
  L.push('見直し前は、段階の累計150／300／600・刻み25／50／100・安全上限＝使える現金−運営費−最小の仕込み（80）。方針の内容も異なる（毎晩50／毎晩積めるだけ／最終日に積めるだけ）。同じシード（1〜30）・同じ基準方針の結果で並べる。');
  L.push('');
  L.push('| 方針 | 見直し前 完走 | 見直し後 完走 | 見直し前 ゲームオーバー | 見直し後 ゲームオーバー | 見直し前 現金＋修繕 平均 | 見直し後 現金＋修繕 平均 | 見直し前 支払済み修繕額 平均 | 見直し後 支払済み修繕額 平均 | 見直し前 標準目標 | 見直し後 標準目標 |');
  L.push('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (const p of policies) {
    const a = v1.rows.find(x => x.policy === p), b = by[p];
    if (!a || !b) continue;
    L.push(`| ${names[p]} | ${a.completed}/${a.n} | ${b.completed}/${b.n} | ${a.gameOver} | ${b.gameOver} | ${a.cashPlusRepair.mean.toFixed(0)} | ${b.cashPlusRepair.mean.toFixed(0)} | ${a.repair.mean.toFixed(0)} | ${b.repair.mean.toFixed(0)} | ${pct(a.goalRate.cash_standard)} | ${pct(b.goalRate.cash_standard)} |`);
  }
  L.push('');
  summary.v1_comparison = policies.map(p => { const a = v1.rows.find(x => x.policy === p), b = by[p]; return a && b ? { policy: p,
    before: { completed: a.completed, gameOver: a.gameOver, cashPlusRepair: a.cashPlusRepair.mean, repair: a.repair.mean, standard: a.goalRate.cash_standard },
    after: { completed: b.completed, gameOver: b.gameOver, cashPlusRepair: b.cashPlusRepair.mean, repair: b.repair.mean, standard: b.goalRate.cash_standard } } : null; }).filter(Boolean);
}
const base = runsOf(BASE);
if (base.length) {
  L.push('## 基準方針（forecast_good）の日別の分布（参考）');
  L.push('');
  L.push(`各セルは 平均 / 中央値 / 最小 / 最大（${base.length}シード）。仕入れ額＝仕込み＋市場＋だし（初日セットは含めない）。夜の終わりの現金は基金を積まない場合の値。`);
  L.push('');
  L.push('| 日 | 仕入れ額 | 夜の終わりの現金 |');
  L.push('|---:|---|---|');
  const dist = a => `${(a.reduce((x, y) => x + y, 0) / a.length).toFixed(0)} / ${median(a)} / ${Math.min(...a)} / ${Math.max(...a)}`;
  for (let day = 1; day <= 7; day++) {
    const rows7 = base.map(r => r.rows[day - 1]).filter(Boolean);
    const buy = rows7.map(d => (d.spend.prep ?? 0) + (d.spend.market ?? 0) + (d.spend.dashi ?? 0));
    L.push(`| Day${day} | ${dist(buy)} | ${dist(rows7.map(d => d.cash))} |`);
  }
  L.push('');
}
summary.check3 = check3;
fs.writeFileSync(new URL('playthrough_summary_fund_v2.json', dir), JSON.stringify(summary, null, 2));
fs.writeFileSync(new URL('PLAYTHROUGH_RESULTS_FUND_V2.md', dir), L.join('\n'));
console.log('wrote playthrough_summary_fund_v2.json / PLAYTHROUGH_RESULTS_FUND_V2.md');
