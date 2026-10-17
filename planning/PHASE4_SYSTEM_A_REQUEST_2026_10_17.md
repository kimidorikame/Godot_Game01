# システム整理A（小さな修正＋日番号の直書きの置き換え）実装plan作成依頼

対象：Claude Code（実装担当）。本書は「何を・どこまで」の要件定義であり、実装手順書ではない。まず本書を読み、**実装plan（変更するファイル・関数・データ形式・テストの一覧・コミットの分け方）**を提示してから着手すること。

## 0. 位置づけ

しまさんの方針：**システム部分を先に作り、会話（脚本）など素材が要るものは後に回す**。その第一弾として、素材が要らず、動作を変えない（または見た目だけが変わる）整理を1回の依頼にまとめる。

| 区分 | 内容 | 性格 |
|---|---|---|
| **F** | F1：客の表示名がIDのまま表示される。F2：再挑戦で`balance_log.jsonl`が同じ日を二重に記録する | 小さな修正 |
| **E** | `DESIGN.md`10.9の残り：新人警官の市場会話（`day_count == 2`）・チンピラの場所代・市場の解禁日・需要経路の切替 | **動作を変えないデータ化** |

完了済み：3-1〜3-8、4-1〜4-4（4-4b-2まで）。`CURRENT_SPEC.md`は4-4b-2時点（コミット`392df81`）。テストは1388件。

**終わりの条件（共通）**：Eは既存データで**動作が変わらない**（会話・要求・金額・乱数の消費順が同一）。自動試遊（3シード×13方針）は4-3の結果（`playthrough_results_regulars.json`）と**完全一致**する。Fは§2.1・§2.2のとおり。テストスイートの最後は`return c.finish()`にする。

**環境制約**：本書の作成者（このチャットのAI）はGodotを実行できない。以下は静的解析（コード読解・grep）だけで書いている。実装後は必ず実機で`tests/run_tests.gd`を実行し、全件成功を確認すること。

---

## 1. コミットの分け方（提案。planで変えてよい）

1. **コミット①：F（表示名・balance_log）**
2. **コミット②：E（日番号の直書きの置き換え）**。4項目あるので、planで更に分けてよい。

---

## 2. F：小さな修正

### 2.1 F1：客の表示名

**現状**：`data/customers/<id>.json`は`{is_mob, favorite, wanted_tags}`で、表示名が無い。名前あり客の名前が画面にIDのまま（`delivery_man`など）出る箇所がある。モブは`data/mobs/*.json`の`"name"`を`Day1Events.mob_display_name()`で読んでいる（未知の種類はid自体を返す）。

**決めてほしいこと**
- 客プロフィールに`"name"`（表示名）を足し、`ScheduleData.customer_display_name(id)`のような読み口を作る案を基本とする（モブの`mob_display_name`と並べる）。未知のid・`"name"`なしはid自体を返す（クラッシュしない）。
- IDがそのまま画面に出ている箇所を**洗い出して表にする**（`debug_panel.gd`の本文・計器盤・STATE VIEWER・予告メモ・結果画面の物語欄（`Result.format_story`）・場面のGREET/TEXTの`customer`など）。**どこまで置き換えるか**（プレイヤーに見える文面だけを置き換え、STATE VIEWERなどのデバッグ表示はIDのままにする、など）を推奨付きで示す。
- 表示名の仮の値（しまさんが後で変えられる仮データ）：`delivery_man`＝配達員、`thug`＝チンピラ、`officer`＝新人警官、`granny`＝老婆、`hooker`＝夜の女、`streamer`＝配信者。既存の仮台詞（例：`チンピラ（MELLOW/GENTLE）`）の書き方に合わせて、衝突しないようにする。
- 会話の文言（場面データの`greet`・`reactions`）は**変えない**。表示名を使うのは、システムが組み立てる文面だけ。

**テスト**：全常連の表示名が空でない。未知idはid自体を返す。置き換えた箇所の文面に、IDが残っていない（プレイヤーに見える範囲）。

### 2.2 F2：再挑戦での`balance_log.jsonl`の二重記録

**現状**：`DebugPanel._on_day_ending()`が日の終わりに`_append_balance_log_file(log_entry)`で`user://balance_log.jsonl`へ1行追記する。再挑戦（4-1：朝の保存から戻す）で同じ日をやり直すと、同じ日が2行以上になる。

**決めてほしいこと（選択肢を比較し、推奨を示す）**
- (a) ログには再挑戦の履歴を残す。各行に`attempt`（その周回の何回目か）などの追加キーだけ足し、集計側が最後の行を取れるようにする。**既存キーは変えない**（互換性のため追加のみ）。
- (b) 再挑戦で戻した朝より後の日の行を、ファイルから取り除く。
- (c) 現状維持＋コメントとして仕様に書く。
- 試遊（`planning/playtest_2026_10_11/`）や分析スクリプトが`balance_log.jsonl`を読んでいるか、読んでいるなら二重行の影響を受けるかを確認して報告すること。
- 結果画面の集計（`GameState.day_records`）は朝の辞書に入っていて、再挑戦で戻るので二重にならない（4-2）。ファイルだけの問題であることを確認すること。

**テスト**：決めた方式での、再挑戦後のファイルの状態。

---

## 3. E：日番号の直書きの置き換え（動作を変えない）

`DESIGN.md`10.9の残り。現行コードで確認した状態：

| 場所 | 今の判定 | 置き換え先（案） |
|---|---|---|
| `day1_events.gd:178` 新人警官の市場会話（`_OFFICER_MARKET`） | `day_count == 2` | 場面の前提（場面データの`market_talk`） |
| `day1_events.gd:999` チンピラの場所代 | `customer_id == "thug" and is_collection_day()` | `bills[].scene` |
| `day1_events.gd:231` 市場の解禁（`day2_unlocked`） | `day_count >= 2` | `Rules.market_open_from_day()`（宣言済み・未使用） |
| `day1_events.gd:405` 需要経路の切替（`use_demand_system`） | `day_count > 1` | `day_overrides`（固定モブ）とDayPlan |

（配達員の3杯専用列は4-4aで場面idの判定にした。`is_collection_day()`・`total_demand_today()`・`FINAL_DAY`は3-1・3-5でデータ化済み。）

### 3.1 新人警官の市場会話

**現状**：PREPの市場の前に、`day_count == 2`のときだけ`_talk("officer", _OFFICER_MARKET)`を差し込む。`_OFFICER_MARKET`は仮台詞1行（`警官（市場・要求タグ: SOUR/BITE）`）で、officerの初登場（`officer_01`＝Day2の宵の口）に対応している。

**基本案**：場面データに`market_talk`（行の配列）を足す。PREPの市場の前に、**今日のDayPlanの枠にある場面**（`today_plan`が今日のものならその枠の`episode_id`。無ければ`ScheduleData.regular_slots(day)`の既定。`Day1Events.episode_id_of()`と同じ引き方）が`market_talk`を持つなら、その行を差し込む。`officer_01.json`に現行の1行を移し、`_OFFICER_MARKET`と`day_count == 2`の判定を消す。Day2のイベント列は**現行と同一**（`_talk("officer", …)`と同じ形・同じ位置）。

**確認・決めてほしいこと**
- `prep_after_tier_events()`が呼ばれる時点でDayPlanがあるか（WAKEで作る）。DayPlanが無いテスト経路での挙動（既定の枠へ落とす）。
- `market_talk`を持つ場面が同じ日に複数あるときの扱い（枠順に全部出す、など。現状は1つだけ）。
- 一度見た場面の`market_talk`を再び出すか（`seen_episodes`との関係。今は静的な割り当てで1日だけなので影響なし。推奨を示す）。
- 場面データの検証テスト（`tests/episode_data_test.gd`）に`market_talk`の型検査を足す。

### 3.2 チンピラの場所代

**現状**：`_customer_extra_events("thug")`が`GameState.is_collection_day()`のとき、`PAY`（`amount: GameState.RENT_PRICE`, `kind: "rent"`）を返す。`week7.json`の`bills`には`{id:"rent", amount:90, days:[1], scene:"thug"}`があり、`scene`は宣言だけで未使用。

**基本案**：`Rules.bills()`から「`scene`がこの客のidで、`days`に今日を含む請求」を引いて`PAY`を作る。客idの直書き（`"thug"`）を消す。**金額**は現行の`RENT_PRICE`と請求の`amount`が同じ値（90）であることを確認し、どちらを正とするか（推奨：`bills[].amount`）を示す。`DebugPanel`の`is_collection_day()`参照箇所（約346・712・1499行）は、水道代など別の用途もあるので、そのままでよいか確認して表にする。

**テスト**：`days`をテスト用に差し替えて、徴収日にだけ`PAY`が出る。`scene`が別の客の請求は出ない。

### 3.3 市場の解禁日

`day2_unlocked := day_count >= 2`を`Rules.market_open_from_day()`による判定へ置き換える（変数名・ラベル「訪問済み」の出し分けも整合させる）。値は2のまま。

### 3.4 需要経路の切替

`use_demand_system`の`GameState.day_count > 1`が、Day1の固定モブ（`day_overrides."1".mobs`）と**重複していないか**を調べる。Day1に固定モブがあるなら`use_fixed_mobs`で既に除外されるので、`day_count > 1`は不要かもしれない。**消せるなら消す／残すなら理由**を示す。自動試遊が一致することが条件。

---

## 4. 新規・書き換えテスト（最低限）

- F1：§2.1のテスト。F2：§2.2のテスト。
- E：新人警官の市場会話がDay2にだけ出る（現行とイベント列が同一。`tests/fixtures/customer_events_4_3.json`と同種の記録での照合）。`market_talk`を持たない場面では出ない。チンピラの場所代がDay1にだけ出る。Day2以降の市場解禁。
- **自動試遊（3シード×13方針）が4-3の結果と完全一致**（日別・現金・評判・インシデント・結果画面の集計まで差分0）。
- 書き換える既存テストと理由の一覧（`day_count == 2`を前提にしているテストなど）。

## 5. 注意

- **Eは動作を変えない**。差が出たら原因を調べて報告すること（数値は調整しない）。
- 範囲外：会話の文言、`sets_facts`・`choices`・`body`・`closing`・`must_info`（次のC）、ニュース（D）、レシピ保存・会話ログ（B）、修繕基金（A）、`_OFFICER_AFTER`・`_OFFICER_PAYMENT`のデータ化（本文の移し替えなので脚本の段階で）、配達員の3杯列（動かさない）。
- `BALANCE_REDESIGN_PLAN.md`・`BALANCE_REDESIGN_V2.md`・`planning/playtest_2026_10_11/runtime_data/`は未追跡のまま触らない。`DESIGN.md`の作業ツリー差分は改行だけの差分なのでコミットしない。コミットメッセージはファイル経由で作ること。
- 保存の版：場面データの`market_talk`は保存する状態を増やさない。版を上げる必要が出る場合は理由を示す。

## 6. 依頼のまとめ

1. 上記を踏まえ、変更するファイル・関数、F1の置き換え箇所の表と方針、F2の方式（比較と推奨）、E各項目の置き換えとテスト、コミットの分けを一覧にした実装planを提示してから着手する。確認事項はその旨を明記する。
2. コミットメッセージは「システム整理A: 内容」の形式。
3. 実装後、`tests/run_tests.gd`を実機で実行し、全件成功を確認して報告する。自動試遊（3シード×13方針）が**4-3の結果と完全一致**することを確認して報告する。
4. 完了後、`CURRENT_SPEC.md`の該当箇所を実装事実に合わせて更新する依頼を改めて出す（このチャット側で別途対応）。
