// 運営費75の確定に向けた集計（A：75の13方針の揃え・10.13判定、B：「濃さ・鮮度のミス」の切り分け）。数字と事実だけを出す。
// 使い方: node summarize_cost75.mjs   （PLAYTHROUGH_RESULTS_COST75.md を書く）
// 入力：playthrough_results_reach_true.json（reach_true・65）／_cost75.json（75・2方針）／_cost75_rest.json（75・残り11方針）
//       playthrough_results_isolation_neglect_{default,reach_true}.json（strength_neglect・65）
//       playthrough_results_isolation_neglect_dashi_{default,reach_true}.json（strength_neglect_dashi・65）
//       playthrough_results_regulars.json／playthrough_tier_log_default.json（既定・65）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const load = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
// 目標の基準は計測した当時の値に固定する（データの goals は UI準備J で 1200／1500／70%／4杯 に変わった。過去の表を作り直しても当時と同じ数字が出るように）
const goals = { cash_standard: 1500, cash_challenge: 1600, good_rate: 0.85, regular_great: 8 };
const rt65 = load('playthrough_results_reach_true.json');
const c75a = load('playthrough_results_reach_true_cost75.json');
const c75b = load('playthrough_results_reach_true_cost75_rest.json');
const base = load('playthrough_results_regulars.json');
const defLog = load('playthrough_tier_log_default.json').tier_log;
const nd = load('playthrough_results_isolation_neglect_default.json');
const nr = load('playthrough_results_isolation_neglect_reach_true.json');
const dd = load('playthrough_results_isolation_neglect_dashi_default.json');
const dr = load('playthrough_results_isolation_neglect_dashi_reach_true.json');
const all75 = { policies: [...c75a.policies, ...c75b.policies], runs: [...c75a.runs, ...c75b.runs],
  daily_operating_cost: c75b.daily_operating_cost, commit: c75b.commit };
const policies = rt65.policies;

const NAMES = { forecast_good: '予報＋基本GOOD', forecast_favorites: '予報＋既知好物', always_small: '小仕込み固定',
  always_large: '大仕込み固定', cheap_valid: '安い完成料理だけ', bare_broth: '空の椀', forecast_mistakes: 'Day3・5に取り違え',
  favorite_oracle: '初回から好物（上限の目安）', no_split: '団体を分割しない', strength_neglect: '濃さ・鮮度のミス',
  strength_neglect_dashi: '濃さ・鮮度のミス（だしの買い置きあり）',
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
const runsOf = (res, p) => res.runs.filter(r => r.policy === p);
const out = [];
const w = s => out.push(s);

function stat(runs) {
  const cash = runs.map(r => r.cash);
  const judged = r => r.result_summary?.judged_cups ?? sumRows(r, 'judged_demand');
  const gp = r => r.result_summary?.good_plus_cups ?? goodPlus(r);
  const total = r => r.result_summary?.cash_plus_repair ?? r.cash;
  const tiers = { small: 0, medium: 0, large: 0 };
  for (const r of runs) for (const d of r.rows) { const t = TIER[(d.spend || {}).prep]; if (t) tiers[t]++; }
  return {
    n: runs.length, cash: mean(cash), sd: sd(cash), min: Math.min(...cash), max: Math.max(...cash),
    rep: mean(runs.map(r => r.rep)), served: mean(runs.map(r => sumRows(r, 'served'))),
    unserved: mean(runs.map(r => sumRows(r, 'unserved'))),
    goodRate: mean(runs.map(r => gp(r) / Math.max(judged(r), 1))),
    t1500: mean(runs.map(r => Number(total(r) >= goals.cash_standard))),
    t1600: mean(runs.map(r => Number(total(r) >= goals.cash_challenge))),
    regGreat: mean(runs.map(r => sumRows(r, 'regular_great'))), regGoodPlus: mean(runs.map(r => sumRows(r, 'regular_good_plus'))),
    early: runs.reduce((s, r) => s + r.rows.filter(d => d.closed_early).length, 0),
    spoiled: mean(runs.map(r => sumRows(r, 'spoiled_value'))), tiers,
    gameOver: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    completed: runs.filter(r => r.completed).length, stalled: runs.filter(r => r.stalled).length,
    cashes: cash,
  };
}

w('# 運営費75の確定に向けた実測（A：75の13方針、B：「濃さ・鮮度のミス」の切り分け）');
w('');
w('> 数字と事実の報告です。**75は暫定値**で、フェーズ5の最初の人の試遊のあとに見直します。運営費をいくつにすべきか、予報をどう直すべきかは書きません。');
w('');
w('## 0. 条件');
w('');
w(`- 到達杯数の表は reach_true（小12／中15／大18）。シード1〜30。運営費はデータ（week7.json）を変えず、ハーネスの引数で実行中だけ上書きしています。`);
w(`- A：運営費${all75.daily_operating_cost}。既存の2方針（予報＋基本GOOD・予報＋既知好物。\`playthrough_results_reach_true_cost75.json\`）と、残り11方針（\`..._cost75_rest.json\`、コミット \`${c75b.commit.slice(0, 7)}\`）で13方針が揃います。`);
w('- B：運営費65・同じ条件（再測定と同じ）。比較は同じ方針・同じシードの対で行います。');
w(`- 目標: 標準 現金＋修繕額≥${goals.cash_standard}／挑戦 ≥${goals.cash_challenge}／料理 GOOD以上率≥${goals.good_rate * 100}%／常連GREAT≥${goals.regular_great}杯。`);
w('');

// ================= A =================
w('## 1. A 運営費75・reach_true の13方針×30シード');
w('');
w('| 方針 | 周 | 最終現金 平均 | 最小〜最大 | 評判 | 提供杯 | 未提供杯 | GOOD以上率 | 1500達成 | 1600達成 | ゲームオーバー | 早期閉店の夜 | 完走 |');
w('|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
const S75 = {};
for (const p of policies) {
  const s = stat(runsOf(all75, p)); S75[p] = s;
  w(`| ${NAMES[p]} | ${s.n} | ${f0(s.cash)} | ${s.min}〜${s.max} | ${f1(s.rep)} | ${f1(s.served)} | ${f1(s.unserved)} | ${pct(s.goodRate)} | ${pct(s.t1500)} | ${pct(s.t1600)} | ${s.gameOver} | ${s.early} | ${s.completed}/${s.n} |`);
}
w('');
w('資金不足の休業（ゲームオーバー）は、空の椀を除く方針の合計で ' + policies.filter(p => p !== 'bare_broth').reduce((s, p) => s + S75[p].gameOver, 0) + ' 件です。');
w('');

w('### 1.1 DESIGN.md 10.13 の合格ライン（運営費75）');
w('');
const bs = S75.forecast_good;
const J = {};
J['1'] = { pass: bs.cash >= 1500 && bs.cash <= 1700, detail: `平均${f0(bs.cash)}（${bs.min}〜${bs.max}）` };
J['1b'] = { pass: bs.t1500 >= 0.85 && bs.t1500 <= 0.95, detail: `${pct(bs.t1500)}（${Math.round(bs.t1500 * bs.n)}/${bs.n}）` };
const over = [];
for (const p of ['cheap_valid', 'bare_broth']) {
  const x = S75[p];
  if (x.cash > bs.cash) over.push(`${p}: 現金${f0(x.cash)}>${f0(bs.cash)}`);
  if (x.goodRate > bs.goodRate) over.push(`${p}: GOOD以上率${pct(x.goodRate)}>${pct(bs.goodRate)}`);
  if (x.regGreat > bs.regGreat) over.push(`${p}: 常連GREAT${f1(x.regGreat)}>${f1(bs.regGreat)}`);
  if (x.regGoodPlus > bs.regGoodPlus) over.push(`${p}: 常連GOOD以上${f1(x.regGoodPlus)}>${f1(bs.regGoodPlus)}`);
}
J['2'] = { pass: over.length === 0, detail: over.length ? over.join(' / ')
  : `安い完成料理（現金${f0(S75.cheap_valid.cash)}・GOOD以上率${pct(S75.cheap_valid.goodRate)}）・空の椀（現金${f0(S75.bare_broth.cash)}）とも、現金・品質・常連実績で基本GOOD（現金${f0(bs.cash)}・${pct(bs.goodRate)}・常連GREAT${f1(bs.regGreat)}）を上回らない` };
const tf = S75.two_failures;
J['3'] = { pass: tf.completed === tf.n && tf.stalled === 0 && tf.gameOver === 0, detail: `完走${tf.completed}/${tf.n}・停止${tf.stalled}・ゲームオーバー${tf.gameOver}・平均現金${f0(tf.cash)}` };
const sell = policies.filter(p => p !== 'bare_broth');
const go = sell.reduce((s, p) => s + S75[p].gameOver, 0), nRuns = sell.reduce((s, p) => s + S75[p].n, 0);
const extreme = S75.decline_one_group.gameOver;
J['4'] = { pass: go === 0, noted: go > 0 && go === extreme, detail: `空の椀を除く${nRuns}周でゲームオーバー${go}` + (extreme ? `（うち毎日断る方針${extreme}）` : '') };
// D1：Day1のキャッシュフロー（全周）。式は summarize_playthroughs.mjs と同じ。
const DAILY = all75.daily_operating_cost, TIER_PRICE = { small: 80, medium: 110, large: 140 };
let d1Ok = 0, d1Total = 0; const d1Bad = [];
for (const r of all75.runs.filter(r => r.day1_cash && r.day1_cash.end !== undefined)) {
  const c = r.day1_cash, tp = TIER_PRICE[c.tier] ?? 0, sales = r.rows[0]?.sales ?? 0;
  const wake = 600 - DAILY, kit = wake - 210;
  const exp = { after_wake: wake, after_kit: kit, after_tier: kit - tp, after_market: kit - tp - 50, end: kit - tp - 50 - 90 + sales };
  d1Total++;
  if (Object.keys(exp).every(k => c[k] === exp[k])) d1Ok++; else d1Bad.push(r.policy + '/' + r.seed);
}
J['D1'] = { pass: d1Bad.length === 0 && d1Total > 0, detail: `${d1Ok}/${d1Total}周が一致（600→${600 - DAILY}→${600 - DAILY - 210}→仕込み→水道代→場所代＋売上。小仕込み＋9杯完売の閉店時現金は${600 - DAILY - 210 - 80 - 50 - 90 + 405}）` };
const items = [['1', '基本GOODの平均最終現金が1500〜1700'], ['1b', '基本GOODの1500達成率が85〜95%'],
  ['2', '安い完成料理・空の椀が基本GOODを上回らない'], ['3', '品質失敗2件でも7日継続'], ['4', '資金不足の休業（ゲームオーバー）が0（空の椀を除く）'],
  ['D1', 'Day1のキャッシュフローが全周で式と一致']];
w('| 項目 | 判定 | 内容 |');
w('|---|---|---|');
for (const [id, label] of items) {
  const x = J[id];
  w(`| ${id}：${label} | ${x.pass ? '合格' : x.noted ? '注記つき合格' : '不合格'} | ${x.detail} |`);
}
w('');
w('### 1.2 運営費65（reach_true）の結果から「7日×10」を引く試算と、75の実測の差');
w('');
w('同じ方針・同じシードの周を対にして、実測の最終現金を、65の結果−営業日数×10と比べます。');
w('');
w('| 方針 | 周 | 一致しなかった周 | 実測−試算 の平均 | 最大の絶対差 |');
w('|---|---:|---:|---:|---:|');
const mism = [];
for (const p of policies) {
  const a = new Map(runsOf(rt65, p).map(r => [r.seed, r]));
  const ds = runsOf(all75, p).map(r => { const o = a.get(r.seed); return { seed: r.seed, d: r.cash - (o.cash - o.rows.length * 10) }; });
  const bad = ds.filter(x => x.d !== 0);
  w(`| ${NAMES[p]} | ${ds.length} | ${bad.length} | ${f1(mean(ds.map(x => x.d)))} | ${Math.max(...ds.map(x => Math.abs(x.d)))} |`);
  if (bad.length) mism.push(`${NAMES[p]}（シード ${bad.map(x => x.seed + ':' + x.d).join('、')}）`);
}
w('');
w(mism.length ? '一致しなかった周: ' + mism.join('／') : 'すべての周で、試算と実測が一致しました。');
w('');

// ================= B =================
w('## 2. B 「濃さ・鮮度のミス」の切り分け（運営費65・reach_true／既定）');
w('');
w('### 2.1 B1 だしの買い置きだけを基準方針と同じにした版（strength_neglect_dashi）');
w('');
w('| 方針 | 到達杯数の表 | 周 | 最終現金 平均 | 最小〜最大 | 評判 | 提供杯 | 未提供杯 | GOOD以上率 | 1500達成 | 1600達成 | 早期閉店の夜 | 小/中/大 |');
w('|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---|');
const rows21 = [['strength_neglect', '既定12/13/14', runsOf(nd, 'strength_neglect')], ['strength_neglect', 'reach_true', runsOf(nr, 'strength_neglect')],
  ['strength_neglect_dashi', '既定12/13/14', runsOf(dd, 'strength_neglect_dashi')], ['strength_neglect_dashi', 'reach_true', runsOf(dr, 'strength_neglect_dashi')],
  ['forecast_good', '既定12/13/14', runsOf(base, 'forecast_good')], ['forecast_good', 'reach_true', runsOf(rt65, 'forecast_good')]];
const ST = {};
for (const [p, lab, runs] of rows21) {
  const s = stat(runs); ST[p + '/' + lab] = s;
  w(`| ${NAMES[p]} | ${lab} | ${s.n} | ${f0(s.cash)} | ${s.min}〜${s.max} | ${f1(s.rep)} | ${f1(s.served)} | ${f1(s.unserved)} | ${pct(s.goodRate)} | ${pct(s.t1500)} | ${pct(s.t1600)} | ${s.early} | ${s.tiers.small}/${s.tiers.medium}/${s.tiers.large} |`);
}
w('');
{
  const d = (a, b) => { const x = ST[a], y = ST[b]; return `${f1(y.cash - x.cash)}`; };
  w(`- 同じ方針内の差（reach_true − 既定）：strength_neglect ${d('strength_neglect/既定12/13/14', 'strength_neglect/reach_true')}円、strength_neglect_dashi ${d('strength_neglect_dashi/既定12/13/14', 'strength_neglect_dashi/reach_true')}円、forecast_good ${d('forecast_good/既定12/13/14', 'forecast_good/reach_true')}円。`);
  const pairedDiff = (A, B) => { const m = new Map(A.map(r => [r.seed, r])); return mean(B.map(r => r.cash - m.get(r.seed).cash)); };
  w(`- 同じシードの対（reach_true − 既定）の平均：strength_neglect ${f1(pairedDiff(runsOf(nd, 'strength_neglect'), runsOf(nr, 'strength_neglect')))}円、strength_neglect_dashi ${f1(pairedDiff(runsOf(dd, 'strength_neglect_dashi'), runsOf(dr, 'strength_neglect_dashi')))}円。`);
  const x = ST['strength_neglect/reach_true'], y = ST['strength_neglect_dashi/reach_true'];
  w(`- reach_true の strength_neglect_dashi と strength_neglect の差（だしの買い置きだけの差）：現金 ${f1(y.cash - x.cash)}円、未提供杯 ${f1(y.unserved - x.unserved)}杯、早期閉店の夜 ${y.early - x.early}。`);
}
w('');

// B2
w('### 2.2 B2 「濃さ・鮮度のミス」で、既定では大仕込みだった夜が reach_true で中仕込みに変わった夜');
w('');
w('既定と reach_true の各夜の記録（上限案と選んだ段階）を、同じシード・同じ日で対にしました。抜き出す条件は、上限案が15で、既定が大・reach_true が中の夜です。');
w('各周の最初の切り替え夜より前は両者の軌道が同じです。**最初の切り替え夜（主）**と、**2回目以降（参考。前の夜の結果の違いで在庫・評判・現金が変わっている）**に分けます。');
w('');
const nrLog = nr.tier_log.filter(x => x.policy === 'strength_neglect');
const ndLog = nd.tier_log.filter(x => x.policy === 'strength_neglect');
const idx = log => new Map(log.map(x => [x.seed + '/' + x.day, x]));
const nrI = idx(nrLog), ndI = idx(ndLog);
const rowOf = (res, seed, day) => runsOf(res, 'strength_neglect').find(r => r.seed === seed)?.rows.find(d => d.day === day);
const stopsBy = (res, seed, day) => (res.water_stop_log || []).filter(x => x.policy === 'strength_neglect' && x.seed === seed && x.day === day).map(x => x.reason);
const switched = [];
for (const [k, x] of nrI) {
  const y = ndI.get(k);
  if (y && x.target === 15 && y.target === 15 && y.tier === 'large' && x.tier === 'medium') switched.push({ seed: x.seed, day: x.day });
}
const firstOf = new Map();
for (const s of switched.sort((a, b) => a.seed - b.seed || a.day - b.day)) if (!firstOf.has(s.seed)) firstOf.set(s.seed, s.day);
const agg = (list, getRes) => {
  const o = { n: 0, demand: 0, served: 0, unserved: 0, early: 0, water: 0, dashi: 0, left: 0, strength0: 0 };
  const reasons = {};
  for (const { seed, day } of list) {
    const d = rowOf(getRes, seed, day); if (!d) continue;
    o.n++; o.demand += d.demand; o.served += d.served; o.unserved += d.unserved; o.early += d.closed_early ? 1 : 0;
    o.water += d.water; o.dashi += d.dashi; o.left += d.soup_left;
    for (const r of new Set(stopsBy(getRes, seed, day))) reasons[r] = (reasons[r] || 0) + 1;
  }
  return { o, reasons };
};
const fmtReasons = r => Object.keys(r).length ? Object.entries(r).map(([k, v]) => `${k}×${v}`).join('、') : 'なし';
const firsts = switched.filter(x => firstOf.get(x.seed) === x.day), laters = switched.filter(x => firstOf.get(x.seed) !== x.day);
w('| 区分 | 設定 | 夜数 | 需要 | 提供 | 未提供 | 早期閉店の夜 | 水（回） | だし（回） | 夜の終わりの鍋の残り | 鍋を直せなかった理由（夜数） |');
w('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|');
for (const [lab, list] of [['最初の切り替え夜（主）', firsts], ['2回目以降（参考）', laters]]) {
  for (const [sl, res] of [['既定（大）', nd], ['reach_true（中）', nr]]) {
    const { o, reasons } = agg(list, res);
    const m = x => o.n ? f1(x / o.n) : '-';
    w(`| ${lab} | ${sl} | ${o.n} | ${m(o.demand)} | ${m(o.served)} | ${m(o.unserved)} | ${o.early} | ${m(o.water)} | ${m(o.dashi)} | ${m(o.left)} | ${fmtReasons(reasons)} |`);
  }
}
w('');
w(`- 切り替わった夜の数：最初 ${firsts.length}（${new Set(firsts.map(x => x.seed)).size}シード）、2回目以降 ${laters.length}。`);
{
  // reach_true の strength_neglect 全体の water_stop_log の内訳（全夜）と、中仕込みの夜に限った内訳
  const all = nr.water_stop_log.filter(x => x.policy === 'strength_neglect');
  const cnt = {}; for (const x of all) cnt[x.reason] = (cnt[x.reason] || 0) + 1;
  w(`- reach_true の strength_neglect 全体で記録した「鍋を直せなかった」回数の内訳: ${Object.entries(cnt).map(([k, v]) => `${k}×${v}`).join('、') || 'なし'}（reason: doses＝水の回数切れ／remaining＝残量条件／strength_floor＝濃さの下限／no_dashi＝濃さが低いのにだしを足せない）。`);
  const med = [];
  for (const r of runsOf(nr, 'strength_neglect')) for (const d of r.rows) if (TIER[(d.spend || {}).prep] === 'medium') med.push({ seed: r.seed, day: d.day });
  const c2 = {}; for (const m of med) for (const rs of new Set(stopsBy(nr, m.seed, m.day))) c2[rs] = (c2[rs] || 0) + 1;
  w(`- reach_true の中仕込みの夜（${med.length}夜）に限ると、鍋を直せなかった理由（夜数）: ${fmtReasons(c2)}。`);
  const sm = [];
  for (const r of runsOf(nr, 'strength_neglect')) for (const d of r.rows) if (TIER[(d.spend || {}).prep] === 'small') sm.push({ seed: r.seed, day: d.day });
  const c3 = {}; for (const m of sm) for (const rs of new Set(stopsBy(nr, m.seed, m.day))) c3[rs] = (c3[rs] || 0) + 1;
  w(`- 参考：小仕込みの夜（${sm.length}夜）では: ${fmtReasons(c3)}。`);
}
w('');
fs.writeFileSync(new URL('PLAYTHROUGH_RESULTS_COST75.md', dir), out.join('\n') + '\n');
console.log(out.join('\n'));
