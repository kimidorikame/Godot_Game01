// 夜湯：BALANCE_REDESIGN_PLAN.md の独立監査モデル
//
// 実行方法
//   node planning/independent_audit.mjs            … 第1部（乱数なし）だけを出力
//   node planning/independent_audit.mjs --economy  … 第2部（収支・目標達成率）も実行
//   node planning/independent_audit.mjs --economy 300   … 第2部のシード数を変える
//   node planning/independent_audit.mjs --json     … 生データをJSONで出力
//
// 固定シード／乱数について
//   第1部（評判・初日材料・鍋）は乱数を一切使わない。需要の±1は確率付きで
//   全経路（3^6＝729）を厳密列挙するため、実行結果は常に同一で、シード指定は不要。
//   第2部（方針別成績）だけは planning/balance_comparison.mjs の simulate() を
//   シード1〜N（既定1000）で呼ぶ。同モデルの乱数はシード決定的なので再実行で同じ値になる。
//
// 独立性の範囲（重要）
//   第1部は正本 BALANCE_REDESIGN_PLAN.md の散文だけから式を起こした再実装であり、
//   balance_comparison.mjs のコードは参照していない。両者が一致すれば相互検証になる。
//   第2部は「境界値だけを振る感度試験」であり、独立な再実装ではない。
//   在庫ロット・腐敗・パック端数の扱いは balance_comparison.mjs のものをそのまま使う。
//
// 入力条件
//   初期現金600／初日費用140／日費用80／売価45／初期評判30／Day1は9杯固定。
//   仕込み 小8-110・中11-110・大14-140（10／杯）、同時容量14、水は一晩2回
//   （残量+2・濃さ-2）、濃縮だし16（濃さ+2）、明け方に濃さ+1、正常域2〜4。
//
// この監査が測っていないもの
//   面白さ、UIの理解、操作時間、人的な誤操作の分布、会話・演出。
//   第1部は「全杯を提供できた場合」の評判軌跡であり、材料不足は考慮しない。

import assert from 'node:assert/strict';

// ── 正本 §2 §5 から起こした定数 ───────────────────────────────
const SCORE = { BAD: 0, OK: 35, GOOD: 75, GREAT: 100 };
const INITIAL_REP = 30;
const DAY1_CUPS = 9;
const NOISE = [[-1, 0.25], [0, 0.5], [1, 0.25]];   // 中心−1／中心／中心＋1
const DOSE_PRICE = 16;

const SCHEDULE = [
  ['delivery', 'thug', 'granny'], ['officer', 'delivery', 'granny'],
  ['lady', 'thug', 'officer'], ['streamer', 'granny', 'delivery'],
  ['officer', 'lady', 'thug'], ['streamer', 'officer', 'lady'],
  ['delivery', 'streamer', 'granny'],
];

// 需要帯（正本 §5）。最上帯の下限 top だけを可変にする。
const center = (rep, top) => rep < 20 ? 7 : rep < 45 ? 9 : rep < 60 ? 11 : rep < top ? 14 : 17;
const nextRep = (rep, q) => Math.round(rep * 0.7 + q * 0.3);

// その日にGREATにできる杯数。初回来店は退店時まで好物が分からない（正本 §4）。
// Day1の配達員だけ本人2杯＋持ち帰り1杯で、持ち帰りは別レシピのためGREAT対象外（正本 §7）。
function greatsPerDay({ learn }) {
  const seen = new Set();
  return SCHEDULE.map((mains, i) => {
    let g = 0;
    for (const m of mains) {
      const cups = i === 0 && m === 'delivery' ? 2 : 1;
      if (!learn || seen.has(m)) g += cups;
      seen.add(m);
    }
    return g;
  });
}

// ── 第1部A：評判経路の厳密列挙 ────────────────────────────────
// failDay 日に failCups 杯だけ failScore 点を出す（0なら失敗なし）。
function enumerate({ top, learn = true, failDay = 0, failCups = 0, failScore = SCORE.BAD, rep0 = INITIAL_REP }) {
  const G = greatsPerDay({ learn });
  const paths = [];
  (function walk(day, rep, w, cups, day7Rep) {
    if (day === 8) { paths.push({ w, cups, day7Rep }); return; }
    for (const [noise, pw] of day === 1 ? [[0, 1]] : NOISE) {
      const n = day === 1 ? DAY1_CUPS : center(rep, top) + noise;
      const g = G[day - 1];
      const bad = day === failDay ? Math.min(failCups, n - g) : 0;
      const q = (g * SCORE.GREAT + bad * failScore + (n - g - bad) * SCORE.GOOD) / n;
      walk(day + 1, nextRep(rep, q), w * pw, cups + n, day === 7 ? rep : day7Rep);
    }
  })(1, rep0, 1, 0, null);
  return {
    paths: paths.length,
    mass: paths.reduce((s, p) => s + p.w, 0),
    day7Rep: [Math.min(...paths.map(p => p.day7Rep)), Math.max(...paths.map(p => p.day7Rep))],
    reachTop: paths.reduce((s, p) => s + p.w * (p.day7Rep >= top), 0),
    meanCups: paths.reduce((s, p) => s + p.w * p.cups, 0),
  };
}
// 失敗を最悪の日に置いたときの到達率
const worstReach = (top, cups, score) => cups === 0
  ? enumerate({ top }).reachTop
  : Math.min(...[1, 2, 3, 4, 5, 6, 7].map(d =>
      enumerate({ top, failDay: d, failCups: cups, failScore: score }).reachTop));

// ── 第1部B：初日セットの材料検算（正本 §3 §7）────────────────────
const ITEM = { // [単価, パック数, 生鮮?]
  hot: [5, 5, false], mellow: [5, 3, true], sour: [4, 5, false], bitter: [4, 3, true],
  savory: [5, 5, false], meat: [8, 3, true], offal: [10, 3, true], tofu: [8, 3, true],
  melon: [10, 5, false], wrapper: [6, 3, true], noodle: [8, 5, false],
  cartilage: [8, 3, true], ear: [10, 5, false], tendon: [12, 3, true],
  clam: [16, 3, true], shrimp: [18, 3, true], maw: [20, 5, false],
};
const SINGLE = { offal: 12, shrimp: 20 };
const STARTER = { hot: 5, mellow: 6, savory: 5, meat: 6, tofu: 6, wrapper: 3, offal: 1 };

function priceFor(id, n) {
  const [unit, pack] = ITEM[id];
  let best = Math.ceil(n / pack) * pack * unit;
  if (SINGLE[id]) best = Math.min(best, Math.floor(n / pack) * pack * unit + (n % pack) * SINGLE[id]);
  return best;
}
const starterCost = () => DOSE_PRICE +
  Object.entries(STARTER).reduce((s, [id, n]) => s + priceFor(id, n), 0);

// Day1 9杯（宵: 配達員本人2＋持ち帰り1＋港湾2／夜半: チンピラ1＋安宿受付2／明け方: 老婆1）
function day1Needs(favoritesKnown) {
  const n = {};
  const add = (id, k) => { n[id] = (n[id] ?? 0) + k; };
  add('hot', 4); add('meat', 4);                      // 配達員本人2＋港湾2（HOT+POWER）
  add('mellow', 4); add('tofu', 4);                   // 持ち帰り1＋チンピラ1＋安宿受付2（MELLOW+GENTLE）
  add('savory', 1); add('wrapper', 1);                // 老婆（SAVORY+FILLING）
  if (favoritesKnown) { add('tofu', 2); add('meat', 1); add('offal', 1); }
  return n;
}

// ── 第1部C：鍋の実行可能性 ────────────────────────────────────
// 減点なし（濃さ2〜4）で出し切れるか。出せない場合は null。
function potPlan(prep, cupsByPhase) {
  let v = prep, s = 3, water = 0, doses = 0;
  for (let phase = 0; phase < 3; phase++) {
    if (phase === 2) s += 1;                                   // 明け方の煮詰まり
    for (let i = 0; i < cupsByPhase[phase]; i++) {
      while (v < 1) {
        if (water >= 2 || v + 2 > 14) return null;
        if (s - 2 < 0) { if (s + 2 > 5) return null; s += 2; doses++; }
        water++; v += 2; s -= 2;
        if (s < 2) { if (s + 2 > 5) return null; s += 2; doses++; }
      }
      if (s < 2 || s > 4) { if (s + 2 <= 5) { s += 2; doses++; } else return null; }
      v -= 1;
    }
  }
  return { water, doses, leftover: v, doseCost: doses * DOSE_PRICE };
}
// 正本 §5 のモブ配置規則から時間帯別の杯数を作る
function cupsByPhase(n, day) {
  const m = n - 3, g = Math.ceil(m / 4);
  const groups = Array.from({ length: g }, (_, i) => Math.floor(m / g) + (i < m % g ? 1 : 0));
  const phaseOf = i => day === 7 ? (i < Math.ceil(g / 2) ? 0 : 1)
    : g === 1 ? 1 : g <= 3 ? i : (i === 0 || i === 1 ? 0 : i - 1);
  const out = [1, 1, 1];
  groups.forEach((c, i) => { out[phaseOf(i)] += c; });
  return out;
}

// ── 固定検査（回帰用）──────────────────────────────────────
function selfChecks() {
  assert.equal(starterCost(), 222, '初日セットは222');
  assert.equal(600 - 140 - 80 - 80 - starterCost() + DAY1_CUPS * 45, 483, '初日閉店483');
  assert.equal(priceFor('shrimp', 1), 20, '海老の小口は20');
  assert.equal(priceFor('shrimp', 3), 54, '海老3個はパック54');
  assert.equal(priceFor('offal', 2), 24, 'モツ2個は小口24');
  const e = enumerate({ top: 75, learn: true });
  assert.equal(e.paths, 729); assert.equal(e.mass, 1);
  assert.equal(e.reachTop, 0.1875, '初見・境界75の到達率は18.75%');
  assert.equal(enumerate({ top: 74, learn: true }).reachTop, 1);
  assert.equal(enumerate({ top: 75, learn: false }).reachTop, 0.89453125);
  assert.equal(potPlan(14, cupsByPhase(18, 7)).doses, 2, 'Day7の18杯はだし2回');
  assert.equal(potPlan(14, cupsByPhase(18, 7)).doseCost + 140, 172, 'Day7の鍋関係費用は172');
  assert.equal(potPlan(8, [5, 3, 1]).water <= 2, true, 'Day1は水2回以内');
  return 12;
}

// ── 出力 ────────────────────────────────────────────────────
const report = { selfChecks: selfChecks() };

report.A_評判境界 = Object.fromEntries([
  ['初見・境界75', enumerate({ top: 75, learn: true })],
  ['初見・境界74', enumerate({ top: 74, learn: true })],
  ['初見・境界71', enumerate({ top: 71, learn: true })],
  ['好物既知・境界75', enumerate({ top: 75, learn: false })],
]);

report.B_失敗耐性 = {};
for (const top of [69, 70, 71, 72, 73, 74, 75]) {
  report.B_失敗耐性[`境界${top}`] = {
    失敗なし: worstReach(top, 0, 0),
    OK1杯: worstReach(top, 1, SCORE.OK), OK2杯: worstReach(top, 2, SCORE.OK),
    OK3杯: worstReach(top, 3, SCORE.OK),
    BAD1杯: worstReach(top, 1, SCORE.BAD), BAD2杯: worstReach(top, 2, SCORE.BAD),
  };
}

report.C_初期評判感度 = {};
for (const r0 of [20, 25, 28, 30, 32, 35, 40]) {
  const e74 = enumerate({ top: 74, rep0: r0 }), e71 = enumerate({ top: 71, rep0: r0 });
  report.C_初期評判感度[`初期評判${r0}`] =
    { Day7開店評判: e74.day7Rep, 境界74到達: e74.reachTop, 境界71到達: e71.reachTop };
}

const surplus = need => Object.fromEntries(
  Object.keys(STARTER).map(id => [id, STARTER[id] - (need[id] ?? 0)]));
report.D_初日 = {
  セット金額: starterCost(),
  開店前現金: 600 - 140 - 80 - 80 - starterCost(),
  閉店現金: 600 - 140 - 80 - 80 - starterCost() + DAY1_CUPS * 45,
  初見GOOD時の余り: surplus(day1Needs(false)),
  好物既知GREAT時の余り: surplus(day1Needs(true)),
  初見が使えないモツ代: SINGLE.offal,
};

report.E_鍋 = { 'Day1 9杯・小仕込み': { 時間帯別: [5, 3, 1], ...potPlan(8, [5, 3, 1]) } };
for (const [label, n, prep, day] of [
  ['8杯・小', 8, 8, 3], ['10杯・小', 10, 8, 3], ['12杯・小(帯上限)', 12, 8, 3],
  ['13杯・中', 13, 11, 4], ['15杯・中(帯上限)', 15, 11, 4],
  ['16杯・大', 16, 14, 5], ['18杯・大(帯上限)', 18, 14, 5], ['Day7 18杯・大', 18, 14, 7],
]) {
  const p = cupsByPhase(n, day);
  report.E_鍋[label] = { 時間帯別: p, ...(potPlan(prep, p) ?? { 提供不可: true }) };
}

// ── 第2部：収支・目標達成率 ──────────────────────────────────
// balance_comparison.mjs の simulate() を条件だけ変えて呼ぶ感度試験。
// 在庫ロット・腐敗・パック端数の扱いは同モデルのものをそのまま使うので、
// 第1部のような独立再実装ではない。そこに誤りがあれば同じ誤りを引き継ぐ。
if (process.argv.includes('--economy')) {
  const { simulate } = await import('./balance_comparison.mjs');
  const seeds = Number(process.argv.find(a => /^\d+$/.test(a)) ?? 1000);
  const mean = a => a.reduce((s, x) => s + x, 0) / a.length;
  const q = (a, p) => a.slice().sort((x, y) => x - y)[Math.floor((a.length - 1) * p)];
  const run = (cfg, pol) => {
    const r = Array.from({ length: seeds }, (_, i) => simulate(i + 1, cfg, pol));
    const cash = r.map(x => x.cash);
    return {
      cash: mean(cash), p10: q(cash, .1), p90: q(cash, .9),
      cups: mean(r.map(x => x.served)), rep: mean(r.map(x => x.rep)),
      spoiled: mean(r.map(x => x.spoiled)), stock: mean(r.map(x => x.stock)),
      unserved: mean(r.map(x => x.refusedRate)), high: mean(r.map(x => Number(x.day7High))),
      t1200: mean(cash.map(x => Number(x >= 1200))), t1500: mean(cash.map(x => Number(x >= 1500))),
      t1600: mean(cash.map(x => Number(x >= 1600))), t1700: mean(cash.map(x => Number(x >= 1700))),
    };
  };
  const REC71 = { single: true, topThreshold: 71, partial: true };          // 初日セット222
  const REC71_210 = { ...REC71, starterOffal: 0 };                          // 初見セット210
  const FG = { great: true, learn: true };

  report.F_設定比較 = {};   // どの変更が効いたかを1つずつ切り分ける（方針は初見・好物優先で固定）
  for (const [name, cfg] of [
    ['旧稿の設定', {}], ['小口＋初日セットのみ', { single: true }],
    ['評判境界71のみ', { topThreshold: 71 }], ['改訂値(境界71・セット222)', REC71],
    ['改訂値(境界71・セット210)', REC71_210],
  ]) report.F_設定比較[name] = run(cfg, FG);

  report.G_境界とGREAT回数 = {};  // GREATへの投資が報われるかは境界値で入れ替わる
  for (const top of [70, 71, 72, 74]) {
    const row = {};
    for (let L = 0; L <= 15; L++)
      row[`GREAT${L}回`] = run({ ...REC71, topThreshold: top }, L === 0 ? {} : { ...FG, greatLimit: L }).cash;
    report.G_境界とGREAT回数[`境界${top}`] = row;
  }

  report.H_境界71の方針別 = {};   // 目標値の識別力を見る
  for (const [name, pol] of [
    ['全員GOOD(上限仕入)', {}], ['GREAT3回', { ...FG, greatLimit: 3 }],
    ['GREAT8回', { ...FG, greatLimit: 8 }], ['GREAT9回', { ...FG, greatLimit: 9 }],
    ['好物を全部GREAT(15回)', FG], ['平均仕入＋部分提供', { forecast: 'mean' }],
    ['保存品優先', { preserve: true }], ['品質失敗2件', { mistakes: true }],
    ['1組を全員断る', { refusal: true }], ['Day2に評判10へ', { repShockDay2: 10 }],
    ['買えるだけ買う', { overbuy: true }],
  ]) report.H_境界71の方針別[name] = run(REC71, pol);

  report.economySeeds = seeds;
}

if (process.argv.includes('--json')) {
  console.log(JSON.stringify(report, null, 2));
} else {
  const pc = x => (100 * x).toFixed(1).padStart(6) + '%';
  console.log(`固定検査 ${report.selfChecks}件すべて通過\n`);
  console.log('── A. 評判境界（Day2〜7の±1を729経路すべて確率付きで列挙）──');
  for (const [k, v] of Object.entries(report.A_評判境界))
    console.log(`  ${k.padEnd(18)} Day7開店評判 ${v.day7Rep.join('〜')}  最上帯到達 ${pc(v.reachTop)}  平均杯数 ${v.meanCups.toFixed(2)}`);
  console.log('\n── B. 最上帯の境界値 × 失敗耐性（失敗を最悪の日に置いた場合）──');
  console.log('  境界   失敗なし   OK1杯   OK2杯   OK3杯  BAD1杯  BAD2杯');
  for (const [k, v] of Object.entries(report.B_失敗耐性))
    console.log(`  ${k.padEnd(6)} ${pc(v.失敗なし)} ${pc(v.OK1杯)} ${pc(v.OK2杯)} ${pc(v.OK3杯)} ${pc(v.BAD1杯)} ${pc(v.BAD2杯)}`);
  console.log('\n── C. 初期評判への感度 ──');
  for (const [k, v] of Object.entries(report.C_初期評判感度))
    console.log(`  ${k.padEnd(10)} Day7開店評判 ${String(v.Day7開店評判.join('〜')).padEnd(7)} 境界74到達 ${pc(v.境界74到達)}  境界71到達 ${pc(v.境界71到達)}`);
  console.log('\n── D. 初日セット ──');
  console.log(`  金額 ${report.D_初日.セット金額} ／ 開店前 ${report.D_初日.開店前現金} ／ 閉店 ${report.D_初日.閉店現金}`);
  console.log(`  初見GOOD時の余り      ${JSON.stringify(report.D_初日.初見GOOD時の余り)}`);
  console.log(`  好物既知GREAT時の余り  ${JSON.stringify(report.D_初日.好物既知GREAT時の余り)}`);
  console.log('\n── E. 鍋（減点なしで出し切れるか）──');
  for (const [k, v] of Object.entries(report.E_鍋))
    console.log(`  ${k.padEnd(18)} 時間帯${JSON.stringify(v.時間帯別)} 水${v.water}回 だし${v.doses}回 追加費用${v.doseCost}`);

  if (report.F_設定比較) {
    const y = x => (100 * x).toFixed(1).padStart(6) + '%';
    console.log(`\n── F. 設定比較（方針は初見・好物優先で固定・${report.economySeeds}シード）──`);
    console.log('  条件                        平均現金  腐敗  最上帯到達  1500達成');
    for (const [k, v] of Object.entries(report.F_設定比較))
      console.log(`  ${k.padEnd(26)} ${v.cash.toFixed(0).padStart(6)} ${v.spoiled.toFixed(0).padStart(5)} ${y(v.high)} ${y(v.t1500)}`);
    console.log('\n── G. 境界値ごとの「GREAT何回が得か」──');
    console.log('  GREAT回数  ' + Object.keys(report.G_境界とGREAT回数).map(s => s.padStart(7)).join(''));
    for (let L = 0; L <= 15; L++)
      console.log(`  ${String(L).padStart(7)}回  ` + Object.values(report.G_境界とGREAT回数)
        .map(r => r[`GREAT${L}回`].toFixed(0).padStart(7)).join(''));
    for (const [k, r] of Object.entries(report.G_境界とGREAT回数)) {
      const vals = Object.values(r), best = Math.max(...vals);
      console.log(`  ${k}: 最良 GREAT${vals.indexOf(best)}回=${best.toFixed(0)}  GREAT0回=${vals[0].toFixed(0)}  差 ${best - vals[0] >= 0 ? '+' : ''}${(best - vals[0]).toFixed(0)}`);
    }
    console.log('\n── H. 境界71での方針別成績と目標達成率 ──');
    console.log('  方針                     平均現金   P10    P90  杯数  評判  ≥1200 ≥1500 ≥1600 ≥1700');
    for (const [k, v] of Object.entries(report.H_境界71の方針別))
      console.log(`  ${k.padEnd(24)} ${v.cash.toFixed(0).padStart(6)} ${String(v.p10).padStart(6)} ${String(v.p90).padStart(6)} ${v.cups.toFixed(1).padStart(5)} ${v.rep.toFixed(1).padStart(5)} ` +
        [v.t1200, v.t1500, v.t1600, v.t1700].map(x => (100 * x).toFixed(0).padStart(5) + '%').join(''));
  } else {
    console.log('\n（収支・目標達成率は --economy を付けると実行します）');
  }
}
