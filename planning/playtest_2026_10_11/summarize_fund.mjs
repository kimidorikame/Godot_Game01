// 4-9③ 修繕基金の別枠方針の集計。基準方針（forecast_good）と、同じ実行・同じシードの基金の方針を並べる。
// 使い方: node summarize_fund.mjs [入力JSON名(既定playthrough_results_fund.json)]
// 出力: playthrough_summary_fund.json（機械可読）／PLAYTHROUGH_RESULTS_FUND.md（人が読む要約）。
// 既存の summarize_playthroughs.mjs は変えない（Day1のキャッシュフロー検査が、Day1に基金を積む方針に合わないため）。
// 数値の調整は提案しない。測った結果を事実として並べるだけ。
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const inName = process.argv[2] ?? 'playthrough_results_fund.json';
const result = JSON.parse(fs.readFileSync(new URL(inName, dir)));
const BASE = 'forecast_good';
const FUND = ['fund_final_only', 'fund_steady', 'fund_max_safe'];
const policies = [BASE, ...FUND].filter(p => result.policies.includes(p));
const mean = (a, f) => a.length ? a.reduce((s, x) => s + f(x), 0) / a.length : 0;
const min = (a, f) => a.length ? Math.min(...a.map(f)) : 0;
const max = (a, f) => a.length ? Math.max(...a.map(f)) : 0;
const pct = x => (100 * x).toFixed(1) + '%';
const f1 = x => x.toFixed(1);
const runsOf = p => result.runs.filter(r => r.policy === p);
const goalsOf = (p, seed) => result.goals_by_run.find(g => g.policy === p && g.seed === seed)?.goals ?? [];
const achieved = (p, seed, id) => !!goalsOf(p, seed).find(g => g.id === id)?.achieved;
const goalIds = ['complete', 'cash_standard', 'cash_challenge', 'good_rate', 'regular_great'];
const goalLabel = { complete: '完走', cash_standard: '標準（現金＋修繕1500）', cash_challenge: '挑戦（現金＋修繕1600）',
  good_rate: '料理（GOOD以上85%）', regular_great: '常連（GREAT8杯）' };
const sum = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
// 完走しなかった周は結果画面（Result.summarize）に到達せず result_summary が空。その周は営業した日の行から
// 同じ項目を組む（現金＝停止時点の現金、支払済み修繕額＝基金の累計、杯数・品質・廃棄は営業した日の合計）。
// 目標の判定（goals_by_run）は結果画面を経ない周は空＝未達として数える。
const summ = r => {
  if (r.result_summary && Object.keys(r.result_summary).length > 0) return r.result_summary;
  const paid = (r.fund_log ?? []).length ? r.fund_log.at(-1).paid_after : 0;
  return { cash: r.cash, repair_paid: paid, cash_plus_repair: r.cash + paid, days: r.rows.length,
    served_cups: sum(r, 'served'), unserved_cups: sum(r, 'unserved'), judged_cups: sum(r, 'judged_demand'),
    good_plus_cups: r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0),
    regular_great: sum(r, 'regular_great'), early_close_days: r.rows.filter(d => d.closed_early).length,
    spoiled_value: sum(r, 'spoiled_value'), incomplete: true };
};

const rows = [];
for (const p of policies) {
  const rs = runsOf(p);
  const sm = r => summ(r);
  const goodPlus = r => sm(r).good_plus_cups ?? 0, judged = r => sm(r).judged_cups ?? 0;
  const stageCount = { '-1': 0, '0': 0, '1': 0, '2': 0 };
  const stageDay = { '0': [], '1': [], '2': [] };
  for (const r of rs) {
    const s = r.stage_reached ?? -1;
    stageCount[String(s)] = (stageCount[String(s)] ?? 0) + 1;
    for (const k of Object.keys(r.stage_days ?? {})) stageDay[k]?.push(r.stage_days[k]);
  }
  const fundNights = r => (r.fund_log ?? []).filter(l => l.amount > 0).length;
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
    spoiled: mean(rs, r => sm(r).spoiled_value),
    rep: mean(rs, r => r.rep),
    fundNights: mean(rs, fundNights),
    stageCount, stageDayMean: Object.fromEntries(Object.entries(stageDay).map(([k, v]) => [k, v.length ? mean(v, x => x) : null])),
    stageDayMin: Object.fromEntries(Object.entries(stageDay).map(([k, v]) => [k, v.length ? Math.min(...v) : null])),
    // 行のある周だけで平均する（ゲームオーバーで営業しなかった日を0として混ぜない）。nByDay＝その日の行のある周の数。
    servedByDay: Array.from({ length: 7 }, (_, i) => { const a = rs.filter(r => r.rows[i]); return a.length ? mean(a, r => r.rows[i].served) : null; }),
    cashByDay: Array.from({ length: 7 }, (_, i) => { const a = rs.filter(r => r.rows[i]); return a.length ? mean(a, r => r.rows[i].cash) : null; }),
    nByDay: Array.from({ length: 7 }, (_, i) => rs.filter(r => r.rows[i]).length),
  });
}
const by = Object.fromEntries(rows.map(r => [r.policy, r]));

// 同じシードで基準方針と対にした差
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
      goodPlus: summ(r).good_plus_cups - summ(base).good_plus_cups,
      standardLost: achieved(BASE, r.seed, 'cash_standard') && !achieved(p, r.seed, 'cash_standard'),
      standardGained: !achieved(BASE, r.seed, 'cash_standard') && achieved(p, r.seed, 'cash_standard'),
      anyGoalLost: goalIds.some(id => achieved(BASE, r.seed, id) && !achieved(p, r.seed, id)) });
  }
  paired[p] = {
    pairs: diffs.length,
    cprMean: mean(diffs, d => d.cpr), cprMin: min(diffs, d => d.cpr), cprMax: max(diffs, d => d.cpr),
    cprNonZero: diffs.filter(d => d.cpr !== 0).length,
    cashMean: mean(diffs, d => d.cash),
    servedMean: mean(diffs, d => d.served), unservedMean: mean(diffs, d => d.unserved), goodPlusMean: mean(diffs, d => d.goodPlus),
    standardLost: diffs.filter(d => d.standardLost).map(d => d.seed),
    standardGained: diffs.filter(d => d.standardGained).map(d => d.seed),
    anyGoalLost: diffs.filter(d => d.anyGoalLost).map(d => d.seed),
  };
}

const summary = { source: inName, commit: result.commit, tracked_changes: result.tracked_changes,
  seeds: Math.max(...rows.map(r => r.n)), fund_checks: result.fund_checks, rows, paired };

// ---- 人が読む要約（PLAYTHROUGH_RESULTS_FUND.md） ----
const L = [];
const names = { forecast_good: '基準：forecast_good（基金なし）', fund_final_only: 'fund_final_only（最終日だけ積めるだけ）',
  fund_steady: 'fund_steady（毎晩50を1回）', fund_max_safe: 'fund_max_safe（毎晩積めるだけ）' };
L.push('# 修繕基金の自動試遊（4-9③・別枠方針）');
L.push('');
L.push(`- 入力: \`${inName}\`（コミット \`${String(result.commit).slice(0, 7)}\`・${rows[0]?.n} シード/方針。基準方針も同じ実行で走らせ、同じシード同士を対にした）`);
L.push('- 数値の調整はしていない。測った結果を事実として並べる。基金の方針は、仕入れ・仕込み・調理・接客を基準方針と同じにし、CLOSE の基金の操作だけが違う。');
L.push('- 既定の13方針×3シードは、基金の方針を足した後も `playthrough_results_regulars.json` と全キー差分0（別途確認）。');
L.push('');
L.push('## 実行時の検査（fund_checks）');
const fc = result.fund_checks ?? {};
L.push('');
L.push(`- 対照実験（fund_final_only と基準方針）: ${fc.control_pairs ?? 0} 組。cash_plus_repair が一致しない組 ${(fc.cash_plus_repair_mismatch ?? []).length}、1〜6日目の日別の行が一致しない組 ${(fc.days_1_to_6_rows_mismatch ?? []).length}`);
L.push(`- 基金の全方針・全シード（${fc.fund_runs ?? 0} 周）: ゲームオーバー ${fc.game_over_incidents ?? '?'} 件・停止 ${fc.stalled_runs ?? '?'} 周・未完走 ${(fc.incomplete_runs ?? []).length} 周`);
L.push('');
// ---- 検査3（ゲームオーバー0・全周完走）の事実 ----
const median = a => { if (!a.length) return 0; const b = [...a].sort((x, y) => x - y); const m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2; };
const dist = a => ({ mean: a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0, median: median(a), min: a.length ? Math.min(...a) : 0, max: a.length ? Math.max(...a) : 0 });
const distText = (d, digits = 0) => `${d.mean.toFixed(digits)} / ${d.median.toFixed(digits)} / ${d.min} / ${d.max}`;
const goInfo = p => {
  const rs = runsOf(p);
  const overs = rs.map(r => r.incidents.find(i => i.type === 'game_over')).filter(Boolean);
  return { p, n: rs.length, completed: rs.filter(r => r.completed).length, gameOver: overs.length,
    days: [...new Set(overs.map(o => o.day))].sort(), cashes: overs.map(o => o.cash), seeds: rs.filter(r => !r.completed).map(r => r.seed) };
};
L.push('## 実行時の検査3（基金の全方針・全シードでゲームオーバー0・全周完走）の結果');
L.push('');
const check3 = FUND.filter(p => by[p]).map(goInfo);
L.push(`検査3は**${check3.every(x => x.gameOver === 0 && x.completed === x.n) ? '成り立った' : '成り立たなかった'}**。`);
L.push('');
L.push('| 方針 | 周 | 完走 | ゲームオーバー | 起きた日（WAKE） | ゲームオーバー時の現金（平均／最小〜最大） |');
L.push('|---|---:|---:|---:|---|---|');
for (const x of check3) L.push(`| ${names[x.p]} | ${x.n} | ${x.completed} | ${x.gameOver} | ${x.days.length ? x.days.map(d => 'Day' + d).join('・') : '—'} | ${x.cashes.length ? `${(x.cashes.reduce((a, b) => a + b, 0) / x.cashes.length).toFixed(1)}／${Math.min(...x.cashes)}〜${Math.max(...x.cashes)}` : '—'} |`);
L.push('');
const mx = check3.find(x => x.p === 'fund_max_safe');
if (mx && mx.gameOver > 0) {
  const byDay = {};
  for (const r of runsOf('fund_max_safe')) { const o = r.incidents.find(i => i.type === 'game_over'); if (o) (byDay[o.day] ??= []).push(r.seed); }
  const dayText = Object.keys(byDay).sort().map(d => `Day${d}の WAKE: ${byDay[d].length}周（シード${byDay[d].join(',')}）`).join('、');
  L.push(`**事実**: fund_max_safe は${mx.n}周のうち${mx.gameOver}周（全シード）で、WAKE（運営費の支払い）でゲームオーバーになり、完走は${mx.completed}周。` +
    `起きた日の内訳は ${dayText}。他の方針（fund_final_only・fund_steady）では起きていない。`);
  L.push('');
  L.push('- 安全上限（使える現金 − 翌朝の運営費 − 翌日の最小の仕込み額）は、積んだ翌朝（Day2）の運営費と最小の仕込みが払えることを守っていた（Day2 の WAKE でゲームオーバーになった周は無い）。');
  L.push('- 上限の計算に含まれない、Day2 以降の材料の購入費が不足し、提供不可の断りと未提供が増え、売上が落ちて現金が尽き、WAKE（Day4。1周は Day5）で運営費が払えなかった（次節の表）。');
  L.push('');
}
L.push('## fund_max_safe の日別の現金の推移と提供（基準方針との並記）');
L.push('');
L.push('朝＝その日の WAKE に入る前の現金（Day1 は初期の600。Day2 以降は前日の夜の終わり）。この後 WAKE で運営費を払う。夜の終わり＝基金を積んだ後の現金。提供・未提供・仕入れ額は全シードの平均（最小〜最大）。仕入れ額＝仕込み＋市場＋だし（初日セットは含めない）。Day4 の WAKE でゲームオーバーになった周は Day4 の行が無い（「行のある周」の列）。完走しなかった周の最終の現金・修繕額・杯数は、営業した日の行から組んだ停止時点の値。目標の判定は、結果画面に到達しない周を未達として数える。');
L.push('');
const dayStats = (p, day) => {
  const rs = runsOf(p);
  const morning = rs.map(r => day === 1 ? 600 : r.rows[day - 2]?.cash).filter(v => v !== undefined);
  const row = r => r.rows[day - 1];
  const withRow = rs.filter(r => row(r));
  const fmt = (arr) => arr.length ? `${(arr.reduce((a, b) => a + b, 0) / arr.length).toFixed(0)}（${Math.min(...arr)}〜${Math.max(...arr)}）` : '—';
  const spendOf = r => (row(r).spend.prep ?? 0) + (row(r).spend.market ?? 0) + (row(r).spend.dashi ?? 0);
  return { morning: fmt(morning), night: fmt(withRow.map(r => row(r).cash)), served: fmt(withRow.map(r => row(r).served)),
    unserved: fmt(withRow.map(r => row(r).unserved)), buy: fmt(withRow.map(spendOf)),
    fund: fmt(withRow.map(r => row(r).spend.fund ?? 0)), n: withRow.length };
};
L.push('| 日 | 方針 | 朝の現金 | 夜の終わりの現金 | 提供杯数 | 未提供杯数 | 仕入れ額 | 基金 | 行のある周 |');
L.push('|---:|---|---|---|---|---|---|---|---:|');
for (let day = 1; day <= 4; day++) for (const p of ['fund_max_safe', BASE].filter(x => by[x])) {
  const d = dayStats(p, day);
  L.push(`| Day${day} | ${p === BASE ? '基準（forecast_good）' : 'fund_max_safe'} | ${d.morning} | ${d.night} | ${d.served} | ${d.unserved} | ${d.buy} | ${d.fund} | ${d.n} |`);
}
L.push('');
const base = runsOf(BASE);
if (base.length) {
  L.push('## 基準方針（forecast_good）の日別の分布（上限の見直しの材料。見直しの提案はしない）');
  L.push('');
  L.push(`各セルは 平均 / 中央値 / 最小 / 最大（${base.length}シード）。仕入れ額＝仕込み＋市場＋だし（初日セットは含めない）。夜の終わりの現金は基金を積まない場合の値。`);
  L.push('');
  L.push('| 日 | 仕入れ額 | 夜の終わりの現金 |');
  L.push('|---:|---|---|');
  for (let day = 1; day <= 7; day++) {
    const rows7 = base.map(r => r.rows[day - 1]).filter(Boolean);
    const buy = rows7.map(d => (d.spend.prep ?? 0) + (d.spend.market ?? 0) + (d.spend.dashi ?? 0));
    L.push(`| Day${day} | ${day === 1 ? '（Day1は初日セットあり。参考）' + distText(dist(buy)) : distText(dist(buy))} | ${distText(dist(rows7.map(d => d.cash)))} |`);
  }
  L.push('');
}
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
L.push('fund_max_safe は完走しない周を含む。その周の現金・杯数は停止時点（営業した日まで）の値で、基準方針の最終値との差になる（停止までの日数が短い分、杯数の差も大きく出る）。');
L.push('');
L.push('| 方針 | 組 | 現金＋修繕 差の平均（最小〜最大） | 差が0でない組 | 現金 差の平均 | 提供杯数 差の平均 | 未提供 差の平均 | 標準目標を失ったシード | 標準目標を得たシード | いずれかの目標を失ったシード数 |');
L.push('|---|---:|---|---:|---:|---:|---:|---|---|---:|');
for (const p of FUND.filter(x => paired[x])) {
  const q = paired[p];
  L.push(`| ${names[p]} | ${q.pairs} | ${q.cprMean.toFixed(1)}（${q.cprMin}〜${q.cprMax}） | ${q.cprNonZero} | ${q.cashMean.toFixed(1)} | ${q.servedMean.toFixed(2)} | ${q.unservedMean.toFixed(2)} | ${q.standardLost.length ? q.standardLost.join(',') : 'なし'} | ${q.standardGained.length ? q.standardGained.join(',') : 'なし'} | ${q.anyGoalLost.length} |`);
}
L.push('');
L.push('## 到達した段階（最終日までに届いた最高の段階）と、初めて届いた日');
L.push('');
L.push('| 方針 | 届かず | 150（看板） | 300（棚と雨よけ） | 600（名義） | 看板に届いた日 平均（最早） | 棚に届いた日 平均（最早） | 名義に届いた日 平均（最早） |');
L.push('|---|---:|---:|---:|---:|---|---|---|');
const dayText = (r, k) => r.stageDayMean[k] === null ? '—' : `${r.stageDayMean[k].toFixed(1)}（${r.stageDayMin[k]}）`;
for (const r of rows.filter(x => FUND.includes(x.policy))) {
  const c = r.stageCount;
  L.push(`| ${names[r.policy]} | ${c['-1']} | ${c['0']} | ${c['1']} | ${c['2']} | ${dayText(r, '0')} | ${dayText(r, '1')} | ${dayText(r, '2')} |`);
}
L.push('');
L.push('## 日ごとの平均（提供杯数／夜の終わりの現金）');
L.push('');
L.push('その日の行のある周だけの平均。行のある周が全シードに満たない日は（N周）を付ける。ゲームオーバーで営業しなかった日は「—」。');
L.push('');
L.push('| 方針 | ' + Array.from({ length: 7 }, (_, i) => `Day${i + 1}`).join(' | ') + ' |');
L.push('|---|' + Array.from({ length: 7 }, () => '---:').join('|') + '|');
for (const r of rows) L.push(`| ${names[r.policy]} | ${r.servedByDay.map((s, i) => s === null ? '—' : `${s.toFixed(1)} / ${r.cashByDay[i].toFixed(0)}${r.nByDay[i] < r.n ? `（${r.nByDay[i]}周）` : ''}`).join(' | ')} |`);
L.push('');
summary.check3 = check3;
summary.base_day_distribution = Array.from({ length: 7 }, (_, i) => {
  const rows7 = base.map(r => r.rows[i]).filter(Boolean);
  const buy = rows7.map(d => (d.spend.prep ?? 0) + (d.spend.market ?? 0) + (d.spend.dashi ?? 0));
  return { day: i + 1, purchases: dist(buy), night_cash: dist(rows7.map(d => d.cash)) };
});
fs.writeFileSync(new URL('playthrough_summary_fund.json', dir), JSON.stringify(summary, null, 2));
fs.writeFileSync(new URL('PLAYTHROUGH_RESULTS_FUND.md', dir), L.join('\n'));
console.log('wrote playthrough_summary_fund.json / PLAYTHROUGH_RESULTS_FUND.md');
