# フェーズ4-4b-1（F5：来店記録）実装plan作成依頼

対象：Claude Code（実装担当）。本書は「何を・どこまで」の要件定義であり、実装手順書ではない。まず本書を読み、**実装plan（変更するファイル・関数・保存項目・テストの一覧・コミットの分け方）**を提示してから着手すること（4-4aまでと同じ粒度・1手順＝1コミット）。

## 0. 前提と、4-4を細かく分けた理由

`DESIGN.md`10.10の4-4（F5来店記録＋F6場面データと選び方＋注文カード）は大きいので、次のとおり三つに分けている（しまさんと合意済み）。

| 手順 | 内容 | 性格 |
|---|---|---|
| 4-4a（完了） | DayPlanが日程を直接読む・客データを基本プロフィールと来店場面に分ける | 動作を変えない整理 |
| **4-4b-1（本書）** | F5来店記録（`known_favorites`の置き換え）。**記録するだけで、台詞や選び方はまだ変えない** | 動作を変えない（好物の開示は従来どおり） |
| 4-4b-2（次回） | F6場面の選び方（`requires`・`not_seen`）・前回の料理を読んだ2行・注文カード（いつもの／今日の頼み）・聞き直し | 動作が変わる |

完了済み：3-1〜3-8、4-1（F7）、4-2（結果画面）、4-3（常連の固定日程）、4-4a。`CURRENT_SPEC.md`は4-4a時点（コミット`2bf254e`）。テストは1211件。運営費65。

**環境制約**：本書の作成者（このチャットのAI）はGodotを実行できない。以下は静的解析（コード読解・grep）だけで書いている。実装後は必ず実機で`tests/run_tests.gd`を実行し、全件成功を確認すること。テストスイートの最後は`return c.finish()`にする（4-4aで決めたルール）。

---

## 1. 対応箇所と終わりの条件

対応：`DESIGN.md`10.8.5（F5来店記録）・10.8.7（朝の保存に来店記録を含める）・10.10の4-4のうちF5の部分。

> 10.8.5：既存の`known_favorites`を置き換える。7日間を通して残し、新しい周で消す。
> ```
> customer_memory[customer_id] = {
>   favorite_known: bool,
>   visits: [ { day, slot, served, grade, ingredients, request_honored, choices } ],
>   facts: { ... },          # 次回へ残す事実（1場面につき1〜2個まで）
>   seen_episodes: [ ... ]
> }
> ```
> 好感度のような数値は持たない。「何を出したか」「何を選んだか」「何を約束したか」の事実だけを残し、台詞の分岐はそれを読む。

**終わりの条件**：
1. `GameState.customer_memory`が、来店のたびに事実（日・枠・提供したか・評価・入れた具材・見た場面id）を記録する。
2. `known_favorites`が`customer_memory[id].favorite_known`に置き換わり、**好物の開示の挙動は従来と同一**（初回は判定に使うが表示しない、退店時に初めて「知った」扱い、配達員は3杯すべて終えた退店時、など）。
3. 来店記録が朝の保存・再挑戦・1枠セーブ（4-1）で往復し、新しい周（`reset_for_new_game()`）で消える。
4. **動作が変わらない**：自動試遊（3シード×13方針）が4-3／4-4aの結果と**完全一致**する。

## 2. 現状（静的解析で確認済み）

### 2.1 `known_favorites`
- `game_state.gd`：`var known_favorites: Dictionary = {}`（客id→true）。`knows_favorite(id)`・`mark_favorite_known(id)`。`SAVED_FIELDS`に入っていて、`reset_for_new_game()`で空になる。`morning_save.gd`が型（Dictionary）を検査。
- 書く側：`debug_panel.gd`の`_serve_customer()`（単発提供。`judged`かつ好物ありなら即`mark_favorite_known`）と`_flush_visit_tally()`（集計客＝配達員。退店時に1回だけ）。
- 読む側：`debug_panel.gd`の予告メモ（`knows_favorite(cid)`なら「／好物:…」を出す）、検証用の`favorite_true`表示、`result.gd`の`format_story()`（4-2。好物を知った客のidを物語欄に出す）、結果画面の呼び出し（`GameState.known_favorites.keys()`）。
- テスト：`first_favorite_test.gd`・`result_flow_test.gd`・`save_file_test.gd`・`save_state_test.gd`が`known_favorites`／`knows_favorite`／`mark_favorite_known`を参照。

### 2.2 来店の記録がすでに残っている場所
- `_visit_tally`（`debug_panel.gd`）：1人の客の杯ごとの集計（客id・売上・杯数・判定結果ごとの杯数・好物の保留）。`_flush_visit_tally()`が退店時に`GameState.record_served(record)`へ1件として積み、日次ログ（`_log_quality_counts`）へ合算する。団体客（モブ）の分割提供では`ordered_servings`・`unserved_servings`・`declined`も付く。
- `GameState.served`：その日の提供記録（日が変わると消える）。`Result`が`day_records`（4-2。日ごとの集計）から累計を出す。これらは**日の集計**であり、客ごとの「前回何を出したか」を持たない。

### 2.3 まだ無いもの
客ごとの履歴（日・枠・評価・入れた具材）、見た場面id（`seen_episodes`）、約束・選択（`facts`・`choices`）。後二者は場面データの選び方（4-4b-2）・選択肢（4-5以降）が使う。

## 3. 決めてほしいこと（planで方針を示す。迷う点は選択肢を並べて推奨を添える）

**論点A：`customer_memory`の形と、どこまで今回入れるか。** 10.8.5の形を基本とする。今回記録する項目は次を基本案とし、変える場合は理由を示す。
- `favorite_known: bool`（`known_favorites`の置き換え）
- `visits: [{day, slot, served, grade, ingredients, episode_id}]`
  - `served`：提供した杯数（0なら未提供・断り）。`grade`：評価（`GREAT`／`GOOD`／`OK`／`BAD`／未提供は空）。団体・配達員のように複数杯の評価がある客は、**何を代表値にするか**（最も悪い評価／最後の評価／杯ごとの配列など）をplanで決める。
  - `ingredients`：その客に出した椀に入れた具材・調味料のid（`current_bowl`の`additions`から）。複数杯なら杯ごと（配列の配列）か合算かを決める。
  - `episode_id`：4-4aの`episode_id_of(customer_id)`が引いた場面id（見た場面）。
  - `request_honored`・`choices`は**今回は足さない**（4-4b-2以降で注文カード・選択肢を入れるときに足す。足しやすい辞書にしておく）。
- `seen_episodes: [episode_id…]`（その客が見た場面id。重複なし）
- `facts: {}`（空のまま。足す手段だけ用意し、今回は使わない）
- **モブは記録しない**（`mob#N`のインスタンスidは来店記録の対象外。名前あり客だけ）。

**論点B：記録のタイミング。** 現状の`_flush_visit_tally()`（退店時に客1人分を確定）に載せるのが自然だが、ここは**呼ばれない経路**（途中で閉店・ゲームオーバー・提供前に断る）もある。次を調べ、「提供しなかった来店」も`served: 0`で記録するかをplanで決めること（4-4b-2の「前回の料理を読んだ2行」は、前回提供しなかった場合も読む必要がある）。
- 客を断る（`[客を断る]`）・注文を断る・早仕舞い・提供できず退店、それぞれで記録が残るか。
- 配達員（`aggregate`）の記録は退店時に1回。

**論点C：`known_favorites`の置き換え方。** 次のどちらかを推奨付きで示すこと。
- (1) `known_favorites`を削除し、`knows_favorite`・`mark_favorite_known`を`customer_memory`経由に書き換える（呼び出し側の関数名は維持し、読む側・書く側のコードは最小の変更にする）。
- (2) `known_favorites`を残して`customer_memory`と二重管理する（**非推奨**。二重管理は食い違いの元）。
- `result.gd`の`format_story`への渡し方（`known_favorites.keys()`）の置き換え先も示す。
- 好物の開示のタイミング（`_serve_customer`の即時／`_flush_visit_tally`の退店時）は**変えない**。

**論点D：保存。** `customer_memory`を`SAVED_FIELDS`に入れ、`known_favorites`を外す。封筒の版を3→4に上げ、古い保存（版3以前）は読めない扱い（新規ゲーム）にする案を推奨とする（4-2・4-4aと同じ流儀）。`MorningSave.is_valid()`に型検査（辞書・各客の`favorite_known`はbool、`visits`・`seen_episodes`は配列など）を足す。**JSONに通すと整数が小数になる**問題は、保存が`var_to_bytes`なので起きないが、テストで往復を確認すること。**再挑戦で戻した朝より後の来店記録を持ち越さない**（4-1・4-2で`morning_snapshots`と`day_records`を扱ったのと同じ問題）ことを確認する。

**論点E：新しい周での初期化。** `reset_for_new_game()`で`customer_memory`を空にする。日次リセット（`reset_for_new_day()`）では消さない（7日間を通して残す）。`save_state_test`が要求する「新しいGameState変数は`SAVED_FIELDS`か`TRANSIENT_FIELDS`に分類する」に従う。

**論点F：結果画面（4-2）との関係。** `format_story`は今`known_favorites`のidだけを使う。`customer_memory`から読む形に置き換えるが、**表示される文言は変えない**。物語欄の本文（来店記録を読んだもの）は4-8の範囲。

## 4. やること（コミットの分け方の提案）

planで変えてよい。

1. **コミット①：`customer_memory`の器と記録。** `GameState.customer_memory`・記録用の関数・`CustomerMemory`静的クラス（planで要否を決める）を足し、来店のたびに`visits`・`seen_episodes`を記録する。**`known_favorites`はまだ残す**（論点Cの(1)の途中経過として、`customer_memory[id].favorite_known`と`known_favorites`が常に一致することをテストで確認する）。保存・新しい周の初期化もここで入れる（版4）。
2. **コミット②：`known_favorites`の撤去。** `knows_favorite`・`mark_favorite_known`を`customer_memory`経由にし、`known_favorites`・その保存・`format_story`の呼び出しを置き換える。既存テストの書き換えは理由をコミットメッセージに書く。

## 5. 新規テスト（最低限）

- 名前あり客の来店ごとに`visits`が1件増える。`day`・`slot`・`served`・`grade`・`ingredients`・`episode_id`が正しい。モブは記録されない。
- 提供しなかった来店（断り・早仕舞い等）の扱い（論点Bの結論どおり）。
- 配達員（3杯）の記録が、退店時に1件。好物の開示が退店時（1・2杯目の途中では`favorite_known`がfalseのまま）。**4-4a以前と同じ**。
- `seen_episodes`が重複しない。
- 好物の開示の挙動が従来と同一（`first_favorite_test`が無修正、または最小の修正で通る）。
- 保存の往復：`to_dict`→`from_dict`・ファイルを通した往復で`customer_memory`が一致する。深いコピー（戻した後に元の辞書を書き換えても影響しない）。再挑戦で戻した朝より後の記録を持たない。新しい周で消え、日次リセットでは消えない。
- 古い保存（版3）が読めない扱いになる。
- `format_story`の出力が従来と同一。
- 既存1211件のうち書き換えるテストと理由の一覧。

## 6. 注意

- **動作を変えない**。台詞・反応・判定・乱数の消費順・好物の開示タイミングを変えない。差が出たら原因を調べて報告すること（数値は調整しない）。
- 範囲外：場面の選び方（`requires`・`not_seen`）・前回の料理を読んだ2行・注文カード・今日の頼み・聞き直し・`choices`・`facts`の利用・`request_honored`。4-4b-2以降。新人警官の市場会話（`day_count == 2`）とチンピラの場所代の日番号判定も同様。
- 好感度のような数値は持たない（10.8.5）。
- 乱数を使わない（記録は事実の保存だけ）。
- `BALANCE_REDESIGN_PLAN.md`・`BALANCE_REDESIGN_V2.md`・`planning/playtest_2026_10_11/runtime_data/`は未追跡のまま触らない。`DESIGN.md`・`CURRENT_SPEC.md`の作業ツリー差分は改行だけの差分なのでコミットしない。

## 7. 依頼のまとめ

1. 上記を踏まえ、変更するファイル・関数、`customer_memory`の形と記録する項目（論点A）、記録のタイミングと提供しなかった来店の扱い（論点B）、置き換え方（論点C）、保存（論点D）、新しい周の初期化（論点E）、結果画面との関係（論点F）、テスト、コミットの分けを一覧にした実装planを提示してから着手する。確認事項はその旨を明記する。
2. コミットメッセージは「4-4b-1: 内容」の形式。
3. 実装後、`tests/run_tests.gd`を実機で実行し、全件成功を確認して報告する。自動試遊（3シード×13方針）は**4-3の結果と完全一致**することを確認して報告する（`playthrough_results_regulars.json`との照合。30シードの再実行は不要）。
4. 完了後、`CURRENT_SPEC.md`の該当箇所（来店記録・好物の開示・保存の版）を実装事実に合わせて更新する依頼を改めて出す（このチャット側で別途対応）。
