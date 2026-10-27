// 計測H（チップと「具2個」）の集計。数字と事実だけを出す。判断・調整の提案は書かない。
// 使い方: node summarize_tip_gu.mjs merge   … tmp_h_*.json を playthrough_results_tip_gu.json にまとめる（tmp は消す）
//         node summarize_tip_gu.mjs tables  … 表を標準出力へ（PLAYTHROUGH_RESULTS_TIP_GU.md に貼る）
// 入力：tmp_h_<方針>_<設定>.json（playthroughs.gd。方針＝p0／p50／p100＝情報量の実験の基本GOOD・k2＝備蓄型・個数k=2。各30シード）
import fs from 'node:fs';
const dir = new URL('./', import.meta.url);
const read = n => JSON.parse(fs.readFileSync(new URL(n, dir), 'utf8'));
const POLICIES = [
  { id: 'p0', label: '情報量 p=0%（基本GOOD）' },
  { id: 'p50', label: '情報量 p=50%（基本GOOD）' },
  { id: 'p100', label: '情報量 p=100%（基本GOOD）' },
  { id: 'k2', label: '備蓄型（個数 k=2）' },
];
const SETTINGS = [
  { id: 'a', label: 'a 現行（t=0・具2種類なし・定価45）' },
  { id: 'b', label: 'b T (5,10)' },
  { id: 'c', label: 'c T (10,20)' },
  { id: 'd', label: 'd G（具2種類・t=0）' },
  { id: 'e', label: 'e G＋T (5,10)' },
  { id: 'f', label: 'f G＋T (10,20)' },
  { id: 'g', label: 'g G＋T (5,10)＋定価50' },
  // 補足：2つ目の具の仕入れまで方針に入れた版（d〜g をやり直したもの。上の d〜g は、仕入れを変えない版＝参考）
  { id: 'd2', label: "d' G＋仕入れ（t=0）" },
  { id: 'e2', label: "e' G＋仕入れ＋T (5,10)" },
  { id: 'f2', label: "f' G＋仕入れ＋T (10,20)" },
  { id: 'g2', label: "g' G＋仕入れ＋T (5,10)＋定価50" },
];
const OUT = 'playthrough_results_tip_gu.json';

if (process.argv[2] === 'merge') {
  const combos = [];
  let commit = '';
  for (const p of POLICIES) for (const s of SETTINGS) {
    const f = `tmp_h_${p.id}_${s.id}.json`;
    const d = read(f);
    commit = d.commit;
    combos.push({ policy: p.id, setting: s.id, tip_gu: d.tip_gu ?? null, info_levels: d.info_levels ?? null, info_stock: d.info_stock ?? null, runs: d.runs });
  }
  fs.writeFileSync(new URL(OUT, dir), JSON.stringify({ commit, daily_operating_cost: 75, reach: 'reach_true', seeds: 30,
    note: '計測H：ハーネスだけの設定（t1・t2・two_gu・price）。案T＝提供ごとに GOOD +t1・GREAT +t2（BAD・OK は 0）。案G＝具が1種類しか入っていない椀は−1段階（すでに減点があれば重ねない）。評判の式・判定・SaleRule は変えていない。',
    combos }));
  for (const p of POLICIES) for (const s of SETTINGS) fs.unlinkSync(new URL(`tmp_h_${p.id}_${s.id}.json`, dir));
  console.log('merged', combos.length, 'combos');
  process.exit(0);
}

const data = read(OUT);
const goals = JSON.parse(fs.readFileSync(new URL('../../data/campaigns/week7.json', dir), 'utf8')).goals;
const mean = a => a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0;
const f0 = x => Math.round(x).toString();
const f1 = x => x.toFixed(1);
const f2 = x => x.toFixed(2);
const pct = x => (100 * x).toFixed(1) + '%';
const sumRows = (r, k) => r.rows.reduce((s, d) => s + (d[k] ?? 0), 0);
const spend = (r, k) => r.rows.reduce((s, d) => s + (d.spend?.[k] ?? 0), 0);
const goodPlus = r => r.result_summary?.good_plus_cups ?? 0;
const judged = r => r.result_summary?.judged_cups ?? 0;
function stat(runs) {
  const total = r => r.result_summary?.cash_plus_repair ?? r.cash;
  const served = runs.map(r => sumRows(r, 'served'));
  const market = runs.map(r => spend(r, 'market'));
  const prep = runs.map(r => spend(r, 'prep'));
  return { n: runs.length, cash: mean(runs.map(r => r.cash)), t1500: mean(runs.map(r => Number(total(r) >= goals.cash_standard))),
    good: mean(runs.map(r => goodPlus(r) / Math.max(judged(r), 1))),
    market: mean(market), prep: mean(prep), served: mean(served),
    perCup: mean(runs.map((r, i) => market[i] / Math.max(served[i], 1))), perCupPrep: mean(runs.map((r, i) => (market[i] + prep[i]) / Math.max(served[i], 1))),
    tips: mean(runs.map(r => r.tips ?? 0)), rep: mean(runs.map(r => r.rep)), over: runs.reduce((s, r) => s + r.incidents.filter(i => i.type === 'game_over').length, 0),
    gu: mean(runs.map(r => r.gu_penalized ?? 0)) };
}
const stats = {};
for (const c of data.combos) stats[`${c.policy}_${c.setting}`] = stat(c.runs);
const out = [];
const w = s => out.push(s);
w('| 方針 | 設定 | 周 | 平均最終現金 | aとの差 | 1500到達率 | GOOD以上率 | 1杯あたり材料費（仕入れ） | 〃（仕入れ＋鍋の素） | 1週間の仕入れ総額 | チップ総額 | 具の減点を受けた杯（1周） | 最終の評判 | ゲームオーバー |');
w('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
for (const p of POLICIES) for (const s of SETTINGS) {
  const x = stats[`${p.id}_${s.id}`], a = stats[`${p.id}_a`];
  const d = x.cash - a.cash;
  w(`| ${p.label} | ${s.label} | ${x.n} | ${f0(x.cash)} | ${s.id === 'a' ? '—' : (d >= 0 ? '+' : '') + f0(d)} | ${pct(x.t1500)} | ${pct(x.good)} | ${f2(x.perCup)} | ${f2(x.perCupPrep)} | ${f0(x.market)} | ${f0(x.tips)} | ${['a', 'b', 'c'].includes(s.id) ? '—' : f1(x.gu)} | ${f1(x.rep)} | ${x.over} |`);
}
w('');
w('a との差（a を 0 とした差。平均最終現金／1500到達率／GOOD以上率／最終の評判）');
w('');
w('| 方針 | b | c | d | e | f | g | d\' | e\' | f\' | g\' |');
w('|---|---|---|---|---|---|---|---|---|---|---|');
for (const p of POLICIES) {
  const a = stats[`${p.id}_a`];
  const cells = ['b', 'c', 'd', 'e', 'f', 'g', 'd2', 'e2', 'f2', 'g2'].map(id => {
    const x = stats[`${p.id}_${id}`];
    const sg = v => (v >= 0 ? '+' : '') + v;
    return `${sg(f0(x.cash - a.cash))}／${sg(f1(100 * (x.t1500 - a.t1500)))}pt／${sg(f1(100 * (x.good - a.good)))}pt／${sg(f1(x.rep - a.rep))}`;
  });
  w(`| ${p.label} | ${cells.join(' | ')} |`);
}
console.log(out.join('\n'));
