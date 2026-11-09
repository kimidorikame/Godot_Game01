# 基準との照合のやり方（2026-11-09 から。旧名 V2_COMPARE.md）

コミット前の確認の「基準との照合」は、**遊びの結果だけを比べる**。会話の行数や支払いの順番で変わる「途中の数」は比べない。
**今の基準は v3**（`playthrough_baseline_v3.json`）。v2（`playthrough_results_regulars_v2.json`）は昔の状態の記録として残す（どの基準のファイルも上書きしない）。

> 名前の注意：「基準 v3」（このファイルの v3）と、UI準備C⑤の「予報を使わない自動試遊（v3）」（`playthrough_results_regulars_v3.json`・
> `PLAYTHROUGH_RESULTS_V3.md`）は別のもの。ファイル名がぶつからないよう、基準 v3 は `playthrough_baseline_v3.json` にした。

## 手順

1. 自動試遊を3シード×13方針で回す（プロジェクト直下で。`<名前>`は一時ファイル）。

   ```
   godot --headless --path . --script res://planning/playtest_2026_10_11/run_playthroughs.gd -- 3 3 <名前>.json all reach_true 75
   ```

2. このフォルダで照合する。

   ```
   node compare_baseline.mjs <名前>.json          ← 今の基準（v3）と比べる
   node compare_baseline.mjs <名前>.json v2       ← 昔の基準（v2）と比べる（基準のファイル名を直接書いてもよい）
   ```

   - 「遊びの結果の違い 0」「基準に無い周 0」「compared 39 of 39」なら一致（終了コード0）。
   - 違いがあれば、違う周（方針#シード）と項目を最大20件出す（終了コード1）。
   - 比べない項目に違いがあれば、その項目と数を1行に出す（一致の判断には使わない）。

3. 一時ファイル（`<名前>.json`）は消す。

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

一覧の正は `compare_baseline.mjs` の `EXCLUDED`（ここを直したら、この表も直す）。

## 基準の一覧

| 基準 | ファイル | 作った日 | 元にしたコミット | 条件 | 作った理由 |
|---|---|---|---|---|---|
| v2 | `playthrough_results_regulars_v2.json` | 2026-10-18 | `48dd9d7` | 30シード×13方針・reach_true・運営費75 | 運営費75の新しい基準（`PLAYTHROUGH_RESULTS_COST75_V2.md`） |
| **v3（今の基準）** | `playthrough_baseline_v3.json` | 2026-11-09 | `307b769` | 3シード×13方針・reach_true・運営費75（照合と同じ条件） | 中身U1で阿強の3杯目（持ち帰り）の札を まろやか＋やさしい → うましお＋やさしい に変えた（意図した変更） |

基準の名前とファイルは `compare_baseline.mjs` の `BASELINES`、今の基準は `CURRENT_BASELINE`。

### v3 と v2 の違い（3シード×13方針＝39周）

- 遊びの結果が違うのは39周のうち33周。**Day1 の判定と売上はどの周も同じ**（自動試遊は3杯目も GOOD にしている）。
- 3杯目に使う材料がココナッツミルクから薬膳ナンプラーだれに替わり、Day1 の終わりの在庫がずれる（ココナッツミルク 2→3、薬膳だれ 4→3。33周）。
  その差が、あとの日の傷み・仕入れ・残りの在庫・断る回数に少しずつ広がった。
- **最終現金が変わったのは11周、平均 −11.1**（39周の平均 1301.2 → 1290.1。いちばん大きい減りは −121）。

| 方針 | 最終現金の差（シード1,2,3） | ほかの変化 |
|---|---|---|
| forecast_good | 0, −45, −25 | シード2で評判 −2、GOOD以上 −1杯 |
| always_large | 0, −45, −25 | シード2で評判 −2、GOOD以上 −1杯 |
| no_split | 0, −45, 0 | シード2で評判 −2、GOOD以上 −1杯 |
| forecast_favorites | 0, 0, −25 | |
| always_small | 0, 0, −25 | |
| favorite_oracle | −25, 0, −25 | |
| two_failures | −121, 0, −25 | シード1で評判 −4、GOOD以上 −5杯・BAD +2杯 |
| forecast_mistakes・strength_neglect・decline_one_group・decline_once | すべて0 | 在庫・傷み・仕入れなどの途中の数だけ違う |
| bare_broth・cheap_valid | すべて0 | 違いなし |

評判 −2 の3周（シード2）は、どれも7日目にターニャ婆へ味の材料の無い椀しか作れず、断る回が1回増えた。
（比べない項目の違い：クリックの回数と Day1 の途中の残高〔初日セットのあと・鍋の素を選んだあとが50低い〕は、文の差し替え〔`19455b9`〕から。）

## 新しい基準を作るとき

1. 照合で遊びの結果に違いが出たら、まず止めて、どの項目がどう違うかを報告する（基準は上書きしない）。
2. それが**意図した変更**（注文の札・日程・数値など、決めて変えたもの）だと決まったら、**新しい基準を作る**（v4、v5…）。
   - 変更をコミットしたあと、作業ツリーに変更が無い状態で、照合と同じ条件（3シード×13方針・reach_true・運営費75）で自動試遊を流し、
     `playthrough_baseline_v<N>.json` として保存する（ファイルの `commit` に元にしたコミットが入る。`tracked_changes` が空であること）。
   - `compare_baseline.mjs` の `BASELINES` に足し、`CURRENT_BASELINE` を替える。
   - この文書の「基準の一覧」に、作った日・元にしたコミット・条件・理由と、前の基準との違いの要約を書き足す。
   - 新しい基準と照合して、全周一致することを確かめる（自動試遊は乱数の種が決まっているので、同じコミットなら毎回同じ結果になる）。
3. 意図しない変化（知らないうちに決まりが変わった）なら、基準は作らずに原因を直す。

## 経緯

- 2026-11-09 まで：v2 と全キー一致（`clicks`・`steps`・`actions`・`rows` を含む）で比べていた。
- 中身U1（1日目の本番の文）で会話の行が増え、水道代を朝の会話（梁伯の場面）で払うようにしたので、クリックの回数と Day1 の途中の残高が
  変わった（遊びの結果は同じ）。あわせて、自動試遊が食後の行（`part` が `body`・`after_bill`・`closing`）でも鍋を直していたのをやめた
  （`playthroughs.gd` の `AFTER_MEAL_PARTS`。その客の椀はもう出し終えていて、空の鍋に水とだしを足して次の日の仕入れまで変わっていた）。`e77237d`。
- 同じ日、阿強の3杯目の札の変更（`307b769`）を意図した変更として受け入れ、基準 v3 を作った。
