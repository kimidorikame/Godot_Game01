# v2 との照合のやり方（2026-11-09 から）

コミット前の確認の「v2 との照合」は、**遊びの結果だけを比べる**。会話の行数や支払いの順番で変わる「途中の数」は比べない。

## 手順

1. 自動試遊を3シード×13方針で回す（プロジェクト直下で。`<名前>`は一時ファイル）。

   ```
   godot --headless --path . --script res://planning/playtest_2026_10_11/run_playthroughs.gd -- 3 3 <名前>.json all reach_true 75
   ```

2. このフォルダで照合する。

   ```
   node compare_v2_play.mjs <名前>.json
   ```

   - 「遊びの結果の違い 0」「基準に無い周 0」「compared 39 of 39」なら一致（終了コード0）。
   - 違いがあれば、違う周（方針#シード）と項目を最大20件出す（終了コード1）。
   - 比べない項目に違いがあれば、その項目と数を1行に出す（一致の判断には使わない）。

3. 一時ファイル（`<名前>.json`）は消す。基準の `playthrough_results_regulars_v2.json` は読むだけで、上書きしない。

## 比べる項目（遊びの結果）

各周の結果のうち、下の「比べない項目」以外のすべて。主なもの：

- 判定（各日の `grades`・`quality`・`regular_good_plus`・`regular_great`）
- 売上・チップ（各日の `sales`。最終の `result_summary`）
- 仕入れ（`purchases`・各日の `spend`・`stock`・`dashi`・`water`、`actions` の仕入れ・具材・水・だし・断る などの操作の回数）
- その日の終わりの現金（各日の `cash`・最終の `cash`・`day1_cash.end`・`day1_cash.tier`）
- 評判（各日の `open_rep`・`next_rep`・最終の `rep`）
- 提供と未提供の数（各日の `served`・`unserved`・`declined_records`・`demand`・`judged_demand`・`regular_cups`・`soup_left`）
- 最終の結果（`result_summary`・`result_phase`・`completed`・`stalled`・`incidents`・`failures`・`closing_stock_units`）

## 比べない項目（2026-11-09 に外した）

| 項目 | 理由 |
|---|---|
| `clicks` | クリックの回数（セリフの行を読む操作を含む）。会話の行数で変わる |
| `steps` | 自動試遊の手数。会話の行数で変わる |
| `actions.next_text_event` | セリフの行を読み進めた回数。ほかの `actions` は比べる |
| `rows[].actions_cumulative` | その日までの操作の回数の累計（セリフの行を読む操作を含む） |
| `day1_cash.after_wake` | Day1 の途中の残高（仕込みに入った時点） |
| `day1_cash.after_kit` | Day1 の途中の残高（初日セットのあと）。水道代を朝の会話で払うと下がる |
| `day1_cash.after_tier` | Day1 の途中の残高（鍋の素を選んだあと） |
| `day1_cash.after_market` | Day1 の途中の残高（開店の時点） |

一覧の正は `compare_v2_play.mjs` の `EXCLUDED`（ここを直したら、この表も直す）。

## 経緯

- 2026-11-09 まで：全キー一致（`clicks`・`steps`・`actions`・`rows` を含む）で比べていた。
- 中身U1（1日目の本番の文）で会話の行が増え、水道代を朝の会話（梁伯の場面）で払うようにしたので、クリックの回数と Day1 の途中の残高が
  変わった（遊びの結果は同じ）。あわせて、自動試遊が食後の行（`part` が `body`・`after_bill`・`closing`）でも鍋を直していたのをやめた
  （`playthroughs.gd` の `AFTER_MEAL_PARTS`。その客の椀はもう出し終えていて、空の鍋に水とだしを足して次の日の仕入れまで変わっていた）。
