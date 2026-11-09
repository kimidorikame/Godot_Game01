// v2 の基準（playthrough_results_regulars_v2.json）との照合：「遊びの結果」だけを比べる（2026-11-09・計測）。
// 使い方（このフォルダで）:
//   node compare_v2_play.mjs <今回の results.json> [基準の results.json（既定＝playthrough_results_regulars_v2.json）]
// 比べるのは、各周（方針×シード）の結果のうち、会話の長さや支払いの順番では変わらない項目だけ（判定・売上・チップ・仕入れ・
// その日の終わりの現金・評判・提供と未提供の数・最終の結果など）。下の EXCLUDED の項目は比べない（違っても一覧に数を出すだけ）。
// 遊びの結果に違いがあれば、違う周と項目を出して終了コード1。基準のファイルは読むだけ（上書きしない）。
// 説明：V2_COMPARE.md。
import fs from 'node:fs';

// 比べない項目（会話の行数や支払いの順番で変わる「途中の数」）。path は周の中の場所（rows[] は各日の行）。
export const EXCLUDED = [
  { path: 'clicks', why: 'クリックの回数（セリフの行を読む操作を含む）。会話の行数で変わる' },
  { path: 'steps', why: '自動試遊の手数（会話の行数で変わる）' },
  { path: 'actions.next_text_event', why: 'セリフの行を読み進めた回数（会話の行数で変わる）。ほかの actions（仕入れ・具材・水・だし・断る など）は比べる' },
  { path: 'rows[].actions_cumulative', why: 'その日までの操作の回数の累計（セリフの行を読む操作を含む）' },
  { path: 'day1_cash.after_wake', why: 'Day1 の途中の残高（仕込みに入った時点）。支払いの順番で変わる' },
  { path: 'day1_cash.after_kit', why: 'Day1 の途中の残高（初日セットのあと）。水道代を朝の会話で払うと下がる' },
  { path: 'day1_cash.after_tier', why: 'Day1 の途中の残高（鍋の素を選んだあと）。同上' },
  { path: 'day1_cash.after_market', why: 'Day1 の途中の残高（開店の時点）。支払いの順番で変わりうる' },
];

const DIR = new URL('./', import.meta.url);
const load = (name) => JSON.parse(fs.readFileSync(new URL(name, DIR), 'utf8'));
const same = (x, y) => JSON.stringify(x) === JSON.stringify(y);

// 周の結果から、比べない項目を外した写し（遊びの結果だけ）。
export function playResult(run) {
  const r = JSON.parse(JSON.stringify(run));
  delete r.clicks;
  delete r.steps;
  if (r.actions) delete r.actions.next_text_event;
  if (Array.isArray(r.rows)) for (const row of r.rows) delete row.actions_cumulative;
  if (r.day1_cash) for (const k of ['after_wake', 'after_kit', 'after_tier', 'after_market']) delete r.day1_cash[k];
  return r;
}

// 2つの値の違う場所（"rows[2].cash" の形）を集める。
function diffPaths(x, y, base, out) {
  if (same(x, y)) return out;
  const isObj = (v) => v !== null && typeof v === 'object';
  if (isObj(x) && isObj(y) && Array.isArray(x) === Array.isArray(y)) {
    for (const k of new Set([...Object.keys(x), ...Object.keys(y)])) {
      const p = Array.isArray(x) ? `${base}[${k}]` : (base ? `${base}.${k}` : k);
      diffPaths(x[k], y[k], p, out);
    }
    return out;
  }
  out.push(base);
  return out;
}

const generalize = (p) => p.replace(/\[\d+\]/g, '[]');

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}` || process.argv[1].endsWith('compare_v2_play.mjs')) {
  const [nowName, baseName = 'playthrough_results_regulars_v2.json'] = process.argv.slice(2);
  if (!nowName) {
    console.log('使い方: node compare_v2_play.mjs <今回の results.json> [基準の results.json]');
    process.exit(2);
  }
  const base = load(baseName), now = load(nowName);
  const playDiffs = [], excludedCounts = {}, missing = [];
  for (const r of now.runs) {
    const o = base.runs.find((x) => x.policy === r.policy && x.seed === r.seed);
    if (!o) { missing.push(`${r.policy}#${r.seed}`); continue; }
    for (const p of diffPaths(playResult(o), playResult(r), '', [])) playDiffs.push({ run: `${r.policy}#${r.seed}`, path: p, base: o, now: r });
    for (const p of diffPaths(o, r, '', [])) {
      const g = generalize(p);
      if (EXCLUDED.some((e) => e.path === g)) excludedCounts[g] = (excludedCounts[g] || 0) + 1;
    }
  }
  const compared = now.runs.length - missing.length;
  console.log(`V2PLAY compared ${compared} of ${now.runs.length}（方針 ${now.policies.length}）  遊びの結果の違い ${playDiffs.length}  基準に無い周 ${missing.length}`);
  console.log('比べない項目の違い（周×箇所の数）: ' + (Object.keys(excludedCounts).length ? JSON.stringify(excludedCounts) : 'なし'));
  for (const d of playDiffs.slice(0, 20)) console.log(`  違い ${d.run} ${d.path}`);
  if (missing.length) console.log('  基準に無い周: ' + missing.join(', '));
  process.exit(playDiffs.length || missing.length || compared === 0 ? 1 : 0);
}
