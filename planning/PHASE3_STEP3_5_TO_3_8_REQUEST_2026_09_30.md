# フェーズ3 続き（3-5〜3-8）実装plan作成依頼

対象：Claude Code（実装担当）。本書は「何を・どこまで」の要件定義であり、実装その
ものの手順書ではない。まず本書の内容を読み、各手順（3-5〜3-8）ごとに**実装plan（変更
するファイル・関数・テストの一覧）**を作成してからコードへ着手すること
（`DESIGN.md`10.10「1ステップ＝1回の依頼」の粒度を踏襲。3-5→3-6→3-7→3-8の順で、
1手順＝1コミットとする）。

## 0. 前提（F1〜F4は実装済み）

`DESIGN.md`10.10「フェーズ3」のうち3-1〜3-4は完了している。

| 手順 | 内容 | コミット |
|---|---|---|
| 3-1 | F1：キャンペーン設定の器（`Rules`／`data/campaigns/week7.json`） | `2cb5ab1` |
| 3-2 | F2：DayPlan（`DayPlanner`／`GameState.today_plan`） | `6fb2e24` |
| 3-3 | F3：SaleRule＋判定v2＋減点の事前表示＋断る操作（名前あり客・配達員） | `bcea23d` |
| 3-4 | F4：帳簿（`Ledger`）＋予算表示＋市場の個数・単価＋前日成績v2 | `220d9a4` |

上記4件は`DESIGN.md`10章の仕様との突き合わせレビュー済み（2026-09-30実施）。
`CURRENT_SPEC.md`にも実装事実として反映済み（コミット`50a7d3e`）。本書が依頼する
3-5〜3-8は、この4部品の上に積む。

**環境制約**：本書の作成者（このチャットのAI）はGodotエンジンを実際に実行できる
環境を持たない。全ての確認は静的解析（コード読解・grep・diff）のみで行っている。
実装後は必ず実機（Godotエディタ／`--headless`）で`tests/run_tests.gd`と自動試遊
（3-8）を実行し、静的解析では見えない実行時エラーが無いことを確認すること。

---

## 1. 3-5：Day1の9杯化・初日セット・朝の確保・持ち帰りの注文化

対応：`DESIGN.md`10.3.3〜10.3.7、10.9（該当4行）、10.11（該当3件）。
終わりの条件（10.10）：**Day1の定数・注文・予報・テストが9杯で一致する**。

### 1-a. Day1の客構成を9杯に揃える（10.3.3）

現状（`scripts/day1_events.gd` `customer_schedule()`／`_pick_mob()`）：
- 宵の口：`data/day_schedule.json`の`"mob": true`により`dock_workers`固定・人数は
  `GameState.DAY1_MOB_COUNT`（=4）。
- 夜半：`"mob": {"pool": [dock_workers, inn_clerk, market_porter]}`から`randi()`で
  1種抽選、人数は同じく`DAY1_MOB_COUNT`（=4）。
- 実際の合計杯数は13（配達員3＋港湾労働者4＋チンピラ1＋夜半モブ4＋老婆1）。
  需要定数`DAY1_DEMAND`（`game_state.gd`）は9だが、実際の注文数と食い違っている。

目標（10.3.3の表）：

| 時間帯 | 客 | 杯 | 要求 |
|---|---|---:|---|
| 宵の口 | 配達員（本人2杯＋持ち帰り1杯） | 3 | 本人=HOT＋POWER、持ち帰り=MELLOW＋GENTLE |
| 宵の口 | 港湾労働者2人 | 2 | HOT＋POWER |
| 夜半 | チンピラ | 1 | MELLOW＋GENTLE |
| 夜半 | 安宿の夜勤受付2人 | 2 | MELLOW＋GENTLE |
| 明け方 | 老婆 | 1 | SAVORY＋FILLING |

合計9杯。`data/campaigns/week7.json`の`day_overrides."1".mobs`に**既にこの数値が
宣言済み**（`[{slot:"宵の口", type:"dock_workers", count:2}, {slot:"夜半",
type:"inn_clerk", count:2}]`）だが、`customer_schedule()`側はまだこれを読んでいない
（F1実装時点では「宣言のみ・3-5で消費」という位置づけ。`rules.gd`のコメント参照）。

**変更が必要な箇所**：
- `day1_events.gd` `customer_schedule()`／`_pick_mob()`：Day1（`day_count==1`または
  `Rules.day_overrides(day)`に`mobs`がある日）は、`data/day_schedule.json`の
  `"mob"`フィールドやプール抽選を使わず、`Rules.day_overrides(1).mobs`の
  `{slot, type, count}`をそのまま使う経路に切り替える。`DAY1_MOB_COUNT`定数は
  Day1専用の一律人数としては使わなくなる（他の用途が無ければ削除、debug_mob_countの
  デフォルト値としての意味だけ残すなら要検討）。
- `data/day_schedule.json`の`"1"."夜半".mob`：`{"pool": [...]}`のままでもコード側が
  `day_overrides.mobs`を優先すれば実害は無いが、実データと設定が食い違ったままだと
  紛らわしいため、`{"count": 2}`固定へ書き換えるか、コメントで
  「day_overrides.mobsが優先されるため参照されない」旨を明記する。
- `game_state.gd` `total_demand_today()`：`if day_count == 1: return DAY1_DEMAND`を
  `Rules.day_overrides(day).get("fixed_demand", ...)`が存在すればそれを返す形に置き換える
  （10.9の表の該当行）。値そのものは9のまま変わらない。
- `game_state.gd` `is_collection_day()`：`day_count == 1`を`Rules.bills()`の
  各billの`days`に`day_count`が含まれるかで判定する形に置き換える（10.9の該当行。
  `bills[].days`は既に`week7.json`で`[1]`と宣言済み）。

### 1-b. 初日セット（無料在庫0・10.3.4）

現状：`day1_events.gd` `initial_inventory()`が
`{nam_prik_pao:10, coconut_milk:10, herbal_sauce:10, offal:4, meat_ball:6, tofu:5,
broken_wrapper:5}`を無料で積む（2026-09-26のDay1詰み対策で増量済み。この増量は
初日セット導入と同時に置き換えられ、意味を失う）。

目標：
- `initial_inventory()`の中身を空にする（無料在庫0）。
- Day1のPREP（WAKE直後）で、「いつもの分」を買う**固定購入イベント**（自由な買い物
  ではない）を1つ追加する。内訳（10.3.4）：ナムプリックパオ5個25／ココナッツミルク
  6個30／薬膳ナンプラーだれ5個25／肉団子6個48／豆腐6個48／割れた餃子皮3個18／
  だし1回16＝**合計210**。モツは含めない。
- 帳簿には`Ledger.record("kit", -210, ...)`のように`kit`カテゴリで記録する
  （`Ledger.CATEGORIES`に`kit`は既にF4で追加済み）。
- `week7.json`の`day_overrides."1".kit`が`"day1_kit"`という文字列で既に宣言済み
  （中身のレシピ自体はまだJSON化されていない）。この購入セットの内訳をどこに
  持たせるか（`week7.json`へ内訳ごと足すか、`day1_events.gd`に専用関数
  `day1_kit_goods()`を置くか）はClaude Codeの実装planで決めてよいが、**既存の
  `*_goods()`パターン（id/item/count構造）を踏襲し、新しいUIパターンを増やさない**
  こと（DESIGN.md設計原則）。
- 資金の整合確認：600（初期）−80（運営費）−140（場所代90＋水道代50の確保）−
  80（小仕込み・最小ケース）−210（初日セット）＝**90**。9杯完売なら＋405（9×45）
  で495。この計算が実際のコードでも一致することを、実装後に`_format_game_state()`の
  `budget`表示で確認する。

### 1-c. 朝の確保（10.3.5）

現状：F4（3-4）で`Ledger.record("reserve", ...)`／`Ledger.record("release", ...)`の
枠組みは既にある（`debug_panel.gd`の支払い演出箇所で呼ばれている）。ただし
「Day1のWAKEで場所代90＋水道代50を**まとめて確保**する」処理そのものが3-5の対象
（現状は演出のタイミングでその都度、決済に近い形で動いている可能性がある。実装plan
作成時に`debug_panel.gd`の該当箇所を再確認し、「WAKEで`reserve`を計上→演出時に
その確保分から`release`」の順序になっているかを確認・修正すること）。

### 1-d. 持ち帰りの注文化（10.3.7）

現状：`day1_events.gd` `_delivery_man_events()`の3杯目（持ち帰り）のREACTイベントは
`"judge": false`、`wanted_tags`／`favorite`キー無し、`reactions: {}`。判定対象・
当夜品質の分母から除外されている。

目標：
- 3杯目のREACTから`"judge": false`を外し、`wanted_tags: ["MELLOW", "GENTLE"]`
  （「今日の頼み：噛まなくても食えるやつ」）を追加して、通常の注文と同じく
  SaleRule／Judgeの対象にする。
- `reactions: {}`はそのまま（持ち帰り先がその場にいないため反応の台詞は出さない。
  判定は行うが会話は無し、という組み合わせ）。
- `favorite`キーは追加しない（配達員本人の好物は1〜2杯目で既に判定対象。3杯目は
  「今日の頼み」のみで好物欄は無し、という10.3.7の書きぶりに従う）。
- 影響確認：`_serve_customer()`／`_add_to_visit_tally()`は`judged`引数を見て
  好物の扱いを分岐している箇所があるため、`judge:false`を外したことで配達員の
  好物確定（`mark_favorite_known`）のタイミングがずれないか、`_flush_visit_tally()`
  周りを実装plan時点で読み直すこと。

### 1-e. 10.11のテスト期待値変更（該当3件）

| テスト | 変更内容 |
|---|---|
| `tests/balance_log_test.gd` | Day1のplanned_cupsを13→9 |
| `tests/reputation_demand_test.gd` | Day1のjudged_planned_cupsを12→9（持ち帰りも判定対象になるため） |
| `tests/schedule_test.gd` | Day1夜半のモブ種類を「複数出うる」→「安宿の夜勤受付（inn_clerk）2人に固定」 |
| `tests/adjust_button_display_test.gd` | 初期在庫の肉団子6個を前提にした期待値を、初日セット購入後の個数を前提にした期待値へ書き換え |

---

## 2. 3-6：鍋の同時容量14（10.3.8）

終わりの条件（10.10）：**残量13以上で水を足せない**。

現状：`game_state.gd` `can_add_water()`／`water_reachable()`は濃さの上下限
（`STRENGTH_HARD_FLOOR`〜`STRENGTH_MAX`）だけを見ており、**残量（容量）の上限は
どこにも実装されていない**（`pot_capacity`はF1で`week7.json`に`14`と宣言済みだが、
`game_state.gd`のどの関数からも参照されていない。他のAIによる自動試遊レポート
（2026-09-26実施）の境界プローブ「14杯・濃さ3・水2・だし1から水→だし→水で
同時残量18」という不整合の指摘はこれに該当する）。

**変更が必要な箇所**：
- `can_add_water()`に「`remaining_servings`が`Rules.pot_capacity() - 2`
  （＝12）以下のときだけ足せる」条件を追加する（水を足すと残量が+2されるため、
  足した後に容量14を超えないためのガード。10.3.8「残量12以下のときだけ足せる」の
  文言と一致）。
- `water_reachable()`（だし→水の回復パス）も同じ容量条件を通した上で判定する
  よう修正する（濃さのガードと容量のガードの両方を満たさないとtrueにしない）。
- 仕込み時点の`remaining_servings`初期値は最大14（大仕込み）であり、水を足す前に
  既に容量上限にあるケースが普通に起こる。UIボタンの無効化（既存の
  `_update_options_row()`の`can_fix_servings`相当）が新しいガードを正しく反映する
  ことを確認する。
- 一晩の総供給上限18（14＋水2回×2）はこのままで変えない（10.3.8）。

---

## 3. 3-7：朝の一画面・予報の幅（10.4）

終わりの条件（10.10）：**Day2以降に総杯数が幅で出る**。

現状：`debug_panel.gd` `_format_tonight_memo()`（SNSタブ）は、時間帯ごとに
「誰が・どんな味を求めているか（＋既知の好物）」だけを一言メモとして出す。
以下は**まだ出ていない**：
- 総杯数（Day1は確定値、Day2以降は`demand_center`±1の幅）。
- 必要な味・具の数（例：HOT4・POWER4…のような、味/具タグ別の必要数の集計）。
- 手持ち在庫との過不足（上記の必要数と`GameState.inventory`を突き合わせた差分）。
- 使える現金（これ自体は`_format_game_state()`の`budget`行に既にあるが、朝の
  一画面としてSNSタブ側からも見える形になっていない）。

`week7.json`の`forecast`（`{"regulars": "base_order", "total": "range",
"range_width": 1}`）と`day_overrides."1".forecast`（`"exact"`）はF1で宣言済みだが
`Rules.forecast()`はまだどこからも呼ばれていない（未消費）。

**変更が必要な箇所**：
- `_format_tonight_memo()`（または新設の関数）を拡張し、既存の客ごとの一言メモに
  加えて次の集計行を足す：
  - 総杯数：`Rules.day_overrides(day).forecast`が`"exact"`（Day1）なら
    今日の実際の合計杯数をそのまま、`Rules.forecast().total`が`"range"`
    （Day2以降）なら`GameState.total_demand_today()`が使う`demand_center`を
    `Rules.forecast().range_width`（=1）で幅表示する（**「中心＝実際」に読めない
    よう、実際に引いた値ではなく中心を基準に幅を出す**。10.4の注意点）。
  - 必要な味・具の数：`today_plan`の各客の`wanted_tags`を集計し、タグ別の
    必要数（例：HOT4／POWER4／MELLOW4／GENTLE4／SAVORY1／FILLING1）を出す。
    モブは「組数を出さない」（組数から人数が逆算できるため。10.4の注意点）＝
    タグ集計に加えるだけで、内訳（何組か）は出さない。
  - 手持ち在庫との過不足：上記の必要数と`GameState.inventory`（タグ換算）を
    比較し、不足しているタグだけを「あと◯個」のように出す。
  - 使える現金：`Ledger.pending_bills_today()`を使い、`_format_game_state()`の
    `budget`行と同じ計算式で「使える現金」を1行足す（表示ロジックの重複を避けたい
    場合は共通のフォーマット関数を`Ledger`か`debug_panel.gd`内のヘルパーへ
    切り出してよい）。
- Day2以降の予報精度（10.4の表）：「常連3人の基本注文・既知の好物＋モブの客層
  （種類の一覧・重複除去）＋総杯数の幅」。**「今日の頼み」は会話で判明**するため
  予報には出さない（`wanted_tags`の実効値ではなく基本注文＝`_customer_flavor()`の
  デフォルト値を使う）。
- **自動購入はしない**（10.4）：この画面はあくまで表示のみで、ボタンから直接
  仕入れる機能を追加しない（市場は既存のPREPフローのまま）。

---

## 4. 3-8：自動試遊の再実行（10.13）

終わりの条件（10.10）：**合格ラインを満たす（数値の暫定確定）**。

3-5〜3-7の実装後、`planning/playtest_2026_09_26/`の仕組み（`run_playthroughs.gd`
等）を使って自動試遊を再実行し、`DESIGN.md`10.13の合格ラインを確認する：

- 基本GOOD方針の平均最終現金が1500〜1700、1500達成率85〜95%。
- 安い完成料理だけ・注文無視の方針が、現金・品質・常連実績の**すべて**で
  基本GOODを上回らない（既存の試遊レポートでは「素材ゼロ」方針が現金だけ
  基本GOODの94%に迫っていた＝初日セット導入・SaleRuleでこの差がどう変わるかを
  確認する）。
- 品質失敗2件（個人1杯＋団体1組）でも7日間の営業を続けられる。
- 小仕込み固定の早期閉店は起きてよい（供給不足の学び）が、**資金不足の休業は0**。

既存の比較方針（7方針×30シード）に加え、初日セット導入後のDay1キャッシュフロー
（1-b「資金の整合確認」の90→495という計算）が実際の試遊でも成立するかを
Day1個別にも確認すること。数値がラインを外れた場合は、`week7.json`の該当数値
（`prep_tiers`／`demand_table`／`day1_kit`の内訳等）だけを調整し、コード側のロジックは
変えない（DESIGN.md設計原則：数値はキャンペーン設定に置く）。

再実行後、`tests/run_tests.gd`（既存スイート）も併せて実行し、1-eで書き換えた
期待値を含めて全項目が通ることを確認する。**このチャット側からはGodotを実行できない
ため、実機での実行と結果の確認はClaude Code（実装担当）またはしまさん自身が行うこと。**
結果は`planning/playtest_2026_09_26/`配下の既存ファイル群と同じ形式で、
日付を更新した新しいレポート（例：`playtest_2026_09_30/`）として残すことを推奨する。

---

## 5. 依頼のまとめ

1. 3-5〜3-8を、上記の順（3-5→3-6→3-7→3-8）で1手順＝1コミットとして実装する。
2. 各手順の着手前に、変更対象ファイル・関数・テストを一覧にした簡潔な実装planを
   提示してから着手する（F1〜F4のときと同じ粒度）。
3. 各手順のコミットメッセージは、これまでのF1〜F4のコミットと同じ形式
   （「F◯: 内容(3-N)」あるいは「3-N: 内容」）に揃える。
4. 3-8完了後、`CURRENT_SPEC.md`の該当箇所（初期在庫の表、Day1需要、鍋容量、
   予報の内容等）も実装事実に合わせて更新する（本書の前提と同じ「実装が先、
   ドキュメントは実装済みの事実だけを記録する」方針）。
