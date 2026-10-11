// 3-8 試遊結果の集計とDESIGN.md 10.13の合格ライン判定。
// 使い方: node summarize_playthroughs.mjs [入力JSON名(既定playthrough_results.json)]
import fs from 'node:fs';
import assert from 'node:assert/strict';
const inName = process.argv[2] ?? 'playthrough_results.json';
const result = JSON.parse(fs.readFileSync(new URL('./' + inName, import.meta.url)));
const PRICE = 45;
const mean = (a, f) => a.length ? a.reduce((s, x) => s + f(x), 0) / a.length : 0;
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const rows = [];
let dayChecks = 0;
for (const policy of result.policies) {
  const rs = result.runs.filter(r => r.policy === policy);
  for (const r of rs) for (const d of r.rows) {
    assert.equal(d.served + d.unserved, d.demand, 'demand accounting');
    assert.equal(d.sales, d.served * PRICE, 'sales accounting');
    assert.equal(Object.values(d.grades).reduce((a, b) => a + b, 0), d.served, 'quality accounting');
    assert(d.cash >= 0 && d.soup_left >= 0, 'nonnegative cash and soup');
    dayChecks++;
  }
  const cash = rs.map(r => r.cash).sort((a, b) => a - b);
  const demandJudged = r => sumRows(r, 'judged_demand');
  const goodPlus = r => r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0);
  const incidentCount = (r, t) => r.incidents.filter(i => i.type === t).length;
  rows.push({
    policy, n: rs.length,
    completed: rs.filter(r => r.completed).length, stalled: rs.filter(r => r.stalled).length,
    gameOver: rs.reduce((s, r) => s + incidentCount(r, 'game_over'), 0),
    meanCash: mean(rs, r => r.cash), minCash: cash[0], maxCash: cash.at(-1),
    rep: mean(rs, r => r.rep),
    goodRate: mean(rs, r => goodPlus(r) / Math.max(demandJudged(r), 1)),
    served: mean(rs, r => sumRows(r, 'served')), unserved: mean(rs, r => sumRows(r, 'unserved')),
    regularGreat: mean(rs, r => sumRows(r, 'regular_great')),
    regularGoodPlus: mean(rs, r => sumRows(r, 'regular_good_plus')),
    spoiled: mean(rs, r => sumRows(r, 'spoiled_value')),
    target1500: mean(rs, r => Number(r.cash >= 1500)), target1600: mean(rs, r => Number(r.cash >= 1600)),
    earlyCloseNights: rs.reduce((s, r) => s + r.rows.filter(d => d.closed_early).length, 0),
    forcedClose: rs.reduce((s, r) => s + incidentCount(r, 'forced_close'), 0),
    unsellableDeclined: rs.reduce((s, r) => s + incidentCount(r, 'unsellable_declined')
      + incidentCount(r, 'group_unsellable_declined'), 0),
    declineActions: mean(rs, r => r.actions.decline_unsellable ?? 0),
    clicks: mean(rs, r => r.clicks),
  });
}
const by = Object.fromEntries(rows.map(r => [r.policy, r]));
const base = by.forecast_good;
const checks = [];
const pct = x => (100 * x).toFixed(1) + '%';
if (base) {
  checks.push({ id: '1', item: '基本GOODの平均最終現金が1500〜1700',
    pass: base.meanCash >= 1500 && base.meanCash <= 1700,
    detail: `平均${base.meanCash.toFixed(0)}（${base.minCash}〜${base.maxCash}）` });
  checks.push({ id: '1b', item: '基本GOODの1500達成率が85〜95%',
    pass: base.target1500 >= 0.85 && base.target1500 <= 0.95, detail: pct(base.target1500) });
  for (const p of ['cheap_valid', 'bare_broth']) {
    const x = by[p]; if (!x) continue;
    const over = [];
    if (x.meanCash > base.meanCash) over.push(`現金${x.meanCash.toFixed(0)}>${base.meanCash.toFixed(0)}`);
    if (x.goodRate > base.goodRate) over.push(`GOOD以上率${pct(x.goodRate)}>${pct(base.goodRate)}`);
    if (x.regularGreat > base.regularGreat) over.push(`常連GREAT${x.regularGreat.toFixed(1)}>${base.regularGreat.toFixed(1)}`);
    if (x.regularGoodPlus > base.regularGoodPlus) over.push(`常連GOOD以上${x.regularGoodPlus.toFixed(1)}>${base.regularGoodPlus.toFixed(1)}`);
    checks.push({ id: '2', item: `${p}が現金・品質・常連実績のすべてで基本GOODを上回らない`,
      pass: over.length === 0,
      detail: over.length ? '上回った項目: ' + over.join(' / ')
        : `現金${x.meanCash.toFixed(0)}・GOOD以上率${pct(x.goodRate)}・常連GREAT${x.regularGreat.toFixed(1)}`
          + `（基本GOOD ${base.meanCash.toFixed(0)}・${pct(base.goodRate)}・${base.regularGreat.toFixed(1)}）` });
  }
}
if (by.two_failures) {
  const x = by.two_failures;
  const injected = result.runs.filter(r => r.policy === 'two_failures')
    .filter(r => r.failures.filter(f => f.kind === 'named').length === 1
      && r.failures.filter(f => f.kind === 'mob').length === 1).length;
  checks.push({ id: '3', item: '品質失敗2件（個人1杯＋団体1組）でも7日間の営業を続けられる',
    pass: x.completed === x.n && x.stalled === 0 && x.gameOver === 0,
    detail: `完走${x.completed}/${x.n}・停止${x.stalled}・ゲームオーバー${x.gameOver}`
      + `・失敗2件を注入できた周${injected}/${x.n}・平均現金${x.meanCash.toFixed(0)}` });
}
// 空の椀（bare_broth）は「何も売れないと破産する」ことの確認用で、意図的に売らない方針。
// 資金不足の休業の判定からは外し、別枠（4b）で「売れず破産した」ことを記録する。
const sellable = rows.filter(r => r.policy !== 'bare_broth');
const totalGameOver = sellable.reduce((s, r) => s + r.gameOver, 0);
const totalStalled = rows.reduce((s, r) => s + r.stalled, 0);
const sellableRuns = sellable.reduce((s, r) => s + r.n, 0);
checks.push({ id: '4', item: '資金不足の休業（ゲームオーバー）が0（空の椀を除く）',
  pass: totalGameOver === 0,
  detail: `空の椀を除く${sellableRuns}周でゲームオーバー${totalGameOver}・全周の進行停止${totalStalled}` });
if (by.bare_broth) {
  const x = by.bare_broth, bare = result.runs.filter(r => r.policy === 'bare_broth');
  const sold = bare.reduce((s, r) => s + sumRows(r, 'served'), 0);
  checks.push({ id: '4b', item: '空の椀は売れず、資金が尽きる（売れないことの確認・参考）',
    pass: sold === 0 && x.gameOver === x.n,
    detail: `提供${sold}杯・ゲームオーバー${x.gameOver}/${x.n}周・最終現金${x.minCash}〜${x.maxCash}` });
}
// Day1個別のキャッシュフロー: 600-80(運営費)-210(初日セット)-仕込み-50(水道代)-90(場所代)+売上
const TIER_PRICE = { small: 80, medium: 110, large: 140 };
let d1Ok = 0;
const d1Bad = [];
const d1Runs = result.runs.filter(r => r.day1_cash && r.day1_cash.end !== undefined);
for (const r of d1Runs) {
  const c = r.day1_cash, tp = TIER_PRICE[c.tier] ?? 0, sales = r.rows[0]?.sales ?? 0;
  const exp = { after_wake: 520, after_kit: 310, after_tier: 310 - tp,
    after_market: 310 - tp - 50, end: 310 - tp - 50 - 90 + sales };
  const ok = Object.keys(exp).every(k => c[k] === exp[k]);
  if (ok) d1Ok++; else d1Bad.push({ policy: r.policy, seed: r.seed, got: c, expected: exp });
}
checks.push({ id: 'D1', item: 'Day1のキャッシュフロー（600→520→310→仕込み→水道代→場所代＋売上）が全周で一致',
  pass: d1Bad.length === 0 && d1Runs.length > 0, detail: `${d1Ok}/${d1Runs.length}周が一致` });
const full9 = result.runs.filter(r => r.day1_cash?.tier === 'small' && (r.rows[0]?.served ?? 0) === 9);
const summary = { commit: result.commit, tracked_changes: result.tracked_changes,
  seeds_old: result.seeds_old, seeds_new: result.seeds_new, totalRuns: result.runs.length,
  dayAccountingChecks: dayChecks, policies: rows, checks,
  day1: { ok: d1Ok, total: d1Runs.length, bad: d1Bad.slice(0, 5),
    smallTier9CupsEnd: full9.length ? full9[0].day1_cash.end : null, smallTier9CupsRuns: full9.length } };
fs.writeFileSync(new URL('./' + inName.replace('results', 'summary'), import.meta.url),
  JSON.stringify(summary, null, 2) + '\n');
console.table(rows.map(r => ({ policy: r.policy, runs: r.n, complete: r.completed, stalled: r.stalled,
  gameOver: r.gameOver, cash: Math.round(r.meanCash), min: r.minCash, max: r.maxCash, good: pct(r.goodRate),
  rep: r.rep.toFixed(1), served: r.served.toFixed(1), unserved: r.unserved.toFixed(1),
  regGreat: r.regularGreat.toFixed(1), t1500: pct(r.target1500), early: r.earlyCloseNights,
  unsell: r.unsellableDeclined })));
for (const c of checks) console.log(c.pass ? 'PASS' : 'FAIL', c.id, c.item, '|', c.detail);
console.log('days validated', dayChecks, 'commit', result.commit, 'dirty:', JSON.stringify(result.tracked_changes));
