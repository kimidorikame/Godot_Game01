// 4-3：常連の固定日程の前後（daily65 → regulars）の比較表。使い方:
//   node compare_regulars.mjs <前のresults.json> <後のresults.json> [最大シード(既定=全部)]
import fs from 'node:fs';
const [aN, bN, maxSeedArg] = process.argv.slice(2);
const load = n => JSON.parse(fs.readFileSync(new URL('./' + n, import.meta.url)));
const maxSeed = maxSeedArg ? Number(maxSeedArg) : Infinity;
const names = { forecast_good: '予報＋基本GOOD', forecast_favorites: '予報＋既知好物', always_small: '小仕込み固定',
  always_large: '大仕込み固定', cheap_valid: '安い完成料理だけ', bare_broth: '空の椀', forecast_mistakes: 'Day3・5に取り違え',
  favorite_oracle: '初回から好物（上限の目安）', no_split: '団体を分割しない', strength_neglect: '濃さ・鮮度のミス',
  decline_one_group: '毎日1組を断る', decline_once: '3日目に1組だけ断る', two_failures: '品質失敗2件' };
const stat = (runs) => {
  const n = runs.length, mean = f => runs.reduce((s, r) => s + f(r), 0) / n;
  const sum = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
  const gp = r => r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0);
  return { n, cash: mean(r => r.cash), min: Math.min(...runs.map(r => r.cash)), max: Math.max(...runs.map(r => r.cash)),
    t1500: mean(r => Number(r.cash >= 1500)), t1600: mean(r => Number(r.cash >= 1600)),
    good: mean(r => gp(r) / Math.max(sum(r, 'judged_demand'), 1)), great: mean(r => sum(r, 'regular_great')),
    served: mean(r => sum(r, 'served')), unserved: mean(r => sum(r, 'unserved')),
    early: runs.reduce((s, r) => s + r.rows.filter(d => d.closed_early).length, 0),
    over: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    complete: runs.filter(r => r.completed).length };
};
const a = load(aN), b = load(bN);
const pct = x => (100 * x).toFixed(1) + '%';
console.log('| 方針 | 周 | 最終現金（前→後） | 現金幅（後） | 1500達成（前→後） | GOOD以上率（前→後） | 常連GREAT杯（前→後） | 提供（前→後） | 未提供（前→後） | 早期閉店夜（前→後） |');
console.log('|---|---:|---|---|---:|---:|---:|---:|---:|---:|');
for (const p of b.policies) {
  const ra = a.runs.filter(r => r.policy === p && r.seed <= maxSeed), rb = b.runs.filter(r => r.policy === p && r.seed <= maxSeed);
  if (!ra.length || !rb.length) continue;
  const x = stat(ra), y = stat(rb);
  console.log(`| ${names[p] ?? p} | ${y.n} | ${x.cash.toFixed(0)} → ${y.cash.toFixed(0)} | ${y.min}〜${y.max} | ${pct(x.t1500)} → ${pct(y.t1500)} | ${pct(x.good)} → ${pct(y.good)} | ${x.great.toFixed(1)} → ${y.great.toFixed(1)} | ${x.served.toFixed(1)} → ${y.served.toFixed(1)} | ${x.unserved.toFixed(1)} → ${y.unserved.toFixed(1)} | ${x.early} → ${y.early} |`);
}
