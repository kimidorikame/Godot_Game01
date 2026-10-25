// 予報を使わない試遊（v3）の集計。数字と事実だけを出す。判断・調整の提案は書かない。
// 使い方: node summarize_v3.mjs   （PLAYTHROUGH_RESULTS_V3.md の表の部分を標準出力へ。要約は手で足す）
// 入力：playthrough_results_regulars_v2.json（予報あり・運営費75・reach_true・13方針×30）
//       playthrough_results_regulars_v3.json（予報なし＝visible・13方針＋下限版2×30）
//       playthrough_results_regulars_v3_improvise.json（参考：visible_improvise）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const load = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const goals = JSON.parse(fs.readFileSync(new URL('../../data/campaigns/week7.json', dir), 'utf8')).goals;
const v2 = load('playthrough_results_regulars_v2.json');
const v3 = load('playthrough_results_regulars_v3.json');
const v3i = load('playthrough_results_regulars_v3_improvise.json');
const NAMES = { forecast_good: '基本GOOD', forecast_favorites: '既知好物', always_small: '小仕込み固定',
  always_large: '大仕込み固定', cheap_valid: '安い完成料理だけ', bare_broth: '空の椀', forecast_mistakes: 'Day3・5に取り違え',
  favorite_oracle: '初回から好物（oracle）', no_split: '団体を分割しない', strength_neglect: '濃さ・鮮度のミス',
  decline_one_group: '毎日1組を断る', decline_once: '3日目に1組だけ断る', two_failures: '品質失敗2件',
  forecast_good_lower: '基本GOOD・下限版（前日の注文杯数だけ）', favorite_oracle_lower: '初回から好物・下限版' };
const BASE13 = ['forecast_good', 'forecast_favorites', 'always_small', 'always_large', 'cheap_valid', 'bare_broth', 'forecast_mistakes',
  'favorite_oracle', 'no_split', 'strength_neglect', 'decline_one_group', 'two_failures', 'decline_once'];
const f0 = x => Math.round(x).toString();
const f1 = x => x.toFixed(1);
const pct = x => (100 * x).toFixed(1) + '%';
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0;
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const goodPlus = r => r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0);
const runsOf = (res, p) => res.runs.filter(r => r.policy === p);
const out = [];
const w = s => out.push(s);

function stat(res, p) {
  const runs = runsOf(res, p);
  const judged = r => r.result_summary?.judged_cups ?? sumRows(r, 'judged_demand');
  const gp = r => r.result_summary?.good_plus_cups ?? goodPlus(r);
  const total = r => r.result_summary?.cash_plus_repair ?? r.cash;
  const cash = runs.map(r => r.cash);
  const ul = (res.unserved_log || []).filter(u => u.policy === p);
  const us = k => ul.reduce((s, u) => s + (u[k] ?? 0), 0) / Math.max(runs.length, 1);
  return {
    n: runs.length, cash: mean(cash), min: Math.min(...cash), max: Math.max(...cash),
    goodRate: mean(runs.map(r => gp(r) / Math.max(judged(r), 1))),
    t1500: mean(runs.map(r => Number(total(r) >= goals.cash_standard))), t1600: mean(runs.map(r => Number(total(r) >= goals.cash_challenge))),
    regGreat: mean(runs.map(r => sumRows(r, 'regular_great'))), regGoodPlus: mean(runs.map(r => sumRows(r, 'regular_good_plus'))),
    water: mean(runs.map(r => sumRows(r, 'water'))), dashi: mean(runs.map(r => sumRows(r, 'dashi'))),
    early: runs.reduce((s, r) => s + r.rows.filter(d => d.closed_early).length, 0),
    unserved: mean(runs.map(r => sumRows(r, 'unserved'))), served: mean(runs.map(r => sumRows(r, 'served'))),
    uIng: us('ingredients'), uPot: us('pot'), uDecl: us('declined'), uNot: us('not_arrived'),
    gameOver: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    completed: runs.filter(r => r.completed).length, stalled: runs.filter(r => r.stalled).length,
  };
}

function judge(res, label) {
  const S = {};
  for (const p of BASE13) S[p] = stat(res, p);
  const bs = S.forecast_good;
  const J = {};
  J['1'] = { pass: bs.cash >= 1500 && bs.cash <= 1700, detail: `平均${f0(bs.cash)}（${bs.min}〜${bs.max}）` };
  J['1b'] = { pass: bs.t1500 >= 0.85 && bs.t1500 <= 0.95, detail: `${pct(bs.t1500)}（${Math.round(bs.t1500 * bs.n)}/${bs.n}）` };
  const over = [];
  for (const p of ['cheap_valid', 'bare_broth']) {
    const x = S[p];
    if (x.cash > bs.cash) over.push(`${p}: 現金${f0(x.cash)}>${f0(bs.cash)}`);
    if (x.goodRate > bs.goodRate) over.push(`${p}: GOOD以上率${pct(x.goodRate)}>${pct(bs.goodRate)}`);
    if (x.regGreat > bs.regGreat) over.push(`${p}: 常連GREAT${f1(x.regGreat)}>${f1(bs.regGreat)}`);
    if (x.regGoodPlus > bs.regGoodPlus) over.push(`${p}: 常連GOOD以上${f1(x.regGoodPlus)}>${f1(bs.regGoodPlus)}`);
  }
  J['2'] = { pass: over.length === 0, detail: over.length ? over.join(' / ')
    : `安い完成料理（現金${f0(S.cheap_valid.cash)}・GOOD以上率${pct(S.cheap_valid.goodRate)}）・空の椀（現金${f0(S.bare_broth.cash)}）とも、現金・品質・常連実績で基本GOOD（現金${f0(bs.cash)}・${pct(bs.goodRate)}・常連GREAT${f1(bs.regGreat)}）を上回らない` };
  const tf = S.two_failures;
  J['3'] = { pass: tf.completed === tf.n && tf.stalled === 0 && tf.gameOver === 0, detail: `完走${tf.completed}/${tf.n}・停止${tf.stalled}・ゲームオーバー${tf.gameOver}・平均現金${f0(tf.cash)}` };
  const sell = BASE13.filter(p => p !== 'bare_broth');
  const go = sell.reduce((s, p) => s + S[p].gameOver, 0), nRuns = sell.reduce((s, p) => s + S[p].n, 0);
  const extreme = S.decline_one_group.gameOver;
  J['4'] = { pass: go === 0, noted: go > 0 && go === extreme, detail: `空の椀を除く${nRuns}周でゲームオーバー${go}` + (extreme ? `（うち毎日断る方針${extreme}）` : '') };
  const DAILY = res.daily_operating_cost, TIER_PRICE = { small: 80, medium: 110, large: 140 };
  let d1Ok = 0, d1Total = 0;
  const base = res.runs.filter(r => BASE13.includes(r.policy));
  for (const r of base.filter(r => r.day1_cash && r.day1_cash.end !== undefined)) {
    const c = r.day1_cash, tp = TIER_PRICE[c.tier] ?? 0, sales = r.rows[0]?.sales ?? 0;
    const wake = 600 - DAILY, kit = wake - 210;
    const exp = { after_wake: wake, after_kit: kit, after_tier: kit - tp, after_market: kit - tp - 50, end: kit - tp - 50 - 90 + sales };
    d1Total++;
    if (Object.keys(exp).every(k => c[k] === exp[k])) d1Ok++;
  }
  J['D1'] = { pass: d1Ok === d1Total && d1Total > 0, detail: `${d1Ok}/${d1Total}周が一致` };
  const items = [['1', '基本GOODの平均最終現金が1500〜1700'], ['1b', '基本GOODの1500達成率が85〜95%'],
    ['2', '安い完成料理・空の椀が基本GOODを上回らない'], ['3', '品質失敗2件でも7日継続'], ['4', '資金不足の休業（ゲームオーバー）が0（空の椀を除く）'],
    ['D1', 'Day1のキャッシュフローが全周で式と一致']];
  w(`| 項目（${label}） | 判定 | 内容 |`);
  w('|---|---|---|');
  for (const [id, text] of items) {
    const x = J[id];
    w(`| ${id}：${text} | ${x.pass ? '合格' : x.noted ? '注記つき合格' : '不合格'} | ${x.detail} |`);
  }
  w('');
}

function table(res, policies, title) {
  w(title);
  w('');
  w('| 方針 | 周 | 最終現金 平均 | 最小〜最大 | 1500達成 | 1600達成 | GOOD以上率 | 水（1周あたり） | だし（1周あたり） | 早期閉店の夜 | 未提供杯（1周あたり） | 未提供の内訳（素材／鍋／断った／来られなかった） | ゲームオーバー |');
  w('|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---|---:|');
  for (const p of policies) {
    const s = stat(res, p);
    if (!s.n) continue;
    w(`| ${NAMES[p]} | ${s.n} | ${f0(s.cash)} | ${s.min}〜${s.max} | ${pct(s.t1500)} | ${pct(s.t1600)} | ${pct(s.goodRate)} | ${f1(s.water)} | ${f1(s.dashi)} | ${s.early} | ${f1(s.unserved)} | ${f1(s.uIng)}／${f1(s.uPot)}／${f1(s.uDecl)}／${f1(s.uNot)} | ${s.gameOver} |`);
  }
  w('');
}

function compare(a, b, policies, labelA, labelB) {
  w(`| 方針 | 平均最終現金（${labelA}→${labelB}） | GOOD以上率 | 水（1周あたり） | だし（1周あたり） | 早期閉店の夜 | 未提供杯（1周あたり） |`);
  w('|---|---|---|---|---|---|---|');
  for (const p of policies) {
    const x = stat(a, p), y = stat(b, p);
    if (!x.n || !y.n) continue;
    w(`| ${NAMES[p]} | ${f0(x.cash)}→${f0(y.cash)}（${y.cash - x.cash >= 0 ? '+' : ''}${f0(y.cash - x.cash)}） | ${pct(x.goodRate)}→${pct(y.goodRate)} | ${f1(x.water)}→${f1(y.water)} | ${f1(x.dashi)}→${f1(y.dashi)} | ${x.early}→${y.early} | ${f1(x.unserved)}→${f1(y.unserved)} |`);
  }
  w('');
}

w(`> **v3 は「言葉と数の対応を覚えた熟練プレイヤー」相当の条件での結果です。**（客足の言葉の帯の中心を数として覚えていて、前日の注文杯数・DMの匂わせ・自分が受けた注文だけで仕込みと仕入れを決める。予報は読まない。）`);
w('');
w('## 0. 条件');
w('');
w(`- v2：\`playthrough_results_regulars_v2.json\`（予報あり。コミット \`${v2.commit.slice(0, 7)}\`、運営費${v2.daily_operating_cost}、reach: ${v2.reach}、info: ${v2.info_mode ?? 'forecast'}）。`);
w(`- v3：\`playthrough_results_regulars_v3.json\`（予報なし。コミット \`${v3.commit.slice(0, 7)}\`、運営費${v3.daily_operating_cost}、reach: ${v3.reach}、info: ${v3.info_mode}）。13方針＋下限版2方針、各30シード。`);
w(`- 参考：\`playthrough_results_regulars_v3_improvise.json\`（info: ${v3i.info_mode}。v3に加えて、注文のタグの素材が手元に無いとき、足りない軸〔味・具〕をほかの在庫で補って椀を成立させる）。v3の既定には含めません。`);
w('- 目標: 標準 現金＋修繕額≥' + goals.cash_standard + '／挑戦 ≥' + goals.cash_challenge + '／料理 GOOD以上率≥' + goals.good_rate * 100 + '%。');
w('');
w('## 1. v3（予報なし）13方針×30シード');
w('');
table(v3, BASE13, '### 1.1 方針ごとの結果');
w('### 1.2 10.13の判定（v3）');
w('');
judge(v3, 'v3');
w('## 2. v2（予報あり）との比較（方針ごと）');
w('');
compare(v2, v3, BASE13, 'v2', 'v3');
w('## 3. 下限版（見込み＝前日の注文杯数だけ）との比較');
w('');
w('| 方針 | v2（予報） | v3（言葉と数＋DM） | 下限版（前日の注文杯数だけ） |');
w('|---|---|---|---|');
for (const [p, low] of [['forecast_good', 'forecast_good_lower'], ['favorite_oracle', 'favorite_oracle_lower']]) {
  const a = stat(v2, p), b = stat(v3, p), c = stat(v3, low);
  const cell = s => `現金${f0(s.cash)}（${s.min}〜${s.max}）・1500達成${pct(s.t1500)}・GOOD以上率${pct(s.goodRate)}・未提供${f1(s.unserved)}杯`;
  w(`| ${NAMES[p]} | ${cell(a)} | ${cell(b)} | ${cell(c)} |`);
}
w('');
w('## 4. 参考：visible_improvise（注文のタグの素材が無いとき、ほかの在庫で補う）');
w('');
table(v3i, [...BASE13, 'forecast_good_lower', 'favorite_oracle_lower'], '### 4.1 方針ごとの結果');
w('### 4.2 10.13の判定（visible_improvise）');
w('');
judge(v3i, 'improvise');
w('### 4.3 v2との比較（方針ごと）');
w('');
compare(v2, v3i, BASE13, 'v2', 'improvise');
console.log(out.join('\n'));
