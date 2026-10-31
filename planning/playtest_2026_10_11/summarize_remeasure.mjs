// 再測定（先に直す4件のあと）の集計。到達杯数の補正（reach_true）と運営費の感度。数字と事実だけを出す。
// 使い方: node summarize_remeasure.mjs   （同じフォルダの結果JSONを読み、PLAYTHROUGH_RESULTS_REMEASURE.md を書く）
//   入力：playthrough_results_regulars.json（既定 12/13/14・運営費65）
//         playthrough_results_reach_true.json（reach_true・65）／..._cost80.json／_cost70.json／_cost75.json
//         playthrough_tier_log_default.json（既定の各夜の上限案と選んだ段階。R0の再実行から抜き出したもの）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const load = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const base = load('playthrough_results_regulars.json');
const rt = load('playthrough_results_reach_true.json');
const c80 = load('playthrough_results_reach_true_cost80.json');
const c70 = load('playthrough_results_reach_true_cost70.json');
const c75 = load('playthrough_results_reach_true_cost75.json');
const defLog = load('playthrough_tier_log_default.json').tier_log;
// 目標の基準は計測した当時の値に固定する（データの goals は UI準備J で 1200／1500／70%／4杯 に変わった。過去の表を作り直しても当時と同じ数字が出るように）
const goals = { cash_standard: 1500, cash_challenge: 1600, good_rate: 0.85, regular_great: 8 };

const NAMES = { forecast_good: '予報＋基本GOOD', forecast_favorites: '予報＋既知好物', always_small: '小仕込み固定',
  always_large: '大仕込み固定', cheap_valid: '安い完成料理だけ', bare_broth: '空の椀', forecast_mistakes: 'Day3・5に取り違え',
  favorite_oracle: '初回から好物（上限の目安）', no_split: '団体を分割しない', strength_neglect: '濃さ・鮮度のミス',
  decline_one_group: '毎日1組を断る', decline_once: '3日目に1組だけ断る', two_failures: '品質失敗2件' };
const TIER = { 80: 'small', 110: 'medium', 140: 'large' };
const TIER_JA = { small: '小', medium: '中', large: '大' };
const f0 = x => Math.round(x).toString();
const f1 = x => x.toFixed(1);
const pct = x => (100 * x).toFixed(1) + '%';
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0;
const sd = a => { const m = mean(a); return Math.sqrt(mean(a.map(x => (x - m) ** 2))); };
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const goodPlus = r => r.rows.reduce((s, d) => s + (d.grades.GOOD ?? 0) + (d.grades.GREAT ?? 0), 0);
const prepCost = r => r.rows.reduce((s, d) => s + ((d.spend || {}).prep ?? 0), 0);
const runsOf = (res, p) => res.runs.filter(r => r.policy === p);
const key = r => r.policy + '/' + r.seed;
const out = [];
const w = s => out.push(s);

// ---- 方針ごとの統計 ----
function stat(runs) {
  const tiers = { small: 0, medium: 0, large: 0 };
  for (const r of runs) for (const d of r.rows) { const t = TIER[(d.spend || {}).prep]; if (t) tiers[t]++; }
  const cash = runs.map(r => r.cash);
  const gr = r => r.result_summary?.cash_plus_repair ?? r.cash;
  const judged = r => r.result_summary?.judged_cups ?? sumRows(r, 'judged_demand');
  const gp = r => r.result_summary?.good_plus_cups ?? goodPlus(r);
  return {
    n: runs.length, cash: mean(cash), sd: sd(cash), min: Math.min(...cash), max: Math.max(...cash),
    rep: mean(runs.map(r => r.rep)), served: mean(runs.map(r => sumRows(r, 'served'))),
    unserved: mean(runs.map(r => sumRows(r, 'unserved'))),
    goodRate: mean(runs.map(r => gp(r) / Math.max(judged(r), 1))),
    early: runs.reduce((s, r) => s + r.rows.filter(d => d.closed_early).length, 0),
    spoiled: mean(runs.map(r => sumRows(r, 'spoiled_value'))), prep: mean(runs.map(prepCost)), tiers,
    t1500: mean(runs.map(r => Number(gr(r) >= goals.cash_standard))),
    t1600: mean(runs.map(r => Number(gr(r) >= goals.cash_challenge))),
    tGood: mean(runs.map(r => Number(judged(r) > 0 && gp(r) >= goals.good_rate * judged(r) - 1e-6))),
    tGreat: mean(runs.map(r => Number((r.result_summary?.regular_great ?? sumRows(r, 'regular_great')) >= goals.regular_great))),
    regGreat: mean(runs.map(r => sumRows(r, 'regular_great'))), regGoodPlus: mean(runs.map(r => sumRows(r, 'regular_good_plus'))),
    gameOver: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    completed: runs.filter(r => r.completed).length, stalled: runs.filter(r => r.stalled).length,
  };
}
const policies = base.policies;

w('# 再測定（先に直す4件のあと）：到達杯数の補正と運営費の感度');
w('');
w('> 数字と事実の報告です。運営費をいくつにすべきかは書きません。');
w('');
w('## 0. 条件');
w('');
w(`- 既定 = 到達杯数の表 12/13/14（\`TIER_REACH\`）・運営費65（\`${base.commit.slice(0, 7)}\` の結果 \`playthrough_results_regulars.json\`）。`);
w(`- reach_true = 12/15/18（\`TIER_REACH_TRUE\`。営業中の水足しを含む一晩の総杯数）。コミット \`${rt.commit.slice(0, 7)}\`、運営費${rt.daily_operating_cost}（データのまま: ${!rt.daily_operating_cost_overridden}）。`);
w('- 運営費の変更は、データ（week7.json）を変えず、ハーネスの引数で実行中だけ上書きしています（データを実際に80へ変えた実行と全キー一致を確認済み）。');
w('- シード1〜30。同じ方針・同じシードの周を対にして比べます（乱数は朝ごとにシード＋日で固定）。');
w(`- 目標の定義（\`Result.judge_goals\` と同じ）: 標準 現金＋修繕額≥${goals.cash_standard}／挑戦 ≥${goals.cash_challenge}／料理 GOOD以上率≥${goals.good_rate * 100}%／常連GREAT≥${goals.regular_great}杯。`);
w('');

// ---- R1 ----
w('## 1. R1 到達杯数の補正（既定 12/13/14 → reach_true 12/15/18、運営費65、13方針×30シード）');
w('');
w('### 1.1 方針ごとの結果（既定 → reach_true）');
w('');
w('| 方針 | 周 | 最終現金 平均（既定→reach_true） | 最小〜最大（reach_true） | 評判 | 提供杯 | 未提供杯 | GOOD以上率 | 早期閉店の夜 | 廃棄額 | 仕込み代 |');
w('|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|');
const S = { def: {}, rt: {} };
for (const p of policies) {
  const a = stat(runsOf(base, p)), b = stat(runsOf(rt, p)); S.def[p] = a; S.rt[p] = b;
  w(`| ${NAMES[p]} | ${b.n} | ${f0(a.cash)}→${f0(b.cash)}（${b.cash - a.cash >= 0 ? '+' : ''}${f1(b.cash - a.cash)}） | ${b.min}〜${b.max} | ${f1(a.rep)}→${f1(b.rep)} | ${f1(a.served)}→${f1(b.served)} | ${f1(a.unserved)}→${f1(b.unserved)} | ${pct(a.goodRate)}→${pct(b.goodRate)} | ${a.early}→${b.early} | ${f1(a.spoiled)}→${f1(b.spoiled)} | ${f1(a.prep)}→${f1(b.prep)} |`);
}
w('');
w('### 1.2 仕込み段階の選択回数（全夜の合計。Day1含む。帳簿の仕込み代 80/110/140 から集計）');
w('');
w('| 方針 | 既定 小/中/大 | reach_true 小/中/大 | 仕込み代の合計（1周平均）の差 |');
w('|---|---|---|---:|');
for (const p of policies) {
  const a = S.def[p], b = S.rt[p];
  w(`| ${NAMES[p]} | ${a.tiers.small}/${a.tiers.medium}/${a.tiers.large} | ${b.tiers.small}/${b.tiers.medium}/${b.tiers.large} | ${b.prep - a.prep >= 0 ? '+' : ''}${f1(b.prep - a.prep)} |`);
}
w('');

// 上限案15の夜の選択
const t15 = (log) => {
  const c = { small: 0, medium: 0, large: 0 };
  for (const x of log.filter(x => x.target === 15)) c[x.tier]++;
  return c;
};
w('### 1.3 上限案（公開予報の総杯数の上限）が15杯の夜に選ばれた仕込み段階');
w('');
w('| 範囲 | 既定 小/中/大 | reach_true 小/中/大 | 大→中に切り替わった夜（同じ方針・シード・日で対） |');
w('|---|---|---|---:|');
const idx = log => new Map(log.map(x => [x.policy + '/' + x.seed + '/' + x.day, x]));
const dIdx = idx(defLog), rIdx = idx(rt.tier_log);
function sw(filter) {
  let n = 0, pairs = 0;
  for (const [k, x] of rIdx) {
    if (!filter(x)) continue;
    const y = dIdx.get(k);
    if (!y || x.target !== 15 || y.target !== 15) continue;
    pairs++;
    if (y.tier === 'large' && x.tier === 'medium') n++;
  }
  return { n, pairs };
}
for (const [label, flt] of [['全13方針', () => true], ['予報＋基本GOOD', x => x.policy === 'forecast_good'],
  ['予報＋既知好物', x => x.policy === 'forecast_favorites']]) {
  const a = t15(defLog.filter(flt)), b = t15(rt.tier_log.filter(flt)), s = sw(flt);
  w(`| ${label} | ${a.small}/${a.medium}/${a.large} | ${b.small}/${b.medium}/${b.large} | ${s.n}（上限案15が両方で一致した ${s.pairs} 夜のうち） |`);
}
w('');
w('参考：上限案ごとの夜数（全方針。既定／reach_true）');
w('');
const targets = [...new Set([...defLog, ...rt.tier_log].map(x => x.target))].sort((a, b) => a - b);
w('| 上限案 | ' + targets.join(' | ') + ' |');
w('|---|' + targets.map(() => '---:').join('|') + '|');
w('| 既定の夜数 | ' + targets.map(t => defLog.filter(x => x.target === t).length).join(' | ') + ' |');
w('| reach_trueの夜数 | ' + targets.map(t => rt.tier_log.filter(x => x.target === t).length).join(' | ') + ' |');
w('');

// 段階別の提供杯数
w('### 1.4 reach_true の周で、段階ごとに実際に提供した杯数（夜の分布。全13方針）');
w('');
function servedDist(res, policyFilter) {
  const h = { small: {}, medium: {}, large: {} };
  for (const r of res.runs) {
    if (policyFilter && !policyFilter(r)) continue;
    for (const d of r.rows) { const t = TIER[(d.spend || {}).prep]; if (!t) continue; h[t][d.served] = (h[t][d.served] || 0) + 1; }
  }
  return h;
}
for (const [label, flt] of [['全13方針', null], ['予報＋基本GOOD', r => r.policy === 'forecast_good']]) {
  const h = servedDist(rt, flt);
  w(`- ${label}`);
  for (const t of ['small', 'medium', 'large']) {
    const ks = Object.keys(h[t]).map(Number).sort((a, b) => a - b);
    const nights = ks.reduce((s, k) => s + h[t][k], 0);
    w(`  - ${TIER_JA[t]}仕込み（${nights}夜）：最大${ks.length ? ks.at(-1) : '-'}杯。分布 ` + (ks.map(k => `${k}杯×${h[t][k]}`).join('、') || '（なし）'));
  }
}
w('');
const hDef = servedDist(base, null);
w('- 参考：既定の周（全13方針）');
for (const t of ['small', 'medium', 'large']) {
  const ks = Object.keys(hDef[t]).map(Number).sort((a, b) => a - b);
  const nights = ks.reduce((s, k) => s + hDef[t][k], 0);
  w(`  - ${TIER_JA[t]}仕込み（${nights}夜）：最大${ks.length ? ks.at(-1) : '-'}杯。分布 ` + (ks.map(k => `${k}杯×${hDef[t][k]}`).join('、') || '（なし）'));
}
w('');

// 基本GOOD 対比較
w('### 1.5 予報＋基本GOOD の対比較（同じシード）');
w('');
{
  const a = runsOf(base, 'forecast_good'), b = new Map(runsOf(rt, 'forecast_good').map(r => [r.seed, r]));
  const diffs = a.map(r => b.get(r.seed).cash - r.cash);
  const neg = diffs.filter(d => d < 0).length, zero = diffs.filter(d => d === 0).length, pos = diffs.filter(d => d > 0).length;
  w(`- 最終現金の差（reach_true − 既定）：平均 ${diffs.length ? (mean(diffs) >= 0 ? '+' : '') + f1(mean(diffs)) : '-'}、最小 ${Math.min(...diffs)}、最大 +${Math.max(...diffs)}、シード数 ${diffs.length}（増えた${pos}・同じ${zero}・減った${neg}）。QA の予測は +88、5シードの対比較で +72〜+104。`);
  const sa = S.def.forecast_good, sb = S.rt.forecast_good;
  w(`- 平均最終現金 ${f1(sa.cash)} → ${f1(sb.cash)}、標準偏差 ${f1(sa.sd)} → ${f1(sb.sd)}、1500達成率 ${pct(sa.t1500)} → ${pct(sb.t1500)}、1600達成率 ${pct(sa.t1600)} → ${pct(sb.t1600)}。`);
}
w('');

w('### 1.6 目標の達成率（既定 → reach_true）');
w('');
w('| 方針 | 標準（≥' + goals.cash_standard + '） | 挑戦（≥' + goals.cash_challenge + '） | 料理（GOOD以上率≥' + goals.good_rate * 100 + '%） | 常連GREAT≥' + goals.regular_great + '杯 |');
w('|---|---|---|---|---|');
for (const p of policies) {
  const a = S.def[p], b = S.rt[p];
  w(`| ${NAMES[p]} | ${pct(a.t1500)}→${pct(b.t1500)} | ${pct(a.t1600)}→${pct(b.t1600)} | ${pct(a.tGood)}→${pct(b.tGood)} | ${pct(a.tGreat)}→${pct(b.tGreat)} |`);
}
w('');

// ---- R2 ----
w('## 2. R2 運営費の感度（reach_true、65／70／75／80）');
w('');
w('65と80は13方針×30シード、70と75は予報＋基本GOODと予報＋既知好物の2方針×30シード。');
w('');
const costs = [[65, rt], [70, c70], [75, c75], [80, c80]];
w('### 2.1 予報＋基本GOOD');
w('');
w('| 運営費 | 周 | 平均最終現金 | 標準偏差 | 最小〜最大 | 1500達成率 | 1600達成率 | GOOD以上率 | 早期閉店の夜 | ゲームオーバー |');
w('|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|');
for (const [c, res] of costs) {
  const s = stat(runsOf(res, 'forecast_good'));
  w(`| ${c} | ${s.n} | ${f1(s.cash)} | ${f1(s.sd)} | ${s.min}〜${s.max} | ${pct(s.t1500)} | ${pct(s.t1600)} | ${pct(s.goodRate)} | ${s.early} | ${s.gameOver} |`);
}
w('');
w('### 2.2 予報＋既知好物');
w('');
w('| 運営費 | 周 | 平均最終現金 | 標準偏差 | 最小〜最大 | 1500達成率 | 1600達成率 |');
w('|---:|---:|---:|---:|---|---:|---:|');
for (const [c, res] of costs) {
  const s = stat(runsOf(res, 'forecast_favorites'));
  w(`| ${c} | ${s.n} | ${f1(s.cash)} | ${f1(s.sd)} | ${s.min}〜${s.max} | ${pct(s.t1500)} | ${pct(s.t1600)} |`);
}
w('');

w('### 2.3 DESIGN.md 10.13 の合格ライン（運営費ごと）');
w('');
function judge(res, full) {
  const bs = stat(runsOf(res, 'forecast_good'));
  const r = {};
  r['1'] = { pass: bs.cash >= 1500 && bs.cash <= 1700, detail: `平均${f0(bs.cash)}（${bs.min}〜${bs.max}）` };
  r['1b'] = { pass: bs.t1500 >= 0.85 && bs.t1500 <= 0.95, detail: pct(bs.t1500) };
  if (!full) { r['2'] = r['3'] = r['4'] = null; return r; }
  const over = [];
  for (const p of ['cheap_valid', 'bare_broth']) {
    const x = stat(runsOf(res, p));
    if (x.cash > bs.cash) over.push(`${p}: 現金${f0(x.cash)}>${f0(bs.cash)}`);
    if (x.goodRate > bs.goodRate) over.push(`${p}: GOOD以上率${pct(x.goodRate)}>${pct(bs.goodRate)}`);
    if (x.regGreat > bs.regGreat) over.push(`${p}: 常連GREAT${f1(x.regGreat)}>${f1(bs.regGreat)}`);
    if (x.regGoodPlus > bs.regGoodPlus) over.push(`${p}: 常連GOOD以上${f1(x.regGoodPlus)}>${f1(bs.regGoodPlus)}`);
  }
  r['2'] = { pass: over.length === 0, detail: over.length ? over.join(' / ') : '安い完成料理・空の椀とも、現金・品質・常連実績で基本GOODを上回らない' };
  const tf = stat(runsOf(res, 'two_failures'));
  r['3'] = { pass: tf.completed === tf.n && tf.stalled === 0 && tf.gameOver === 0, detail: `完走${tf.completed}/${tf.n}・停止${tf.stalled}・ゲームオーバー${tf.gameOver}` };
  const sell = policies.filter(p => p !== 'bare_broth');
  const go = sell.reduce((s, p) => s + stat(runsOf(res, p)).gameOver, 0);
  const extreme = stat(runsOf(res, 'decline_one_group')).gameOver;
  const nRuns = sell.reduce((s, p) => s + runsOf(res, p).length, 0);
  r['4'] = { pass: go === 0, noted: go > 0 && go === extreme, detail: `空の椀を除く${nRuns}周でゲームオーバー${go}` + (extreme ? `（うち毎日断る方針${extreme}）` : '') };
  return r;
}
const items = [['1', '基本GOODの平均最終現金が1500〜1700'], ['1b', '基本GOODの1500達成率が85〜95%'],
  ['2', '安い完成料理・空の椀が基本GOODを上回らない'], ['3', '品質失敗2件でも7日継続'], ['4', '資金不足の休業（ゲームオーバー）が0']];
const J = costs.map(([c, res]) => [c, judge(res, c === 65 || c === 80)]);
w('| 項目 | ' + J.map(([c]) => `運営費${c}`).join(' | ') + ' |');
w('|---|' + J.map(() => '---').join('|') + '|');
for (const [id, label] of items) {
  w(`| ${id}：${label} | ` + J.map(([, r]) => {
    const x = r[id];
    if (!x) return '対象外（この組では未実行）';
    return (x.pass ? '合格' : x.noted ? '注記つき合格' : '不合格') + '：' + x.detail;
  }).join(' | ') + ' |');
}
w('');

w('### 2.4 差額を機械的に引く試算（運営費65の reach_true の結果 − 営業日数×差）と実測の差');
w('');
w('同じ方針・同じシードの周を対にして、実測の最終現金と試算を比べます。');
w('');
w('| 運営費 | 方針 | 周 | 試算と実測が一致しなかった周 | 実測−試算 の平均 | 最大の絶対差 |');
w('|---:|---|---:|---:|---:|---:|');
const mism = [];
for (const [c, res] of costs.filter(([c]) => c !== 65)) {
  const ps = c === 80 ? policies : ['forecast_good', 'forecast_favorites'];
  for (const p of ps) {
    const a = new Map(runsOf(rt, p).map(r => [r.seed, r]));
    const ds = [];
    for (const r of runsOf(res, p)) {
      const o = a.get(r.seed);
      const days = o.rows.length;
      ds.push({ seed: r.seed, d: r.cash - (o.cash - days * (c - 65)), same: r.rows.length === o.rows.length });
    }
    const bad = ds.filter(x => x.d !== 0);
    w(`| ${c} | ${NAMES[p]} | ${ds.length} | ${bad.length} | ${f1(mean(ds.map(x => x.d)))} | ${Math.max(...ds.map(x => Math.abs(x.d)))} |`);
    if (bad.length) mism.push(`${c}/${p}: シード ${bad.map(x => x.seed + '(' + x.d + ')').join('、')}`);
  }
}
w('');
if (mism.length) { w('一致しなかった周（運営費/方針: シード(実測−試算)）:'); for (const m of mism) w('- ' + m); w(''); }
else w('すべての周で、試算と実測が一致しました（運営費は自動操作の判断を変えていません）。\n');

w('## 3. 補足（観察された事実）');
w('');
w('### 3.1 運営費80で試算と実測が一致しなかった7周（390周のうち）');
w('');
w('- 該当は 大仕込み固定1周・初回から好物2周・毎日1組を断る4周。いずれも**途中から買った物・提供した杯数が変わっています**（運営費の差額そのものではなく、現金が少ない夜の買い物の結果が変わった）。');
w('- 原因を手で確かめたのは「初回から好物」シード12のDay2です。ハーネスの買い物は「手持ちの現金が商品の値段に足りなくなるまで買う」（`money < price` で打ち切り）ため、Day2の最後の買い物（好物の `meat_ball` 24円）の時点で、運営費65では現金が43円、運営費80では13円（24円に足りない）になり、その1個を買えませんでした。以後の夜の在庫・提供・評判が少しずつずれています。');
w('- 残りの6周も、買い物の額（`market`）か提供杯数が変わった夜から差が出ていますが、個別の原因までは確かめていません。');
w('- つまり、ハーネスの判断は、手持ちの現金が商品の値段に足りなくなるほど苦しい夜にだけ、運営費で変わります。');
w('');
w('### 3.2 「濃さ・鮮度のミス」方針が reach_true で悪化した理由（事実）');
w('');
w('この方針は、毎朝のだしの買い置きをしません（`playthroughs.gd` の買い物で `strength_neglect` は除外）。だしが無いと水足しは濃さの下限（0）で止まります。reach_true では、需要の上限案が15杯の夜に大仕込みではなく中仕込みを選びます。');
w('');
w('| 方針 | 設定 | 仕込み | 夜数 | 需要（杯/夜） | 提供（杯/夜） | 未提供（杯/夜） | 早期閉店の夜 | 水（回/夜） | だし（回/夜） |');
w('|---|---|---|---:|---:|---:|---:|---:|---:|---:|');
for (const p of ['strength_neglect', 'forecast_good']) {
  for (const [lab, res] of [['既定', base], ['reach_true', rt]]) {
    const o = {};
    for (const r of runsOf(res, p)) for (const d of r.rows) {
      const t = TIER[(d.spend || {}).prep]; if (!t) continue;
      o[t] = o[t] || { n: 0, demand: 0, served: 0, unserved: 0, early: 0, water: 0, dashi: 0 };
      const x = o[t]; x.n++; x.demand += d.demand; x.served += d.served; x.unserved += d.unserved; x.early += d.closed_early ? 1 : 0; x.water += d.water; x.dashi += d.dashi;
    }
    for (const t of ['small', 'medium', 'large']) {
      const x = o[t]; if (!x) continue;
      w(`| ${NAMES[p]} | ${lab} | ${TIER_JA[t]} | ${x.n} | ${f1(x.demand / x.n)} | ${f1(x.served / x.n)} | ${f1(x.unserved / x.n)} | ${x.early} | ${f1(x.water / x.n)} | ${f1(x.dashi / x.n)} |`);
    }
  }
}
w('');
w('同じ中仕込みでも、基本GOOD（だしを買い置きする）は需要14.0杯に対し13.7杯を出せていて、未提供は既定の大仕込みの夜と同じ0.3杯です。');
w('');
fs.writeFileSync(new URL('PLAYTHROUGH_RESULTS_REMEASURE.md', dir), out.join('\n') + '\n');
console.log(out.join('\n'));
