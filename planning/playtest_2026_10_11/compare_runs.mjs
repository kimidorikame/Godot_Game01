// 調整前→調整後の対比表をMarkdownで出す。使い方: node compare_runs.mjs <前のsummary.json> <後のsummary.json>
import fs from 'node:fs';
const [a, b] = process.argv.slice(2).map(f => JSON.parse(fs.readFileSync(new URL('./' + f, import.meta.url))));
const pct = x => (100 * x).toFixed(1) + '%';
const names = { forecast_good: '予報＋基本GOOD', forecast_favorites: '予報＋既知好物', always_small: '小仕込み固定',
  always_large: '大仕込み固定', cheap_valid: '安い完成料理だけ', bare_broth: '空の椀', forecast_mistakes: 'Day3・5に取り違え',
  favorite_oracle: '初回から好物（上限の目安）', no_split: '団体を分割しない', strength_neglect: '濃さ・鮮度のミス',
  decline_one_group: '毎日1組を断る', decline_once: '3日目に1組だけ断る', two_failures: '品質失敗2件（個人1＋団体1）' };
console.log('| 方針 | 最終現金（前→後） | 現金幅（後） | 1500達成（前→後） | 1600達成（前→後） | ゲームオーバー（前→後） |');
console.log('|---|---:|---|---:|---:|---:|');
for (const p of b.policies) {
  const x = a.policies.find(r => r.policy === p.policy);
  console.log(`| ${names[p.policy] ?? p.policy} | ${x.meanCash.toFixed(0)} → ${p.meanCash.toFixed(0)} | ${p.minCash}〜${p.maxCash}`
    + ` | ${pct(x.target1500)} → ${pct(p.target1500)} | ${pct(x.target1600)} → ${pct(p.target1600)} | ${x.gameOver} → ${p.gameOver} |`);
}
