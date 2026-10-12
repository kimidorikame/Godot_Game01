# フェーズ4-4a（DayPlanが常連の日程を直接読む・客データを基本プロフィールと来店場面に分ける）実装plan作成依頼

対象：Claude Code（実装担当）。本書は「何を・どこまで」の要件定義であり、実装手順書ではない。まず本書を読み、**実装plan（変更するファイル・関数・データ形式・テストの一覧・コミットの分け方）**を提示してから着手すること（4-3までと同じ粒度・1手順＝1コミット）。

## 0. 前提と、4-4を二つに分けた理由

`DESIGN.md`10.10の4-4は「F5来店記録＋F6場面データと選び方＋注文カード」で、一度に変える範囲が大きい。そこで次のように分ける（しまさんと合意済み）。

| 手順 | 内容 | 性格 |
|---|---|---|
| **4-4a（本書）** | DayPlanが常連の日程を直接読む（4-3の互換層を消す）。客JSONの`"days"`を、基本プロフィールと来店場面（日番号キーなし）に分ける。日番号の直書き（10.9）のうち配達員の3杯専用列を置き換える | **動作を変えないデータ構造の整理**。試遊・テストの結果は4-3と同一になる |
| 4-4b（次回） | F5来店記録（`known_favorites`の置き換え）、F6場面の選び方（`requires`・`not_seen`）、前回の料理を読んだ2行、注文カード（いつもの／今日の頼み） | 動作が変わる |

完了済み：3-1〜3-8、4-1（F7）、4-2（結果画面）、市場の店の2行表示、4-3（常連の固定日程）。`CURRENT_SPEC.md`は4-3時点（コミット`fa5c910`）。テストは958件。運営費65。

**環境制約**：本書の作成者（このチャットのAI）はGodotを実行できない。以下は静的解析（コード読解・grep）だけで書いている。実装後は必ず実機で`tests/run_tests.gd`を実行し、全件成功を確認すること。

---

## 1. 対応箇所と終わりの条件

対応：`DESIGN.md`10.8.1（客JSONの`"days"`を基本プロフィールと来店場面に分け、日番号キーを使わない）・10.8.2（DayPlanの`slots`）・10.9（日番号の直書き）・10.10の4-4のうち、データ構造の部分。

**終わりの条件**：
1. 客データに日番号キーが無い（`"days"`が消える）。
2. DayPlanの各枠が`regular_id`と`episode_id`を持ち、客の会話は`episode_id`で引く。
3. 4-3の互換層（`compose_day_schedule`・`day_schedule`・`_pick_main`の`main_pool`分岐）が無い。
4. **動作が4-3から変わらない**：全日・全枠で、客のイベント列（会話・要求タグ・好物・servings・反応文）が4-3と同一。自動試遊（3シード×13方針）は4-3の結果と**完全一致**する。

## 2. 現状（静的解析で確認済み）

### 2.1 客データ（`data/customers/*.json`）
`{"is_mob","favorite","days":{"<日>":{"greet","wanted_tags","reactions","servings"}}}`。`delivery_man`だけ`"wanted_tags"`をトップレベルに持つ。日番号キーを持つ日は、hooker＝3〜7、officer＝2〜7、streamer＝4〜7、thug＝1、granny＝1、delivery_man＝1。`ScheduleData.customer_data(id, day)`が`days[day]`を取り、無ければ`days["1"]`へフォールバックする（4-3で確認した「13枠は当日分、8枠はDay1の内容」の正体）。

### 2.2 客のイベント列の組み立て（`scripts/day1_events.gd`）
- `customer_events(customer_id)`：`customer_id == "delivery_man" and GameState.day_count == 1`なら`_delivery_man_events()`（3杯専用列）。それ以外は`_customer_flavor()`→汎用の流れ。
- `_customer_flavor(customer_id, mob_count)`：モブは`today_plan["mob_instances"]`から、常連は`ScheduleData.customer_data(customer_id, GameState.day_count)`から読む。**日番号で引いている**ので、DayPlanが持つ枠の情報とつながっていない。
- `_customer_total_servings()`・`Forecast`（`forecast.gd`）も`customer_data`／`customer_events`をその日の番号で読む。

### 2.3 DayPlan（`scripts/day_planner.gd`）と4-3の互換層
`DayPlanner.build()`→`Day1Events.customer_schedule()`→`ScheduleData.day_schedule(day)`（`compose_day_schedule`が`week7_regulars.json`と`mob_rules.json`から旧形式`{"slots":[{name,main,mob}]}`を組み立てる）。`today_plan["slots"]`は`[{name, customers:[客id|"mob#N", …]}]`。OpenControllerはこれを不透明な文字列として読む。`_pick_main`の`main_pool`分岐は、4-3以降どの枠でも使われない。

### 2.4 保存
`today_plan`は`MorningSave`で保存・復元される（4-1）。封筒の版は2。`is_valid()`が`today_plan`の型を検査する。

## 3. 決めてほしいこと（planで方針を示す。迷う点は選択肢を並べて推奨を添える）

**論点A：データ分割の形。** 次を基本案とし、変える場合は理由を示す。
- `data/customers/<id>.json`（基本プロフィール）：`is_mob`・`favorite`・`wanted_tags`（基本注文。10.5.1「常連の基本注文は日によって変えない」）。
- `data/episodes/<客>/<episode_id>.json`（来店場面）：`id`・`customer`・`greet`・`reactions`・`servings`。10.8.6の他のキー（`requires`・`callback`・`body`・`choices`など）は**足さない**（4-4b）。
- **先に確認すること**：現行の`days`の各エントリの`wanted_tags`が、客ごとの基本注文と全日一致するか。一致するなら`wanted_tags`はプロフィールだけに置く。一致しない日があれば、その旨を報告し、場面側に残す案を示す。

**論点B：episode_idの割り当て。** `week7_regulars.json`の各枠に`episode_id`を足す（21枠）。現行の13枠（当日のキーを持つ枠）はそれぞれ別の場面、8枠（Day1の内容へフォールバックしていた枠：配達員Day2・4・6、チンピラDay2・5・6、老婆Day3・7）はそのDay1の場面と**同じepisode_idを共有する**案を基本とする。命名と、21枠→episode_idの対応表をplanに載せること。4-4bで`not_seen`の選び方を入れると、共有した場面は「既読のとき別の場面」を選べる必要が出るが、4-4aでは静的な割り当てでよい（先取りしない）。

**論点C：DayPlanの枠の形。** `today_plan["slots"]`の各枠に`regular_id`と`episode_id`を足す。**OpenControllerが読む`name`・`customers`は変えない**（`customers`は`[regular_id, "mob#N", …]`のまま）。`mob_instances`も今のまま（10.8.2の`mobs`への移設は範囲外）。`regular_id`が空の枠（想定外）が安全に扱えることを確認すること。

**論点D：イベント列の組み立てがepisode_idを引く経路。** 現状は`customer_events(customer_id)`が日番号で引く。次のどれにするか、planで推奨を示す。
- (1) `customer_events(customer_id)`の内部で、`today_plan`から「この客の今日の枠」を引いて`episode_id`を得る。
- (2) `customer_events(customer_id, episode_id)`と引数を足し、呼び出し側（OPENの客キュー）が枠から渡す。
- いずれの場合も、`Forecast`・`_customer_total_servings`・`Result`など、`customer_data`を日番号で読んでいる箇所を洗い出し、置き換え先を表にすること。`today_plan`が空のとき（テストがWAKEを経由せずに呼ぶ場合）の挙動も決める。

**論点E：配達員の3杯専用列。** `customer_events`と`_customer_flavor`の2箇所の`day_count == 1`を、日番号ではなくepisode_id（例：配達員の最初の場面）で判定する形に置き換える（10.9）。3杯列そのもの（`_delivery_man_events()`のGDScript）は動かさない。会話のデータ化は4-4b以降。

**論点F：互換層と旧経路の撤去。** `compose_day_schedule`・`day_schedule`・`_pick_main`の`main_pool`分岐・`ScheduleData._FALLBACK_DAY`（客データ用）を消す。`customer_schedule()`は`week7_regulars.json`の枠を直接読む。次を示すこと。
- 4-3の互換層に依存しているテスト・コード（`schedule_test.gd`・`reputation_demand_test.gd`・`regular_schedule_test.gd`など）の一覧と、書き換え方針。
- 定義の無い日（Day8以降）の扱い。最終日が7なので実プレイでは起きない。クラッシュしない最小の挙動（例：Day1と同じ枠を返す／空の枠を返す）を決め、理由を書く。

**論点G：保存との整合。** 枠のキーが増えるので、4-3以前の保存（`regular_id`・`episode_id`なし）をそのまま読むと、復元した朝の客の会話が引けなくなる。次を決めること。
- 封筒の版を3に上げ、古い保存は読めない扱い（新規ゲーム）にする案を推奨とする（4-2で2に上げたのと同じ流儀）。別案があれば比較する。
- `MorningSave.is_valid()`に新キーの型検査を足すか。

## 4. やること（コミットの分け方の提案）

planで変えてよい。

1. **コミット①：新データ構造を足す。** `data/episodes/…`と基本プロフィールを作り、`week7_regulars.json`に`episode_id`を足し、`ScheduleData`に新しい読み込み（`episode_data`など）を足す。**旧経路はまだ使う**。新旧の内容が一致することのテスト（全日・全客）を追加する。
2. **コミット②：切り替えと撤去。** DayPlan・`customer_events`・`Forecast`をepisode_id経由にし、互換層・`days`・旧フォールバックを消し、保存の版を上げる（論点G）。テストの書き換えは理由をコミットメッセージに書く。

## 5. 新規テスト（最低限）

- **同一性の保証（最重要）**：切り替え前の`customer_events`（全常連×Day1〜7）の出力を、切り替え後と比較して一致する。切り替え前の値は、コミット①の時点で定数または一時ファイルに記録して比べてよい（記録は①のテストに含め、②で参照する）。
- 21枠それぞれが有効な`episode_id`を持ち、対応する場面ファイルが存在し、`customer`が`regular_id`と一致する。
- `customer_data`・場面データに日番号キーが無い。
- DayPlanの枠が`regular_id`・`episode_id`を持ち、`customers`の先頭が`regular_id`。再挑戦（4-1）で同じDayPlanに戻る。
- 配達員のDay1は3杯列、Day2・4・6は通常の1杯（日番号ではなくepisode_idで分かれる）。
- 古い保存（版2）が読めない扱いになる、または互換に読める（論点Gの結論どおり）。
- 既存958件のうち書き換えるテストと理由の一覧。

## 6. 注意

- **動作を変えない**。会話の文言・要求・好物・servings・反応文・乱数の消費順を変えない。差が出たら、原因を調べて報告すること（数値は調整しない）。
- 範囲外：来店記録（F5）・`known_favorites`の置き換え・場面の選び方（`requires`・`not_seen`）・`today_request`・注文カード・聞き直し・新人警官の市場会話の日番号（`day_count == 2`）・チンピラの場所代（`is_collection_day()`）。4-4b以降。
- 後から4-4bで`requires`などを足せる形にしておくこと（場面は辞書、枠は辞書）。
- `BALANCE_REDESIGN_PLAN.md`・`BALANCE_REDESIGN_V2.md`・`planning/playtest_2026_10_11/runtime_data/`は未追跡のまま触らない。`DESIGN.md`・`CURRENT_SPEC.md`の作業ツリー差分は改行だけの差分なのでコミットしない。

## 7. 依頼のまとめ

1. 上記を踏まえ、変更するファイル・関数、データ形式（論点A・B）、DayPlanの枠（論点C）、組み立ての経路（論点D・E）、撤去の範囲（論点F）、保存との整合（論点G）、テスト、コミットの分けを一覧にした実装planを提示してから着手する。確認事項はその旨を明記する。
2. コミットメッセージは「4-4a: 内容」の形式。
3. 実装後、`tests/run_tests.gd`を実機で実行し、全件成功を確認して報告する。自動試遊（3シード×13方針）は**4-3の結果と完全一致**することを確認して報告する（`playthrough_results_regulars.json`との照合。30シードの再実行は不要）。
4. 完了後、`CURRENT_SPEC.md`の該当箇所（客データの構成・DayPlanの枠・保存の版）を実装事実に合わせて更新する依頼を改めて出す（このチャット側で別途対応）。
