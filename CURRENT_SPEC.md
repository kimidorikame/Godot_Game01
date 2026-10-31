# 夜湯（仮題）現状仕様書

このドキュメントは **「今どこまで実装され、どう動いているか」の事実の記録**。
DESIGN.md が「これから作る指示書」なのに対し、こちらは「現在の到達点」を映す。
実装済みコードを正とする。最終更新時点で Day1 の状態遷移が通しで動き、
**夜の核（会話から好みを読む → 3枠に味と具を選ぶ → 段階評価 → 反応）まで実装済み**。
鍋の残量・濃さ・水/ベース・在庫の消費・市場（一部）・廃棄・具材の腐敗・
終了日・ゲームオーバーも実装済み。
メニュー・レシピ表示（仮UI）は実装済み。7日分のシナリオ（本文）はまだ無い。

---

## 0. 全体像（一言で）

サイバーパンク／九龍風スラムの屋台で一日一鍋のスープを営む会話＋小規模経営ゲーム。
現状は **本番UIの骨組みまで実装済み（絵はすべて仮）**。メインシーンは `scenes/game_root.tscn`
（UI準備B）で、Day1の朝から最終日の結果画面までマウスだけで遊べる。開発用の DebugPanel
（State Viewer）は `scenes/debug_panel.tscn` に残してあり、状態を見ながらボタンで手動進行できる。
**【2026-10-25】UI準備A〜C**（処理の切り出し・本番UIの骨組み・ルールと情報の変更）が入った。
下の「§6 本番UI（UI準備A・B）」「§6 ルールと情報の変更（UI準備C）」を参照。

---

## 1. アーキテクチャ（4つの進行部品＋DebugPanel）

状態を「日をまたいで残る事実」と「イベント列の再生位置」に分ける二層構造。
進行を司る部品を役割ごとに分離している。

| 部品 | 種別 | 役割 | 進行度を持つか |
|------|------|------|--------------|
| **GameState** | autoload シングルトン | 日をまたぐ事実（money, inventory, day_count 等）と、状態変更の入口 | 持たない |
| **FlowController** | Node | 上位フェーズの一方向遷移（WAKE→…→NEXT_DAY）。フェーズゲート判定 | 遷移規則のみ（現在phaseはGameState） |
| **EventRunner** | RefCounted | フェーズ内の Event 列を index で1つずつ再生。status を持つ | index / status |
| **OpenController** | RefCounted | OPEN 中の客キューを1人ずつ管理 | 客の index のみ |
| **DebugPanel** | PanelContainer | 状態表示 ＋ 現状は「Event を受けて処理する側」を兼任（学習・検証用） | — |

補足:
- **status は EventRunner が持つ**（GameState には置かない）。客ごと・フェーズごとに
  runner を使い捨てるので、各 runner が status を持てば混ざらない。
- **DebugPanel が処理も兼任**しているのは意図的。AIに実装させた処理を理解するため、
  ボタン入力→EventRunner→状態変更→表示更新の因果を追う学習・検証装置として使っている。
- 本番UIへ処理を直接コピーしない。本番UIを作る段階で同じ処理が必要になったときだけ、
  DebugPanelと本番UIが共有できるControllerへの分離を検討する。

**（2026-09-28追記・F1〜F4実装済み）** 上記4部品＋DebugPanelに加え、経済・判定のルールそのものは小さな静的クラス（`Day1Events`・`Ingredients`と同じ形）へ分離されている：`Rules`（キャンペーン設定`data/campaigns/week7.json`の読み取り口）・`DayPlanner`（`GameState.today_plan`の構築）・`SaleRule`（提供前チェック）・`Judge`（判定v2）・`Ledger`（`GameState.ledger`への記録・集計）。いずれも状態は持たず（状態は`GameState`のフィールド側）、GameStateの分割や汎用エンジン化ではない（`DESIGN.md`10.2原則10）。

  - `Rules`（`scripts/rules.gd`）：`data/campaigns/week7.json`を読み込んでキャッシュする
    だけの読み取り専用口。`price_per_serving()`・`daily_operating_cost()`・
    `dashi_price()`・`water_doses()`・`demand_table()`・`prep_tiers()`・
    `initial_money()`・`initial_reputation()`・`pot_capacity()`・`final_day()`・
    `bills()`・`day_overrides(day)`等を持つ。値そのものは7日版で変わっていない
    （600/30/45/80/…がコードのconstからJSON参照に変わっただけ）。
  - `DayPlanner`（`scripts/day_planner.gd`）：`build(debug_mob_count=-1)`が
    `Day1Events.customer_schedule()`を呼び、結果を`GameState.today_plan`
    （`{day, slots, mob_instances}`）へ書く。WAKEで1回だけ呼ぶことで「その日の
    客組みを1回決めて使い回す」を保証する（DESIGN.md 10.2原則2）。
  - `SaleRule`（`scripts/sale_rule.gd`）：`check(bowl, soup, order={})`が
    `{ok, reasons[]}`を返す「提供できるか」の事前ゲート。`reasons`は
    `NO_FLAVOR`（味付け0）・`NO_TOPPING`（具0）・`STRENGTH_ZERO`（鍋の濃さ0）・
    `SHORT_SERVINGS`（注文数に対して残量不足）の4種。判定（Judge）より前に、
    在庫・鍋・売上を一切動かさずに呼べる。
  - `Judge`（`scripts/judge.gd`）：`grade(bowl, soup, order)`が
    `{grade, base_grade, penalties[], favorite_hit, match_count}`を返す判定v2。
    一致数どおりのbase_gradeに対し、濃さ1/5・傷んだ具材の各penaltyで最大1段階だけ
    下げる（重ね掛けなし）。favoriteは**初回から**判定に使われ、`match_count>=2`
    のときだけGREATへ上げる（1軸一致＋favoriteはOKのまま。DESIGN.md 10.3.2）。
  - `Ledger`（`scripts/ledger.gd`）：`record(category, amount, item="", count=0,
    unit_price=0, ref="")`で`GameState.ledger`（Array、日をまたいで残る）へ1件追記
    する。`category`は`daily_cost`/`rent`/`water`/`kit`/`prep`/`market`/`dashi`/
    `sale`/`fund`/`reserve`/`release`の11種（DESIGN.md 10.4）。`pending_bills_today()`
    が`reserve`−`release`の当日差分から「支払い予定」を、`spend_by_category_today()`
    が当日のカテゴリ別支出集計を計算する（どちらも読み取り専用の集計関数で、
    money自体には触れない）。3-7で`usable_cash()`（`GameState.money - pending_bills_today()`）
    を追加した。STATE VIEWERの`budget`行の第3項とSNSタブの「使える現金」が共用する。
  - `Forecast`（`scripts/forecast.gd`・3-7）：朝の一画面（SNSタブの客足予報）の集計。
    状態を持たない静的クラスで、`GameState.today_plan`と`GameState.inventory`から計算し、
    数値・辞書を返す（文字列の組み立ては`DebugPanel._format_tonight_memo()`）。詳細は
    下記「スマホUI」の「SNSタブ（客足予報）」参照。**【UI準備C①・2026-10-25】予報はプレイヤーに
    出さなくなった**（本番UIのSNSタブはDM。DebugPanelの予報メモは「検証用」）。`Forecast`は
    自動試遊の既定（`info=forecast`）とテストが使うので消していない。

---

## 2. GameState（日をまたいで残る実行中の事実）

ここでいう「残る」はゲーム実行中の日またぎを指す。ディスクへのセーブは、朝の1枠セーブだけ4-1（2026-10-11）で実装済み（§6「朝の保存と1枠セーブ（4-1）」参照）。

```
day_count   : int   = 1     # 何日目か。NEXT_DAY で +1
money       : int   = 600   # 所持金。支払いで減り売上で増える（2026-09-26改訂：300→600）
reputation  : int   = 30    # 評判。判定結果で増減し、翌日のモブ人数を決める（実装済み。
                             # 2026-09-26改訂：0→30）
inventory   : Dictionary = {} # { id: 個数 }。市場での複数購入に対応（7.7）
stocked_day : Dictionary = {} # { id: 最後に補充した day_count }。腐敗の経過日数の基準（実装済み）
rumors      : Array = []    # スマホ情報（予約のみ・未使用）
phase       : Phase = WAKE  # 今どのフェーズか
soup        : null          # 今日の鍋（仕込み前は null）※日次リセット対象
served      : Array = []    # 今夜の提供実績 ※日次リセット対象
rent_paid_today : bool = false # 今日の場所代を払い終えたか ※日次リセット対象
ledger      : Array = []    # 支出・売上の記録（F4・実装済み・2026-09-28追記）。
                             # {category, amount, item, count, unit_price, ref, day}。
                             # 日をまたいで残る（reset_for_new_game()でのみクリア）。
                             # 旧`pending_bills_today`はここから`Ledger.pending_bills_today()`
                             # で計算する形に置き換えられ、フィールド自体は削除された
                             # （下記「支払い予定」参照）
today_plan  : Dictionary = {} # 今日の客組み（F2・実装済み・2026-09-28追記）。
                             # {day, slots, mob_instances, demand_center}。※日次リセット対象
                             # demand_centerは3-7で追加（WAKEでDayPlanner.build()が保存）
```

### 状態変更の入口（受け側はここだけを通す）
- `apply_money(delta)` … 支払いも売上も全部ここ。差はデータ側の text（トーン）
- `try_pay(amount) -> bool`（実装済み・ゲームオーバー対応）… 「払えないかもしれない」
  支払い専用の入口。所持金が`amount`未満なら**何もせず**`false`を返す
  （`apply_money`を呼ばない）。足りていれば`apply_money(-amount)`を呼んで`true`を返す。
  売上・市場購入など「常に払える／受け取れる」場面は従来通り`apply_money`を直接呼ぶ
  （詳細は§6「ゲームオーバー」参照）
- `settle_reputation(quality)`（実装済み・2026-09-25改訂）… 評判更新の唯一の入口。閉店時に
  DebugPanelから1回だけ呼ばれる：`reputation = round(reputation * 0.7 + quality * 0.3)`。
  杯ごとに増減させていた旧`apply_reputation(delta)`は廃止（詳細は下記「評判」参照）
- `add_inventory(item, count)` … 在庫を足す唯一の入口（`inventory[item] += count`）
- `remove_inventory(item, count)` … 在庫を減らす。0以下になったキーは削除する
  （「持っていない」を辞書に無い状態で表現。引きすぎても負の値にはならない）
- `set_soup(base_id, tags, servings, strength, water_doses)` … 今日の鍋を作る
- `consume_soup(servings)` … 鍋から取り分けた分だけ残量を減らす
- `deepen_soup(delta)` … 鍋を濃くする（実装済み・2026-09-26改訂：1晩で呼ばれるのは
  明け方（最後の時間帯）に入った瞬間の1回だけ。旧・時間帯が変わるたび＝1晩最大2回から
  変更。呼び出し側＝DebugPanelが`OpenController.slot_index`を見て判定する。§5参照）
- `add_water()` / `add_dashi()` … 鍋に水・濃縮だしを足す（複合操作）。**残量を増やせるのは
  水だけ**（濃縮だしは濃さだけ上げる。§5参照）。**上限・下限を超える操作はボタン側の
  `can_add_water()`/`can_add_dashi()`で無効化し、実行時に`clampi`で切り捨てない**
  （2026-09-26改訂・濃さメカニクス三点セット。旧`add_base()`／予備ベースは濃縮だしへ
  置き換え。§5「濃縮だしの購入」参照）
- `can_add_water()` / `can_add_dashi()` … 資源があり、かつ足した結果の濃さが範囲内
  （水は`STRENGTH_HARD_FLOOR`(0)以上、だしは`STRENGTH_MAX`(5)以下）に収まるか。
  **3-6実装済み（2026-10-04・DESIGN.md 10.3.8）**：`can_add_water()`にはさらに
  「残量が`Rules.pot_capacity() - WATER_SERVINGS`（14-2=12）以下」という容量条件が
  独立した`and`条件として加わった（だしでは回復できない条件のため別ガード）。
  `water_reachable()`（だし経由の回復判定）にも同じ容量条件を、だしブーストの判定
  より先に通す。詳細は下記「鍋の同時容量14」参照
- `record_served(record)` … 提供実績を1件記録
- `mark_rent_paid()` … 今日の場所代を払い終えたと記録する（実装済み・§5「未解決」の
  直し方で追加。`rent_paid_today`を直接代入させない入口。2026-09-28追記：
  `pending_bills_today`を差し引く決済処理は削除され、代わりに呼び出し側
  （`debug_panel.gd`）が`Ledger.record("release", ...)`を呼ぶ形に置き換わった）
- `set_pending_bills_for_today()` / `settle_daily_cost_pending()` は
  **2026-09-28追記・F4実装により削除**。表示専用の「支払い予定」は
  `Ledger.pending_bills_today()`が`ledger`の`reserve`/`release`エントリから
  都度計算する形に置き換わった（moneyには一切触れない点は変わらない。
  詳細は下記「支払い予定」参照）
- `reset_for_new_day()` … soup・served・rent_paid_today・today_plan
  をクリア（money・ledger 等は残す。2026-09-28追記：`pending_bills_today`は
  フィールド自体が削除されたためここでは触らない）
- `advance_day()` … day_count +1
- `is_collection_day()` … 今日が徴収日か。**3-5（DESIGN.md 10.9）で`day_count == 1`の
  直書きから`Rules.bills()`の各billの`days`（`week7.json`では全billとも`[1]`）に
  `day_count`が含まれるかの判定へ置き換えた（値そのものは変わらず、7日版では
  引き続き初日のみtrue）。実装中に見つかった注意点：JSONの数値はfloatとして読まれる
  ため、`Array.has(day_count)`（int）だと型が違って一致しない（`[1.0].has(1)`が
  false）。要素ごとに`int(d) == day_count`へ変換して比較する（コミット`5d86444`）。
  徴収日が初日のみのため、通常プレイでは水道代・場所代によるゲームオーバーは
  Day1以外では発生しない。意図した割り切り。§11参照
- `total_demand_today()` … 今夜の総需要杯数を決める。**3-5（DESIGN.md 10.9）で
  `day_count == 1`なら`DAY1_DEMAND`定数、という直書きから`Rules.day_overrides(day)`に
  `fixed_demand`があればそれを返す形へ置き換えた（`week7.json`の
  `day_overrides."1".fixed_demand`＝9。`DAY1_DEMAND`定数自体は削除）**。それ以外の日は
  `DEMAND_TABLE`（評判の下限→中心値）から中心値を引き、±1に25/50/25%で振れる。
  モブの人数は名前付き客の杯数を差し引いた残りとして`Day1Events._plan_mob_groups()`が
  組に分けて配分する（詳細は下記「客数の決め方」参照。旧`mob_count_for_reputation(reputation)`・
  `mob_count_today()`は廃止）。
  **3-7（2026-10-11）**：中心値を引く処理を`demand_center_today()`（乱数なし。
  `fixed_demand`がある日はその値）へ分離し、`total_demand_today()`はこれを呼んで
  ±1を抽選するだけになった（`DEMAND_TABLE`を参照する箇所は1箇所）。朝の予報は
  抽選結果ではなくこの中心を基準に幅を出す。`DayPlanner.build()`がWAKEで
  `today_plan["demand_center"]`へ保存する
- `fresh_count(id)` / `damaged_count(id)` … 品目の「傷んでいない/傷んだ」在庫数
  （購入日ごとのロット`perishable_batches[id]`から集計。実装済み・鮮度選択。§5参照）
- `remove_inventory_fresh(id, count)` / `remove_inventory_damaged(id, count)` …
  指定したバケツから古い順に引き、足りなければもう一方で自動的に補う
- `discard_spoiled_inventory()` … 経過4日目以上のロットだけを在庫・`perishable_batches`から削除し、
  破棄が発生した品目ごとに`{id: {"count": 破棄個数, "value": 実額}}`のDictionaryで返す（同じ品目の
  新しいロットが残っていれば品目自体は残る。**2026-09-23：戻り値をidの配列からDictionaryへ変更
  （日次ログの廃棄額概算に個数が必要になったため）。呼び出し元2箇所は無改修で動作**。
  §11「日次ログの導入」参照。**同日・①具材の購入単位で、`value`（ロットの実際に払った単価×
  個数の合計）をさらに追加。呼び出し元は変わらず`for id in spoiled`とキーを回すだけなので、
  この拡張でも無改修**）
- `is_final_day()` … 今日が最終日か。`day_count >= FINAL_DAY`（`is_collection_day()`と同じ形）
- `reset_for_new_game()` … 全状態初期化。**【4-2で変更】結果画面の「新しい周」から呼ばれる**（以前は最終日のNEXT_DAY→WAKEで呼ばれていた）
  （下記「状態変数12個すべてが対象」参照）

### ゲーム共通の定数（GameState に置く）
- `PRICE_PER_SERVING = 45`（**2026-09-26改訂：差分表最後の3項目で50→45**）…
  一杯の売価（内容にかかわらず固定）。**チップ（UI準備H2）**：評価した杯だけ、定価に加えて`GameState.tip_for(評価, 杯数)`ぶんを受け取る
  （GREAT +10・GOOD +5・OK／BAD・評価なしは 0。値は`data/campaigns/week7.json`の`economy.tips`＝`Rules.tips()`。定価は全評価で同じで、BADも受け取る。
  評判の式・判定・SaleRuleは変えない）。売上（提供記録の`sale`・日次ログの`sale_total`・帳簿の`sale`）はチップを含み、うちチップを提供記録の`tip`・日次ログの`tips`・
  `Result.summarize`の`tips`に持つ（追加のみ。保存版は上げない）。表示：夜の結果・昨夜の成績の売上の横に「うちチップ ¥xx」、結果画面の成績に「チップ合計」の1行、
  提供の直後の反応の文に「+¥5」。自動試遊は既定でチップを0に差し替える（v2と全キー一致）。確認：`tests/tips_test.gd`。
  **具だくさん（UI準備L）**：具の材料が2種類（違う材料。`Ingredients.topping_kinds`。同じ材料を2つ・札が2つある材料1つ〔牛すじ〕は1種類）入っていて、評価（減点で下がったあとの評価）が
  GOOD以上の丼は、チップに`GameState.hearty_tip_for(評価, 杯数, 椀の具材)`ぶんを足す（1杯 +10。GOOD 計+15・GREAT 計+20。値は`economy.hearty_tip`＝`Rules.hearty_tip()`、0で無効）。
  味1・具1の丼のチップは変えない。上乗せはチップ（提供記録の`tip`・日次ログの`tips`）に含み、うち具だくさんを提供記録の`hearty_tip`・`hearty_cups`（上乗せがあった記録だけ）、
  日次ログ（`day_records`・BALANCE_LOG）の`hearty_tips`・`hearty_cups`、`Result.summarize`の`hearty_tips`・`hearty_cups`に持つ（追加のみ。保存版は上げない）。
  表示：提供の直後の反応の文に「+¥5　具だくさん +¥10」（分けて出す）、結果画面の成績の「チップ合計」の下に「うち具だくさん ¥xx（x杯）」。
  自動試遊は既定で上乗せも0に差し替え、`result_summary`には出さない（v2と全キー一致）。確認：`tests/hearty_tip_test.gd`
- `SERVINGS_PER_BASE`は**2026-09-25（仕込み3段階化）で削除**。ベース1袋で作れる
  杯数は`Day1Events.PREP_TIERS`（小8杯/80・中11杯/110・大14杯/140）が持つ形に
  変わった（下記「仕込みの3段階化」参照。コミット`9a49e90`）
- `INGREDIENT_SERVINGS_PER_PURCHASE`は**2026-09-23（①具材の購入単位）で削除**。
  市場での1回の購入で増える個数は品目ごとに`*_goods()`の`count`フィールドが持つ形に
  変わった（下記「市場での購入」参照。コミット`e6fbc27`）
- `DEMAND_TABLE`（実装済み・2026-09-25改訂）… 総需要杯数を決める評判の下限→
  中心値テーブル。旧`MOB_COUNT_TABLE`は廃止（下記「客数の決め方」参照）。
  **`DAY1_DEMAND`定数は3-5で削除**（Day1固定値9は`week7.json`の
  `day_overrides."1".fixed_demand`へ移った。上記`total_demand_today()`参照）
- `SPOIL_DAMAGED_DAY = 3` / `SPOIL_DISCARD_DAY = 4` … 腐る品目の経過日数のしきい値
  （購入日を1日目として数える）
- `RENT_PRICE = 90`（**2026-09-26改訂：場所代・水道代の再編で150→90**）… 場所代。
  チンピラのPAYの金額と、未払いのまま閉店したときの特別請求（実装済み・§5
  「未解決」の直し方）の両方に使う。**システム整理Aで定数から`static var RENT_PRICE := Rules.bill_amount("rent", 90)`
  になった**（正は`week7.json`の`bills`の`rent`の`amount`。値は90のまま）
- `WATER_PRICE = 50`（実装済み・2026-09-26改訂・場所代/水道代の再編）… 水道代。
  従来`debug_panel.gd`内のマジックナンバーだったのを`RENT_PRICE`と同じ扱いで
  定数化した（値そのものは50のまま）。場所代と合わせて徴収日の合計140
  （`BALANCE_REDESIGN_PLAN.md`§1・§2）
- `DAILY_OPERATING_COST = 75`（**【2026-10-25・UI準備D・D-4】朝には引かない。朝は払えるかだけを見て「支払い予定」として確保し、市場を出るときに引く**（下の「画面の使い勝手（UI準備D）」D-4）。**3-8で80→70→65に調整、2026-10-18に65→75へ変更**〔到達杯数を補正した再測定の結果。暫定値で、フェーズ5の最初の人の試遊のあとに見直す。下記「運営費75の確定」参照〕。値は`week7.json`の`economy.daily_operating_cost`を`Rules.daily_operating_cost()`経由で読む。新設・実装済み・2026-09-26改訂・場所代/水道代の
  再編＋日々の運営費）… 徴収日に関わらず7日間毎日発生する固定費。WAKEに入った
  瞬間`debug_panel.gd`が直接支払う（詳細は§6「WAKE」参照）
- `FINAL_DAY = 7` … 本番の7日版（体験版の3日から変更済み・実装済み・Godot実機で
  7日通しプレイを確認済み。§11「今回決めた3点」参照）
- `INITIAL_MONEY = 600`（**2026-09-26改訂：差分表最後の3項目で300→600**）… 初期値。
  変数宣言側もこの定数を使い、初期値が二重に書かれないようにしている
- `INITIAL_REPUTATION = 30`（新設・2026-09-26改訂・差分表最後の3項目）… 初期評判。
  従来は`INITIAL_MONEY`と違って定数化されておらず、変数宣言側・`reset_for_new_game()`
  の2箇所に`0`が直書きされていたが、値を変えるにあたって同じパターンに揃えた
- `BASE_PRICE`（`INITIAL_RESERVE_BASE_UNITS`も同様）は**2026-09-26（濃さメカニクス
  三点セット）で削除**。予備ベース購入（`buy_reserve_base`）専用の価格だったが、
  予備ベースごと濃縮だし（`DASHI_PRICE = 16`）へ置き換わったため不要になった
  （§5「濃さの上限・下限」「濃縮だしの購入」参照。コミット`5927470`）

---

## 3. フェーズ遷移（FlowController）

```
WAKE → PREP → OPEN → CLOSE → NEXT_DAY →（WAKE へ折り返し）
```

- **一方向。前に戻らない。** これが「一日一鍋・仕込み直し不可」を構造で保証する。
- NEXT_DAY→WAKE の折り返しで分岐する（実装済み。**【2026-10-11・4-2で変更】最終日は日次リセットも日数加算もせず`Phase.RESULT`へ入る。最終日の項目は4-2以前の記述**。§6「結果画面（4-2）」参照）：
  - 最終日でなければ今まで通り `reset_for_new_day()` ＋ `advance_day()`
  - **最終日（`GameState.is_final_day()`）なら `reset_for_new_day()` の代わりに
    `GameState.reset_for_new_game()` を呼び、`game_restarted` シグナルを発火する**。
    `DebugPanel` がこれを受けて初期在庫を積み直す（§6「終了日」参照）
- `advance_phase()` でフェーズを1つ進める。`[次のPhase]` ボタンから叩く。
- **`GAME_OVER`（実装済み）**：`Phase` enum の末尾に追加した終端フェーズ
  （既存の `WAKE=0 / PREP=1 / OPEN=2 / CLOSE=3 / NEXT_DAY=4` の番号は変えていない。
  `GAME_OVER=5`、4-2で`RESULT=6`を追加）。通常の一方向連鎖（WAKE→…→NEXT_DAY→WAKE）とは別枠で、
  水道代・場所代が払えないときにここへ入る（詳細・確認手順は§6「ゲームオーバー」参照）。
  `advance_phase()` は先頭で `phase == GAME_OVER` ならガードして何もしないため、
  `[次のPhase]` が効かなくなる。（【2026-10-11追記・4-1】仮ボタン[同じ朝からやり直す]で、最後に記録された朝へ戻れるようになった。`[次のPhase]`では復帰しない点は変わらない。）

### フェーズゲート（途中で飛ばせるか）
`_phase_can_skip` テーブルで管理。DONE 必須フェーズは runner が DONE になるまで
`[次のPhase]` を弾く（`is_advance_blocked()`）。

| フェーズ | 飛ばせるか | 理由 |
|---------|-----------|------|
| WAKE | ○（true） | スマホを見ずに出かけてよい |
| PREP | ✕（false） | 仕込みを飛ばさせない |
| OPEN | ✕（false） | 接客を飛ばさせない |
| CLOSE | ✕（false） | 閉店処理を飛ばさせない |
| NEXT_DAY | ○（true） | 日次処理だけの自動フェーズ |

---

## 4. Event 型（データと処理の分離）

Event は **データ**（値のみ）。処理は受け側（現状 DebugPanel の `_apply_event`）が
type を見て振り分ける。処理をデータに埋め込まない。

| type | 効果 | 処理 |
|------|------|------|
| TEXT | 表示のみ | なし（状態を動かさない） |
| WAIT_INPUT | 入力待ちで停止 | EventRunner が status=WAITING_INPUT にする |
| PAY | 支払い | `_pay_or_game_over(amount)` → `try_pay(amount)`。<br>払えなければ GAME_OVER（§6「ゲームオーバー」） |
| ADD_ITEM | 在庫追加 | `add_inventory(item, amount)` |
| REMOVE_ITEM | 在庫消費 | `remove_inventory(item, amount)` |
| SET_SOUP | 共有鍋の作成 | `set_soup(base_id, tags, servings, strength, water_doses)`<br>（クズ野菜の日は strength=1。§6参照） |
| GREET / SERVE | 表示のみ（接客） | なし |
| CHOICE | 店主の距離感の選択（入力待ち。システム整理C2） | `options`（`{id,label}`の二択）を持つので停止。選んだ結果は`CustomerMemory.record_choice`で来店記録の`choices`と`facts`へ（§6「提供後の場面」） |
| SCENE_END | 場面の終わり（システム整理C2） | `sets_facts`を来店記録の`facts`へ書く（締めを読み終えて来たときだけ） |
| ADJUST | 具材の選択（入力待ち） | `options` を持つので EventRunner が停止。<br>椀への反映は受け側（選択肢ボタン）。<br>`new_bowl: true` のときだけ、current になった瞬間に `reset_bowl()` で椀を新しくする（同じ客の2杯目以降） |
| MARKET | 市場の店選び（入力待ち） | `options`（6店舗。2026-09-26改訂：水場のボタンを廃止し7→6）を持つので停止。<br>店を選ぶ処理・水道代の自動支払いは受け側。「市場を出る」で先へ |
| REACT | 判定＋売上確定 | `judge_bowl()` で4段階判定 ＋ `apply_money(+sale)` ＋ `record_served()`。<br>任意フラグ（既定値なら従来どおり）：<br>`judge: false` … 判定しない（評判も動かない）。鍋の消費と売上は通常どおり<br>`aggregate: true` … 鍋の消費と売上はその場で、評判と提供記録は退店時に客1人分として1回だけ反映（§5「1杯ずつ接客する客」） |

※ `options` を持つ Event は type に関係なく入力待ちになる（個数は関知しない）。

### EventRunner の status
- `PLAYING` … `advance()`を受け付ける状態。現状は`[次のEvent]`で index +1
- `WAITING_INPUT` … 入力待ちで停止。`[入力完了]`（complete_input）でのみ解除
- `DONE` … 列を消化しきった。上位が「次へ進んでよい」と見る合図

### 現在の既知制約
Event の効果は index が次へ動いたときに、新しく current になった Eventへ一度適用する。
そのため index 0 に効果Eventを置くと適用されない。現在は各Event列の先頭が
TEXT / GREETのみなので実害はないが、将来先頭へ効果Eventを置く場合は実行契約を見直す。

---

## 5. OPEN の客ループ（OpenController）

OPEN だけ別階層。客ごとに EventRunner を使い回す。

```
FlowController（フェーズ）
  └ OPEN のとき
      └ OpenController（客キューを1人ずつ： queue / index）
          └ EventRunner（その客の GREET→ADJUST→SERVE→REACT を再生）
```

- 客がさばき切られる（runner が DONE）と、次の客をロード。
- キューが空になると OPEN 終了 → CLOSE へ進める。
- 接客の骨格は全客共通（4ステップ）。差は text と sale、および REACT 後の追加 Event。

### 調理（ADJUST）— 3枠に味と具を選ぶ

- ADJUST は `options` を持つ Event。`options` を持つ Event は
  EventRunner が入力待ちとして扱う（個数は関知しない）。
- **選択肢は在庫から動的生成する（実装済み）**：`_adjust_options()` が
  `GameState.inventory.keys()`（`soup_base` を除く）を毎回読んで
  ボタンを作る。ハードコードされた7種固定リストではなくなった。
  表示ラベルは `_ADJUST_LABELS`（id → 日本語名）の辞書から引く。
  在庫に無い（買っていない／使い切った）具材はボタンごと出ない。
- 具材ボタンを押すと `current_bowl.additions` に足すだけで、**runner は進まない**。
  進むのは `[入力完了]`（提供）を押したとき。「選ぶ」と「進む」を分離している。
- 上限3つ。**重複可**（同じ具材を複数入れられる。将来「強さ」を持たせる余地）。
- 3つ埋まると具材ボタンを無効化。3つ未満でも提供でき、0個なら具なし。
- ボタンの無効化は「3つ埋まった」だけでなく**在庫が尽きた**場合も効く
  （接客の途中で在庫が0になったケースに対応。都度 `GameState.inventory` を
  見て判定するので、Event生成時の固定値には頼らない）。
- 在庫は `add_inventory`/`remove_inventory` で増減する `Dictionary {id: 個数}`。
  0以下になったキーは自動で削除される（「持っていない」＝キーが無い状態）。
- **具材消費は `servings` 連動（実装済み・当初想定から変更）**：ボタンを1回押すと、
  在庫は1個ではなく**その客の `servings` 分**まとめて減る（港湾労働者 servings=4
  なら-4。配達員は1杯ずつ接客するので、各杯で-1）。1回の調理が「客が頼んだ杯数ぶんの
  具材を使う」ことに対応させるため。
- **【解消済み】在庫を減らすのは椀への追加が成功したときだけ（フェーズ1 ステップ3）**：
  `OpenController.add_to_bowl()` が `bool`（追加できたか）を返すようにし、
  `DebugPanel._on_ingredient_selected()` は追加が成功したときだけ
  `GameState.remove_inventory()` を呼ぶ。UI側のボタン無効化（上限3つ・在庫切れ）で
  通常は起きないが、直す前は「椀には入らないのに在庫だけ減る」ケースが理論上あった。
- **端数での無効化（名前あり客・配達員のみ。実装済み）**：在庫が0でなくても、残数が
  客の `servings` に満たない具材のボタンはグレーアウトする。「在庫切れ」の判定は
  0基準ではなく「この客に出すのに足りるか」基準になった。
- **【2026-09-23：モブ客（団体オーダー）だけ例外に変更】** 上記の「端数での無効化」・
  「選んだ瞬間に`servings`分まとめて消費」は、**モブ客（`is_mob:true`）には適用されなく
  なった**。`BALANCE_REDESIGN_PLAN.md`§8②「拒否と部分提供」の実装
  （コミット`c19ed80`）で、モブ客に限り
  - ボタンの無効化条件は「押した側のバケツに1個以上あるか」だけに簡略化（名前あり客・
    配達員はservings常に1なので旧条件と数学的に同値＝無変化。モブだけ「全員分そろわ
    なくても選べる」ようになった）。
  - 選んだ具材は在庫をまだ引かず、`[入力完了]`を押して人数を確定した時点で
    まとめて消費する（下記「団体客の人数調整」参照）。
  名前あり客・配達員はこの項目の記述のまま変更なし。
- 計器盤の `inventory_detail(内訳)` に品目ごとの個数を表示する。
- **具材ボタンに所持数を表示（実装済み・2026-09-26改訂）**：ラベルの末尾に
  `(N)`で残数を付ける（例：`肉団子(4)`、傷んだ側は`肉団子(傷)(2)`）。ボタン無効化の
  判定にすでに使っている在庫数（`own`）をそのまま表示に使うだけで、新しい計算は無い。
- **調味料と具材のボタンを2行に分ける（実装済み・2026-09-26改訂）**：ADJUSTの具材
  選択のときだけ、`SeasoningRow`（新設）と`OptionsRow`（既存）の2行に分けて表示する。
  分類は新しい辞書を作らず、既存の`Ingredients.is_topping()`（「具なしの椀は常に
  最低評価」の判定にも使っている「具の軸」判定）をそのまま流用する：`POWER`/`GENTLE`/
  `FILLING`/`BITE`/`TREAT`のいずれかを持つ品目が`OptionsRow`（具材）、`HOT`/`MELLOW`/
  `SOUR`/`BITTER`/`SAVORY`のみの品目が`SeasoningRow`（調味料）。**苦瓜（bitter_melon）は
  タグが`BITTER`のみ（味の素材）なので調味料側に入る**（`ingredients.gd`に明記された
  既存仕様どおり）。`[廃棄する]`は具材側（`OptionsRow`）に残る。ADJUST以外の場面
  （PREP_TIER・鍋モード・団体客の確認ボタン）は今までどおり`OptionsRow`1行のまま。
  **【2026-10-11・UI変更で市場の店の画面も2行になった】**§「市場の店の画面の2行表示」参照。
  対象は名前あり客・配達員・モブすべて共通（ADJUSTの表示に関する全客共通の変更）。

### 団体客の人数調整（拒否と部分提供・実装済み・2026-09-23／分割提供は2026-09-26改訂）

`BALANCE_REDESIGN_PLAN.md`§6「団体を全員断らずに済むようにする」・§8②の実装
（コミット`c19ed80`。経済数値・評判テーブル・鍋容量は無変更）。対象は**モブ客
（`is_mob:true`の団体オーダー）だけ**。名前あり客・配達員（servings常に1）は対象外。

- **達成可能人数の計算**：`min(注文人数, 鍋の残量, 選んだ各具材のバケツ別在庫数)`。
  新鮮・傷んだの2バケツは合算しない（新鮮2＋傷み2を「新鮮4人分」とは扱わない）。
  同じ具材を複数枠（重複可）で選んだ場合は、その具材の在庫数を選んだ回数で割った値が
  上限になる（例：軟骨(新鮮)を2枠選び新鮮在庫8個なら、軟骨に関する上限は8÷2=4人）。
- **UI**：モブ客のADJUST中に`[入力完了]`を押すと、最初の1回では進まず
  「N人分を提供（注文M人）」「注文を断る」の2択（レシピ1で達成可能人数が注文人数に
  満たないときは「残り◯人に別の具材で挑戦する」を加えた3択）に差し替わる
  （`_pending_group_choice`。既存の鍋モード・市場・スマホと同じ「専用ボタン行に
  差し替える」パターン）。達成可能人数が0のときも「挑戦する」は出す（具材を変えれば
  0人からでも挽回できるため）。全員分そろっている場合も必ず「断る」を出す（自動で
  全員提供にはしない）。
- **確定後**：ボタンを押すまで在庫・鍋残量・売上・評判は一切動かない。確定すると、
  実際に提供する人数（`actual`）ぶんだけ鍋・具材を消費し、売上は`actual×PRICE_PER_SERVING`。
  判定（GREAT/GOOD/OK/BAD）は`actual`の大小に関係なく「何を入れたか」だけで決まる。
  評判はこの場では**動かない**（実装済み・2026-09-25改訂：杯ごとの即時加算は廃止し、
  閉店時に`_log_quality_counts`へ結果を積んで1回だけ計算する方式に統一。下記「評判」
  参照）。「断る」（`actual=0`）を選んだ場合は判定・鍋消費・売上のいずれも発生しない。
- **分割提供（最大2レシピ・実装済み・2026-09-26改訂）**：`BALANCE_REDESIGN_PLAN.md`§6が
  当初「今回は対象外・将来検討」としていた、団体を複数レシピに分けて届ける機能。
  「挑戦する」を選ぶと、その時点の達成可能分（レシピ1）はその場で確定・提供し、
  残り人数ぶんを**新しいADJUST（`new_bowl:true`で椀をリセット。既存の「同じ客の
  2杯目以降」と同じ仕組みを流用）へ回して具材を選び直せる**。2回目のADJUSTでは
  「N人分を提供／注文を断る」の2択のみで、「挑戦する」は出ない（**1団体につき
  最大2レシピ**で打ち止め）。新しいADJUST/SERVE/REACTは、既存のEventRunnerが
  今どの位置にいるかを見て、その直後へ動的に挿入する（`flow.runner.events.insert()`。
  PREP_TIER段階選択のような「runnerごと差し替え」ではなく、同じrunnerを延長する形。
  モブ客の接客Event列に閉店会話等が後ろに続く場合でも順序を保てる）。各レシピの
  判定は個別に`judge_bowl()`を呼ぶ（人数の多寡に影響されない、既存どおり）。
- **記録の統合**：配達員の複数杯接客（1人として集計する`_visit_tally`）を団体客にも
  拡張し、**1団体＝1件の`record_served()`にまとめる**。`sale`・`servings`は両レシピの
  合計、`results`は判定結果ごとの内訳（例：`{"GOOD": 3, "OK": 1}`。従来の単一の
  `result`フィールドは使わない）、`ordered_servings`は最初の注文人数（レシピ2でも
  変わらない）、`unserved_servings`は両レシピ確定後の最終的な不足人数、`declined`は
  1杯も提供できなかったときだけ`true`。配達員側の集計（`ordered_servings`を渡さない
  呼び出し）は`{customer, sale, servings, results}`の4フィールドのまま変わらない
  （同じ`_add_to_visit_tally`/`_flush_visit_tally`を条件分岐で共用）。評判
  （`_log_quality_counts`）への加算は**グループ確定（最終レシピのflush）時に
  両レシピぶんをまとめて行う**（レシピごとにその場で加算すると、flush時の`results`
  再合算と二重加算になるため）。閉店時にしか読まれない日次集計のため、加算タイミングの
  違いは最終結果に影響しない。
- **鍋不足フローとの関係**：モブ客に限り、鍋残量不足を理由にした`[入力完了]`のブロックと
  `[閉店]`の自動出現が無くなった（達成可能人数の計算に鍋残量も含めたため、鍋が
  尽きていても「断る」で次の客へ進めるようになった）。下記「鍋が尽きたときの対応」は
  **名前あり客・配達員には無変更のまま適用される**。
- `tests/group_partial_serve_test.gd`（24項目→分割提供の新規シナリオ2件を追加し
  計45項目）で配線を検証。挑戦して成功するケース・2回目も鍋残量律速で不足するケースの
  両方で、`record_served`が1件にまとまり`results`/`ordered_servings`/`unserved_servings`/
  `declined`が正しいこと、`_log_quality_counts`が二重加算されないことを確認済み。
  Godot実機でも、具材を意図的に絞った状態でモブ客に遭遇させ、確認ボタンの表示・
  「挑戦する」からレシピ2への遷移・断った場合に材料が減らないことを目視確認済み。
  コミット：`9c9da7e`。

### 名前あり客・配達員の「客を断る」（F3・実装済み・2026-09-30追記）

`DESIGN.md`10.3.6。上記の団体客（モブ）向け「注文を断る」はコミット`c19ed80`で
既にあったが、**名前あり客・配達員は対象外**だった。F3実装で名前あり客・配達員の
ADJUST中にも`[客を断る]`ボタンが追加され（`_is_current_mob_order()`のときは
モブ側の「断る」と重複するためこのボタン自体を出さない）、達成可能かどうかに
関わらずいつでも押せる。

- `_on_customer_decline_pressed()`が`_pending_decline`を立てて
  `_complete_input_and_advance()`を呼ぶ（`_pending_group_choice`と同じ
  「ADJUST側で確定させてREACT到達時に反映する」パターン）。
- `_serve_customer_decline(ev)`：`judge_bowl()`を呼ばない・鍋を消費しない・
  売上を発生させない。`GameState.record_served({customer, sale:0, servings:0,
  declined:true, result:""})`として未提供を記録する（配達員＝`aggregate:true`の
  ときは`_visit_tally`へ0杯ぶんとして積み、退店時にまとめて反映）。
- ADJUST中の事前警告（`_format_sale_hint()`。F3・DESIGN.md 10.3.1/10.3.2）：
  まだ判定していない椀について、`SaleRule.check()`が`NO_FLAVOR`/`NO_TOPPING`を
  返すなら「（このままでは提供できません：味付けが入っていません・具が入って
  いません）」を、提供はできても濃さ1/5または傷んだ具材使用でJudgeの減点が
  見込まれるなら「（このままだと1段階下がります：…）」を表示する。どちらも
  該当しなければ何も表示しない。残量不足（`_is_short_in_adjust`）・濃さ0
  （`_is_strength_zero_in_adjust`）は既存の別ロジックが担当するため、
  `_is_bowl_unsellable_in_adjust()`はSaleRuleの`NO_FLAVOR`/`NO_TOPPING`だけを見る
  （二重判定を避ける）。`NO_FLAVOR`/`NO_TOPPING`のときは`[入力完了]`も止まる。

### 初期在庫（`initial_inventory()`・**3-5で廃止・実装済み**）

> **【2026-10-01追記・3-5実装済み】** 以下は無料の初期在庫が存在していた時点の
> 記録（履歴として残す）。3-5（DESIGN.md 10.3.4）の実装により`initial_inventory()`は
> 空の辞書を返すだけになり、具材は一切無料では持たない。代わりに下記「初日セット
> （`day1_kit`・実装済み）」がDay1のPREPで固定購入される（コミット`5d86444`）。

Day1 開始時点で最初から持っていた分（市場で買う前でも Day1 の3人＋モブに
対応できる最小セットとして確定していた、旧仕様）。

具材3品目（下記表）は詰みポイント対策（Day1の実際の注文13杯に対し初期在庫が
9杯想定分しかなく足りなくなる問題）として2026-09-26に増量していた。ナムプリック
パオ・ココナッツミルク・薬膳ナンプラーだれ（調味料3種）と offal（モツ）は
変更なし。

| 種別 | id | 個数（旧・無料初期在庫） |
|------|----|----:|
| 調味料 | nam_prik_pao（ナムプリックパオ） | 10 |
| 調味料 | coconut_milk（ココナッツミルク） | 10 |
| 調味料 | herbal_sauce（薬膳ナンプラーだれ） | 10 |
| 具材 | offal（下処理したモツ） | 4 |
| 具材 | meat_ball（くず肉団子） | 6 |
| 具材 | tofu（豆腐） | 5 |
| 具材 | broken_wrapper（割れた餃子皮） | 5 |

- `pickled_lime`（塩漬けライム）と `bitter_melon`（苦瓜）は無料在庫に含めず
  （どちらも市場で買って初めて使えるようにし、「買う」動線の価値を残すため。
  苦瓜は永順青果で実際に購入できる＝下記参照）、この方針は初日セットでも
  踏襲されている（下表参照）。

### 初日セット（`day1_kit`・F1 day_overrides・3-5実装済み）

DESIGN.md 10.3.4。Day1のPREPで、仕込み段階を選ぶ前に固定の購入イベントとして
差し込まれる（プレイヤー操作を挟まない一方向のイベント。MARKETのような選択UIは
出さない＝「Day1は自由な買い物なし」を維持）。

内容は`data/kits/day1_kit.json`（`ScheduleData.kit_data(id)`。`mob_data()`と同じ
キャッシュパターン）が持ち、`Rules.day_overrides(1).kit`（＝`"day1_kit"`）で
参照される。

| 品目 | id | 個数 | 価格 |
|------|----|----:|----:|
| ナムプリックパオ | nam_prik_pao | 5 | ¥25 |
| ココナッツミルク | coconut_milk | 6 | ¥30 |
| 薬膳ナンプラーだれ | herbal_sauce | 5 | ¥25 |
| 肉団子 | meat_ball | 6 | ¥48 |
| 豆腐 | tofu | 6 | ¥48 |
| 割れた餃子皮 | broken_wrapper | 3 | ¥18 |
| 濃縮だし | dashi | 1回 | ¥16 |

**合計¥210**（モツ＝offalは含めない）。

- `Day1Events.prep_events()`の`_kit_purchase_events(kit_id)`が、TEXT（「いつもの
  仕入れ先で、仕込みに使う分をまとめて受け取った。」）→PAY（`kind:"kit"`、
  `Ledger`の`kit`カテゴリで記帳）→品目ごとのADD_ITEM（`unit_price`付き。腐る
  品目は`perishable_batches`へ実際に払った単価で記録される）という順のEvent列を
  組み立てる。
- `debug_panel.gd._apply_event()`のADD_ITEMハンドラは、`item`が`"dashi"`のときだけ
  在庫ではなく`GameState.buy_dashi()`へ振り分ける（市場の`_on_shop_item_selected()`の
  `id == "dashi"`特別扱いと同じ前例）。
- Day1は市場がまだ開いていない（`market_open_from_day = 2`）ため、このセットが
  Day1に使える具材の唯一の出どころになる。
- 配達員3杯目（持ち帰り）の`MELLOW`＋`GENTLE`に使える豆腐・ココナッツミルクも
  このセットに含まれる。

### 具材の腐敗（実装済み）

**対象品目**（`Ingredients.is_perishable(id)`）:

| 腐る | 腐らない |
|---|---|
| coconut_milk（ココナッツミルク） | nam_prik_pao（ナムプリックパオ） |
| offal（モツ） | herbal_sauce（薬膳ナンプラーだれ） |
| meat_ball（肉団子。旧ラベル「くず肉団子」） | pickled_lime（塩漬けライム） |
| tofu（豆腐） | winter_melon（冬瓜） |
| broken_wrapper（割れた餃子皮） | dried_wood_ear（乾燥きくらげ） |
| bitter_melon（苦瓜） | rice_noodle（米麺） |
| cartilage（軟骨） | fish_maw（魚の浮き袋。**2026-09-23：①具材の購入単位で腐る側から移動。`BALANCE_REDESIGN_PLAN.md`§3「保存=可」に合わせた**） |
| tendon_meat（すじ肉。**同日：タグにPOWERを追加**。下記「味と具の軸」参照） | soup_base（対象外・別ロジックで消費） |
| shrimp（海老） | |
| clam（貝） | |

**経過日数と状態**（購入日を1日目とする。都度計算・保存しない）：

| 経過日数 | 状態 | 効果 |
|---|---|---|
| 1〜2日目 | 傷んでいない | 通常通り使える |
| 3日目 | 傷んだ | 使って判定すると-1段階（4日目以降は下記の通り自動破棄されるので、実質3日目だけがこの状態で選べる） |
| 4日目以降 | 自動破棄 | PREP冒頭で `discard_spoiled_inventory()` が対象のロットだけ削除。破棄があれば一言テキストで知らせる |

- **在庫は購入日ごとのロット（バッチ）で管理する（実装済み・鮮度選択）**：
  `perishable_batches[id]`（`[{day: 購入日, count: 個数, unit_price: 1個あたりの
  実際の支払額}, ...]`。購入日が早い順）に、同じ品目を買うたびロットが積み増される
  （**同じ日かつ同じ`unit_price`のときだけ**ロットを合算。2026-09-23・①具材の
  購入単位：同じ日にパック購入と小口購入を両方行うと単価が異なるため、合算すると
  廃棄額の計算で単価を取り違えてしまう。分けて別ロットのまま持つ）。
  買い足しても古いロットの経過日数はリセットされない＝
  「一部は新鮮・一部は傷んでいる」が同じ品目内で共存できる
  （旧仕様は`stocked_day[id]`という品目1つにつき経過日数1つのスカラー値しか
  持たず、買い足すたびに上書きされて古い分の情報が消えていた。今回そちらは廃止した）。
  `inventory[id]`（合計個数）は常にロットの合計と一致する。
- **ADJUSTのボタンは「傷んでいない」「傷んだ」の最大2つに分かれる**：
  その品目に傷んでいない在庫が1個以上あれば「（品目名）」ボタン、傷んだ在庫が
  1個以上あれば「（品目名）(傷)」ボタンが出る（片方しか無ければ1つだけ。
  腐らない品目は常に「傷んだ」概念が無いので1つのまま）。度合い（何日目か）で
  ボタンをさらに細かく分けることはしない。
  - **「傷んでいない」ボタンを押すと、傷んでいない在庫の中で古い方（ロット）から
    自動的に消費される**（`GameState.remove_inventory_fresh(id, servings)`）。
    足りない分は傷んだ在庫で自動的に補う。「傷んだ」ボタンはその逆
    （`remove_inventory_damaged`。傷んだ分から先に引き、足りなければ
    傷んでいない分で補う）。
  - **判定（-1段階のペナルティ）は「押したボタンの種類」だけで決まる**：
    実際にどちらの在庫が何個使われたかは見ない。「傷んでいない」を押せば、
    たとえ傷んだ分を補って使っていても常に非傷扱い（ペナルティ無し）。
    「傷んだ」を押せば、たとえ傷んでいない分を補って使っていても常に傷扱い
    （-1段階）。ボタンの意味を常に一定にし、プレイヤーが押す前に結果を
    予測できるようにしている。
  - **ボタンの有効条件**：押した側のバケツ自身に1個以上あり、かつ
    「傷んでいない＋傷んだ」の合計が客の人数分（servings）以上あること
    （既存の「端数だけ黙って消費させない」方針を、2バケツ合計に対して適用）。
    片方が0個のボタンはそもそも表示されない。
- Day1の初期在庫も`add_inventory`経由でロットが記録されるだけで、
  特別扱いはしない（Day1開始が1日目としてそのまま数え始まる）。
- **破棄のタイミングはPREP冒頭**（市場へ行く前）。経過4日目以上の**ロットだけ**を
  削除する（同じ品目の新しいロットが残っていれば、品目自体は在庫に残る）。
  同じ日にその品目を買い足しても、既に破棄された後には間に合わない
  （買い足しで「救う」には4日目になる前に補充する必要がある）。
- **市場5店の実購入が実装済みになったため、初期在庫の腐る5品目
  （ココナッツミルク・モツ・肉団子・豆腐・割れた餃子皮）すべてに
  補充経路ができた**（§6「市場での購入 — 残り5店」参照。以前あった
  「4日目以降補充手段が無い」制約は解消済み）。
- 計器盤の `inventory_detail(内訳)` に、傷んだ分があるときだけ内訳を表示する
  （例：`tofu:4(新鮮3・傷1)`。傷んだ分が0なら注記なし）。
- **デバッグ用**：計器盤に「モブ人数」ボタンを追加し、今夜のモブ人数を
  自動→1→2→3→4→自動…と強制指定できる（OPENに入る前に押す。本番のデータ・
  乱数には影響しない、検証用の上書き）。同じ品目を鮮度違いで複数個消費する
  検証など、モブ人数を固定して確認したい場面向け。

### 廃棄（実装済み）

ADJUST中に `[廃棄する]` を押すと、椀を完成させずに引っ込められる。

```
ADJUSTで1〜2個選ぶ → [廃棄する]
  → additions が (0/3) に戻る（judge は「(未定)」に戻る）
  → 鍋の残量が servings 分減る（consume_soup。取り分けた一杯は戻らない）
  → 選んで消費した具材の在庫は戻らない（消費したまま）
  → discard_count（廃棄回数）に+1
  → 同じ客のADJUSTに戻り、選び直せる（[入力完了]は経由しない・次の客へは進まない）
```

- **鍋の残量が客の`servings`に満たないときは`[廃棄する]`は押せない**（実装済み・
  フェーズ1ステップ2）：取り分けられる一杯が無ければ無駄にすることもできない、
  という扱い。`[入力完了]`と同じ判定（`_is_short_now()`）を使う。足りないときの
  進め方は「鍋が尽きたときの対応」参照。

- **同じ客に戻って作り直せる**のが実装上のポイント：当初の依頼では
  「REACTを経由して次の客へ進む（判定なし・売上なし）」を想定していたが、
  実装ではその場でやり直す形になった。「掬った一杯と使った具材は無駄になるが、
  同じ客への接客自体は続く」という仕様として確定。
- 廃棄でやり直した後、`[入力完了]` で提供すれば通常通り SERVE→REACT に進み、
  判定・売上・評判が発生する（廃棄は接客の記録には残らず、最終的に提供された
  分だけが `served` にカウントされる）。
- 計器盤の `discarded(廃棄数)` に廃棄回数が出る。`served(接客数/杯数)` の
  接客数は廃棄を含めず、実際に提供された客の数だけをカウントする。
- `judge_bowl` は呼ばれない（客に見せていないので判定自体が発生しない）。

### 判定（REACT）— 一致数＋favorite で4段階

```
具なし（Ingredients.is_topping を満たす具材が1つも無い）→ 一致数に関係なく常にBAD

一致数 = 3枠の中身のtags と 客の wanted_tags の一致数
        ※鍋(soup)のtags は数えない
        ※wanted_tags 側をループして数えるので、具材を重複させても
          同じtagは1回しか数えられない

  0個 → BAD / 1個 → OK / 2個以上 → GOOD
  favorite（好物の具材id）が入っていれば1段上げる（一致0には効かない）
  → 1個+fav = GOOD / 2個以上+fav = GREAT
```

- **【解消済み】具なしの椀は常にBAD**：DESIGN.mdの「具なしの椀は常に最低評価」に
  実装を合わせた（フェーズ1 ステップ3）。具のタグ（POWER/GENTLE/FILLING/BITE/TREAT）
  を持つ材料が1つも無い椀は、調味料だけ入れていても・何も入れていなくても一致数に
  関係なく強制的にBADになる。苦瓜はBITTERのみ＝味の素材なので具に数えない。
  判定順序は「具なし判定 → 一致数 → favoriteで上げる → 濃さ・傷みで下げる」。
  具なしは判定の下限（BAD）なので、濃さ1/5や傷んだ具材と重なっても二重には下がらない。
  `Ingredients.is_topping(id)` で品目ごとに判定し、`current_bowl["no_topping"]` に
  記録する（計器盤の `judge(判定):` 欄に「・具なし」として表示）。

- 判定は `OpenController.judge_bowl(wanted_tags, favorite)`。結果・一致数・
  favorite の有無・具なしだったか・反応のランダム番号を `current_bowl` に記録する
  （客が替われば消える）。
- 反応 text は Event の `reactions` 辞書（`{BAD/OK/GOOD/GREAT: [2種]}`）から
  結果で引く。**Event データは書き換えない**（受け側が都度読んで選ぶ）。
- 計器盤では反応行の頭に `【GOOD】` のように結果を付けて表示する（データ側には入れない）。

#### 初回好物の開示（実装済み・2026-09-23）

> **【2026-09-28追記・実装済み】** 下記の「まだ知らない客に好物を入れてもGREATにはならない（一致数どおりGOOD止まり）」は**もう現在の実装ではない**。7日版MVPの判定v2（`scripts/judge.gd`・`DESIGN.md`10.3.2）で判定の扱いが変わった：favoriteは**初回から**判定に使われ、2軸一致のときに限りGREATへ1段上げる（1軸一致＋favoriteはOKのまま）。`debug_panel.gd`側でも`knows_favorite()`によるゲート（判定に渡す前に既知でなければ空へ差し替える処理）を廃止し、常に生の`favorite`を`judge_bowl()`へ渡す形に変わっている。好物を**表示する**タイミング（`mark_favorite_known`。既知になるまでSTATE VIEWER上では隠す）だけは変えていない——変わったのは「隠れている間も判定には使う」という点。下記の本文（`_serve_customer()`の説明を含む）は当時の実装の記録として残す。

`BALANCE_REDESIGN_PLAN.md`§8③のうち「初回は退店時に好物を知る」だけを実装した
（商品の購入単位・客数の決め方＝評判式は対象外・今回は無変更。コミット`8867c84`）。
対象は**名前あり客（is_mob:false）だけ**。モブは`favorite`が常に空なので無関係。

- **【4-4b-1で変更】`known_favorites`は撤去され、客ごとの既知状態は`GameState.customer_memory[id].favorite_known`が持つ**（「来店記録（F5・4-4b-1）」節）。以下は旧記述：`GameState.known_favorites`（`{customer_id: true}`）が客ごとの既知状態を持つ。
  `reset_for_new_day()`では触らない（日をまたいで持ち越す）。`reset_for_new_game()`
  でクリアする（新しい周回では全員また初対面から）。`knows_favorite(id)`／
  `mark_favorite_known(id)`の2つの入口経由でのみ読み書きする（`mark_rent_paid()`と
  同じ形）。
- 実装当初は`_serve_customer()`が`judge_bowl()`に渡す好物を、Event側の生の`favorite`ではなく「知っていれば生の値・知らなければ空」に差し替えていた（**まだ知らない客に好物を入れてもGREATにはならない**、一致数どおりGOOD止まり）。
  **2026-09-28追記・F3実装により変更**：このゲートは廃止され、`_serve_customer()`は
  常に生の`favorite`を`judge_bowl()`へ渡す（`debug_panel.gd`該当箇所のコメント
  「knows_favorite()でゲートしてから判定に渡していたが、そのゲート自体を廃止した」）。
  今は**初回から**favoriteが判定に使われる（2軸一致のときだけGREATへ、上記の
  判定v2更新note参照）。表示（既知になるまで隠す）と判定（初回から使う）が分離された。
- 「知った」扱いにする（`mark_favorite_known()`）タイミングは退店時：
  - 名前あり客（1回の接客＝1杯）はその場（判定直後）で確定してよい。
  - **配達員（`aggregate:true`・1杯ずつ3回接客）は1杯目の判定直後では確定させず、
    `_visit_tally`へ生の`favorite`を保持しておき、退店（`_flush_visit_tally()`。
    次の客へ進むときと、フェーズ遷移時の安全網の両方から呼ばれる）の瞬間に1回だけ
    確定させる**。これを間違えて1杯目の直後に確定させると、同じ来店の2杯目から
    もう好物が効いてしまうため、実装時に慎重に扱った点（Claude Codeの実装レビューで
    独自に発見・修正）。
- 計器盤の`Bowl`欄に`favorite_true(本来の好物・デバッグ)`行（判定の前後どちらでも
  Event側の生の値と`known`状態を表示。検証用）、`GameState`欄に
  `known_favorites(好物を知っている客)`の一覧行（【4-4b-1で`favorite_known(好物を知っている客)`に変更】）を追加した。既存の
  `favorite(好物): ...`行（判定に**実際に使った**値。初回は空になる）は変更していない。
- `tests/first_favorite_test.gd`（新規15項目）＋Godot実機のDay1本編（配達員→老婆）で、
  初回はGREATにならないこと・提供直後に`known=true`へ切り替わることを確認済み。
  2回目以降の来店で実際にGREATになる確認は、Day2以降の再来店タイミングでGodot実機で
  引き続き確認予定（【4-3以降】常連は固定日程なので、2回目以降の来店日は「常連の固定日程と
  モブ規則（4-3）」節の表のとおりに決まる。旧`data/day_schedule.json`の抽選ではない）。

### 味と具の軸

| 味（調味料） | タグ | 具（具材） | タグ |
|------------|------|-----------|------|
| ナムプリックパオ | `HOT` | 下処理したモツ | `POWER` |
| ココナッツミルク | `MELLOW` | くず肉団子 | `POWER` |
| 薬膳ナンプラーだれ | `SAVORY` | 豆腐 | `GENTLE` |
| 塩漬けライム | `SOUR`（Day1未使用） | 割れた餃子皮 | `FILLING` |
| 苦瓜 | `BITTER`（Day1未使用） | | |

具の軸は全5種（`FILLING / POWER / GENTLE / BITE / TREAT`）だが、Day1 の在庫は
3軸ぶんのみ。味は舌の感覚、具は体の要求で、軸が重ならない。

### Day1 の3人 ＋ Day2初登場の1人（wanted_tags と favorite）

| 客 | 初登場 | wanted_tags | favorite（仮） | 好みの伝え方 |
|----|:---:|------------|--------------|------------|
| delivery_man | Day1 | `HOT` + `POWER` | tofu | 明言する（今日は辛くしてくれ） |
| thug | Day1 | `MELLOW` + `GENTLE` | meat_ball | 遠回しに漏らす（口当たりがまろくなるやつ） |
| granny | Day1 | `SAVORY` + `FILLING` | offal | 比喩と記憶で語る（薬棚の匂い、腹の底へ残る） |
| officer（警官） | Day2 | `SOUR` + `BITE` | rice_noodle | 昼の市場で明言する（酸っぱい汁。ちゃんと噛めるもの） |

favorite は本来レア食材（たまにしか売っていない／高い）にする予定だが、
現状は検証用に Day1・Day2 の在庫から仮に割り当てている。
officer の favorite（米麺・`FILLING`）は wanted_tags（`SOUR`/`BITE`）のどちらとも
一致しないため、一致数0（具なし、または軸が合わない具材だけ）のときは favorite が
入っていても上がらず BAD のまま（§5「判定（REACT）」の一致0のルールどおり）。
Day2の詳細は次項「Day2の客：新人警官」参照。

### servings（1回の接客で出る杯数）

客データが `servings` を持ち、**1回の調理で複数杯を処理する**。

| 客 | servings | 売上 | 意味 |
|----|---------:|-----:|------|
| delivery_man | 1 × 3回 | 135（2026-09-26改訂：150→135） | 1杯ずつ3回調理（おかわり＋持ち帰り）。下記「1杯ずつ接客する客」 |
| dock_workers（モブ） | 4 | 180（2026-09-26改訂：200→180） | 4人の一団。まとめて1回調理・1回評価 |
| thug | 1 | 45（2026-09-26改訂：50→45） | |
| granny | 1 | 45（2026-09-26改訂：50→45） | |
| **合計** | **9杯** | **405**（2026-09-26改訂：450→405） | 接客は4人 |

- 売上は `PRICE_PER_SERVING × servings`。鍋の残量も servings 分だけ減る。
- 港湾労働者の一団は**判定は1回**。同じ一杯を人数分に分ける扱い（従来どおり）。
- `served` は客単位で記録し、レコードに `servings` を持つ。
  計器盤は `served(接客数/杯数): 4 / 9` の形で両方出す（配達員は1件・3杯）。
- 「今の杯が何杯分か」（`_current_servings()`）は、客のEvent列の**今の位置から先の最初の
  REACT、無ければ直前のREACT**の `servings` を読む（`_react_for_now()`）。
  REACTが1つだけの客は、どの位置でも従来と同じ値になる。

### 1杯ずつ接客する客（配達員・実装済み）

配達員（阿強）は、**同じ客へ3杯を1杯ずつ、会話の合間に出す**
（以前の「servings=3で3杯一括」の割り切りは解消）。会話の正本は本番用会話稿
`１日目_配達員_1(1).md`（`１日目_運び屋_1.md`）。
**この3杯列は、システム整理Eで場面データ（`delivery_man_01.json`の`cups`）から組む形になった**
（専用のEvent列・`THREE_CUPS_EPISODE`は無い。Event列・要求タグ・好物・反応・売上は従来と同一。
下の「複数杯の場面（システム整理E）」節参照）。

```
来店会話
→ 1杯目  ADJUST → SERVE → REACT（評価・反応）
→ 共通会話（K4172・危険手当）
→ 2杯目  ADJUST(new_bowl) → SERVE → REACT（評価・反応）
→ 共通会話（第八码頭・クレーン制御部品・門のおっさん）
→ 3杯目  ADJUST(new_bowl) → SERVE → REACT（持ち帰り。**3-5で判定対象に変更**。下記表参照）
→ 退店会話（名前「阿強」・支払い）
→ 次の客（港湾労働者）へ
```

| 杯 | 誰の分 | 評価 | 評判への寄与 | 売上・鍋 |
|---|---|---|---|---|
| 1杯目 | 阿強本人 | `HOT + POWER`／好物 `tofu` で個別に判定・反応が分岐 | 閉店時のQに算入（`judge:true`） | その場で +45／−1杯（2026-09-26改訂の売価45を反映。旧表記+50は売価改訂の反映漏れだったため合わせて修正） |
| 2杯目 | 阿強本人（おかわり） | 同上（新しい椀。1杯目の具材・評価・傷み印は持ち越さない） | 閉店時のQに算入（`judge:true`） | その場で +45／−1杯 |
| 3杯目 | 第八码頭の労働者への持ち帰り（辛さ控えめ・豆腐多め） | **3-5で変更**：`MELLOW+GENTLE`（「今日の頼み」）で判定（DESIGN.md 10.3.7）。反応の台詞は出さない（`reactions:{}`のまま。持ち帰り先がその場にいないため）。favoriteは持たせない | 閉店時のQに算入（`judge:false`を削除） | その場で +45／−1杯（2026-09-26改訂の売価45を反映） |

- **客キューの上では退店まで1人**：来店〜退店を1本のEvent列にしているので、
  退店会話が終わる（runnerがDONEになる）まで次の客へ進まない。時間帯の移行（濃さ+1）も
  客の切り替え時だけなので、3杯の途中では起きない。
- **杯の切り替え**：2杯目・3杯目の ADJUST に `new_bowl: true`。ADJUSTが current に
  なった瞬間に `OpenController.reset_bowl()` を呼ぶので、具材を選べる前に必ず新しい椀になる
  （独立したEventにしないので、[次のEvent]の操作は増えない）。
- **評判の集約**（実装済み・2026-09-25改訂）：客ごとの即時加算・平均丸め（旧`_visit_tally`の
  `REPUTATION_NAMED`集計、`_flush_visit_tally()`での`roundi`平均）は廃止。1杯目・2杯目の
  判定結果はその都度`_log_quality_counts`（その夜全体の集計。客の種別を問わず1杯＝1件）に
  積まれるだけで、配達員個人としての評判反映は起きない。評判は閉店時に**その夜の全客分を
  まとめて**`_quality_score()`→`settle_reputation()`で1回だけ更新する（下記「評判」参照）。
  配達員だけ評判の影響が大きくなる/小さくなることはない（他の客と同じ1杯=1件の扱い）。
- **提供記録**：杯ごとには積まず、退店時に「売上135・3杯」（2026-09-26改訂：150→135）
  の1件だけ残す（計器盤の接客数は1）。
  `_visit_tally`は`customer`/`sale`/`servings`/`results`/`pending_favorite`のみを持ち、
  評判関連のフィールド（`rep_sum`/`rep_count`）は無い。
- **途中閉店・ゲームオーバー**：`_set_runner_for_phase()` の先頭でも `_flush_visit_tally()` を
  呼ぶので、「そこまでに提供した杯」だけが反映される。反映後は集計を空にするので二重には効かない。
  （評判自体はいずれにせよ閉店時の`_on_day_ending()`まで動かない）
- **鍋不足の保留**：保留はEvent辞書ごと持つので、[戻る]で再開してもフラグ（judge/aggregate）は効く。
  配達員の接客中は「名前あり客が残っている」扱いなので、3杯の途中で自動閉店は起きない。
- **反応文**：会話稿の数行を改行でつないだ1つの文字列（`reactions` の形は従来どおり、各結果1パターン）。
  GREATは会話稿に無いため、既存の「豆腐に気づく」下りを今回の口調で書き起こしたもの。
- **1杯目・2杯目の SERVE**：反応文が「店主「ほら。…」」で始まるので、SERVEは中立なト書き
  「（湯気の立つ椀を置く）」。3杯目は会話稿の「（店主は蓋つきの容器を袋へ入れる）」。
- 集計中は計器盤に `visit(この客の集計)` の行が出る（評価件数・評判増減の合計・売上・杯数）。
- 旧 `_customer_flavor("delivery_man")` は、`is_mob_customer()` と要求タグ・好物の参照元として残す。
- **バランスへの影響**：具材消費は「選ぶたびに3個」から「杯ごとに選ぶたびに1個」になった
  （3枠を毎回埋めれば総量は同じ9個）。[廃棄する]での鍋の損失も3杯分から1杯分に減った。

### Day2の客：新人警官（officer・実装済み）

Day2（`day_count == 2`）に初登場する固定客。表示名「警官」。通常の1杯客
（GREET → ADJUST → SERVE → REACT → 共通会話 → 会計・退店）だが、**昼のPREPと
夜のOPENの2部構成**になっている点だけが他の客と違う。会話の正本は
`Day2_新人警官_1.md`。

```
PREP（officer_01の`market_talk`が今日の枠にあるときだけ。**システム整理Aで`day_count == 2`の直書きから場面データへ移した**。下の「システム整理A」の節参照）
  ベース入手（通常 or クズ野菜）の直後・MARKET Event の前に
  昼の市場の会話を挟む（GREET。「酸っぱい汁。ちゃんと噛めるもの」で
  wanted_tags を仕入れ前に知らせる）
  → MARKET（以降は通常どおり）

OPEN・宵の口（1人目）
  GREET（来店）→ ADJUST → SERVE → REACT（SOUR+BITE／好物 rice_noodle）
  → GREET（共通会話。評価結果に関係なく同じ内容）→ GREET（会計・退店）
  → 次の客（dock_workers。いれば）
```

- **customer_schedule の日別分岐（実装済み）**：`Day1Events.customer_schedule(mob_count)`
  が `GameState.day_count` を関数内で直接読み、`day_count == 2` のときだけ別の並びを
  返す（`_market_options()` が `day_count` を直接読むのと同じパターン）。
  `day_count == 1` と `day_count >= 3` は変更前と同じ並びのまま。
  ```
  day_count == 2 :
    宵の口 : [officer]（＋ mob_count > 0 のときだけ dock_workers）
    夜半   : []（客なし）
    明け方 : []（客なし）
  ```
  夜半・明け方を客のいない時間帯にしても、`OpenController._skip_finished_slots()`
  が読み飛ばして自動的にOPEN終了へ進む（実装済み・確認済み。時間帯そのものが
  空になるのは今回が初めてのケース）。
- **場所代への影響なし**：場所代（チンピラのPAY）は `is_collection_day()`
  （`day_count == 1`）のときだけなので、Day2にチンピラがいなくても影響しない。
- **鍋の濃さが変わらない一晩**：Day2は時間帯が宵の口1つしか使われないため、
  時間帯移行（濃さ+1）が一度も起きない。濃さは仕込み時の3のまま夜が終わる
  （Day1より易しい日になる。意図した設計というより一つの時間帯しか使わない
  ことの自然な帰結として受け入れている）。
- **要求タグは市場より先に知らせる**：昼の市場会話で `SOUR`（酸っぱい汁）と
  `BITE`（噛めるもの）を伝え、好物（米麺）は夜の来店会話で明かす。
  Day2の市場（`塩漬けライム`・`乾燥きくらげ`／`軟骨`・`すじ肉`・`米麺`）は
  いずれも初期在庫に無く、`day2_unlocked`（`day_count >= 2`）で解禁される
  3店（乾物調味料・食肉仲卸・豆腐麺）で購入する。
- **反応文は配達員と同じ形式**：GREAT/GOOD/OK/BADの4結果それぞれ1パターンのみ
  （チンピラ・老婆の「各段階2パターンからランダム」ではない）。会話稿の短い
  やり取りを `_lines_text()` で1つの文字列にし、要素数1の配列にする。
  `judge_bowl()` が選ぶ `reaction_variant`（0/1）は `pool[variant % pool.size()]`
  で要素数1でも安全に0番目を指す。
- **共通会話・会計退店は評価結果に依存しない**：REACTの後は `_customer_extra_events()`
  に足した `"officer"` ケースが、結果に関係なく同じ共通会話＋会計・退店を返す
  （チンピラの場所代Event追加と同じ差し込み口。PAY Eventは無く、売上はREACTの
  `sale` で反映済み）。
- **Day1・配達員への影響なし**：`day_count == 1` の `prep_events()` /
  `customer_schedule()` の出力は変更前と完全に一致することを確認済み
  （変更前後のEvent列をハッシュ化して比較）。
- **Day3以降は今回のスコープ外**：`day_count >= 3` は Day1 の客スケジュールを
  そのまま再利用する（従来どおり）。日別スケジュールを汎用データ駆動の仕組みに
  作り直すのは別タスク（§9「まだ無いもの」参照）。
- 変更ファイルは `scripts/day1_events.gd` のみ（`_customer_flavor()` に `"officer"`
  ケース、`_customer_extra_events()` に `"officer"` ケース、`prep_events()` と
  `customer_schedule()` に `day_count == 2` の分岐を追加）。`debug_panel.gd` /
  `open_controller.gd` 等は無改修（客IDで分岐する処理を増やしていない）。

### モブ客（dock_workers）

```
wanted_tags : 味1つ＋具1つ（名前あり客と同じ形）
favorite    : 持たない（GREATは出ない）
会話        : 一言の要望のみ
```

- **名前あり客と同じ判定処理を通す**。「モブは評価しない」にすると
  「具なしで出せば原価0で儲かる」抜け道ができ、それを塞ぐ特別処理が要る。
  同じ判定なら具なしは自動的に最低評価になり、特別処理が消える。
- 評判の増加量は名前あり客より小さい（下記）。
- 触った感触：会話が短いので、テンポは名前あり客と似ていても負担にならない。
  1回の操作で人数分さばけるので、人数が増えても操作は増えない。
  「客が沢山来ている」演出としても機能する。
- **人数は評判で決まる（実装済み）**。詳細は次項。

### 評判（実装済み・2026-09-25改訂：閉店時1回だけの当夜品質式）

`BALANCE_REDESIGN_PLAN.md`§8④評判の更新（差分表4項目め）。**杯ごとの即時加減算は
廃止し、閉店時（NEXT_DAY→WAKE折り返しの`day_ending`）に1回だけ、現在の評判と
当夜品質Qから新しい値を計算し直す**方式に変わった（コミット`da42bcf`）。

```
1杯の評点：BAD 0、OK 35、GOOD 75、GREAT 100（名前あり客・モブの区別なし・共通）
当夜品質 Q ＝ 評点の合計 ÷ 朝に確定した判定対象杯数
翌日の評判 ＝ round(現在の評判 × 0.7 ＋ Q × 0.3)
```

- `GameState.settle_reputation(quality: float)`が新しい唯一の入口（旧
  `apply_reputation(delta)`は削除）。`DebugPanel._on_day_ending()`が
  `_quality_score(_log_quality_counts, _log_judged_planned_cups)`でQを計算し、
  1回だけ呼ぶ。**OPEN中は`GameState.reputation`が朝の値のまま一切動かない**
  （計器盤の表示も含む）。
- 分母`_log_judged_planned_cups`は「OPEN突入時に先読みした全REACT杯数
  （`_log_planned_cups`）のうち、`judge:false`（配達員の持ち帰り等・評価対象外の杯）を
  除いたもの」。**未提供の杯（部分提供の残り・断られた分）は得点0のまま分母には残る**
  （`_log_quality_counts`に積まれないだけで、先読み時点の杯数からは引かれない。
  「未提供への別の固定減点は重ねない」という§5原文どおり）。
- 分母が0（判定対象の杯が1日も無い、実際には起こらない想定）のときはQ=0として扱う
  （0除算ガード）。
- 名前あり客・モブで感度を分けていた旧`REPUTATION_NAMED`/`REPUTATION_MOB`は廃止し、
  `REPUTATION_SCORE`（GREAT100/GOOD75/OK35/BAD0）1本にまとまった。**どの客でも
  1杯あたりの得点は同じ**（バランス上の実質的な変更。モブは人数が多い分、Qへの寄与が
  相対的に大きくなる）。
- 日次ログに`quality`（その日のQ）・`judged_planned_cups`（Qの分母）を追加し、
  コンソール出力にも`rep=X→Y(Q=Z)`の形で表示する。

### 客数の決め方（実装済み・2026-09-25改訂：総需要ベースの組配分）

`BALANCE_REDESIGN_PLAN.md`§8⑤客数の決め方（差分表5項目め）。旧・評判しきい値表で
モブ人数を直接抽選する方式（`MOB_COUNT_TABLE`/`mob_count_for_reputation()`/
`mob_count_today()`。いずれも削除）を、**その夜の総需要を決めてから、名前あり客の分を
引いた残りをモブの組へ配分する**方式に置き換えた（コミット`da42bcf`）。

```
GameState.total_demand_today()：評判帯ごとの中心値(DEMAND_TABLE)を引き、中心-1/中心/
中心+1を25%/50%/25%で抽選。Day1は9固定（3-5で`Rules.day_overrides(1).fixed_demand`へ
移行。上記「状態変更の入口」参照）。
```

| 朝の評判 | 中心需要 | 実需要 |
|---|---:|---:|
| 0〜19 | 7 | 6〜8 |
| 20〜44 | 9 | 8〜10 |
| 45〜59 | 11 | 10〜12 |
| 60〜70 | 14 | 13〜15 |
| 71〜100 | 17 | 16〜18 |

（§5原文の「基本の仕込み」列＝仕込み3段階化（差分表6項目め）は2026-09-25に実装済み
（下記「仕込みの3段階化」参照）。ただし評判帯とここでの仕込み段階の対応は
**自動選択・強制ではない**：プレイヤーは毎朝どの段階でも自由に選べる。この表は
自動プレイヤーによる収支検証時の想定プレイという位置づけのまま）

- `Day1Events.customer_schedule()`（**Day2以降のauto経路だけ**）が、総需要から
  その日のメイン客（名前あり客）の合計杯数（`_customer_total_servings(id)`。
  客ごとの全REACT Eventのservingsを合算。配達員のDay1専用3杯構成にも自動で
  対応する）を引いて「モブ杯数」を求め、`_plan_mob_groups()`で1〜4人の組
  （`ceil(モブ杯数/4)`組・大きい組から先）へ配分してから枠へ割り当てる。
- 組の配置先は§5原文どおりの固定順（1組目→夜半、2組目→宵の口、3組目→明け方、
  4組目→宵の口。同じ枠に組が2つ入ることもある）。行き先の枠がその日「モブなし」
  （Day1・Day7の明け方）なら夜半へ振り替える（全日で夜半は必ずモブ許可枠）。
- **デバッグ用のモブ人数強制上書き（`_debug_mob_count`≥0）は、この総需要
  システムを通らず、従来どおり枠（宵の口・夜半・明け方）ごとに`_pick_mob()`で
  独立に決める**。

> **【2026-10-01追記・3-5実装済み】** Day1は上記のいずれでもなく、**`Rules.day_overrides(1).mobs`
> （F1・`week7.json`）による固定編成が最優先で使われる**（DESIGN.md 10.3.3・10.9。
> コミット`5d86444`）。`customer_schedule()`は`debug_mob_count < 0`のとき、まず
> `day_overrides(day).mobs`を見る：空でなければその日は固定編成（`{slot, type, count}`の
> 配列）を使い、`_pick_mob()`も総需要システムも通らない。Day1の固定編成は
> 「宵の口＝港湾労働者(dock_workers)2人・夜半＝安宿の夜勤受付(inn_clerk)2人」で、
> 旧`DAY1_MOB_COUNT`（常に4人固定）による「チュートリアルなので評判では揺らさない」
> という挙動を、枠ごとに人数も型も固定するより厳密な形へ置き換えた（実際の客数を
> 13杯→9杯に揃えるための変更。具体的な客構成は直後の表を参照）。
> `DAY1_MOB_COUNT`定数自体は、`_pick_mob()`の直接ユニットテスト（`schedule_test.gd`）と
> デバッグ上書き経路のフォールバック用に残っている。`data/day_schedule.json`（【4-3で削除。Day1のモブ指定は`data/schedules/mob_rules.json`のDay1の日別上書きへ引き継いだ】）の
> Day1夜半`"mob":{"pool":[...]}`は、この固定編成に優先権を譲るためあえて変更して
> いない（実データとしては残るがDay1では参照されない）。

Day1の実際の客構成（3-5で確定・合計9杯）：

| 時間帯 | 客 | 杯 | 要求 |
|---|---|---:|---|
| 宵の口 | 配達員（本人2杯＋持ち帰り1杯） | 3 | 本人=`HOT+POWER`、持ち帰り=`MELLOW+GENTLE` |
| 宵の口 | 港湾労働者(dock_workers)2人 | 2 | `HOT+POWER` |
| 夜半 | チンピラ | 1 | `MELLOW+GENTLE` |
| 夜半 | 安宿の夜勤受付(inn_clerk)2人 | 2 | `MELLOW+GENTLE` |
| 明け方 | 老婆 | 1 | `SAVORY+FILLING` |

- 【4-3で解消：常連は固定日程（21枠）になり、モブの規則は`mob_rules.json`へ分離した】`data/day_schedule.json`のメイン客・モブ抽選プールの構成（Day2〜7がまだ「3枠
  すべてモブ許可」のダミーデータのままである点も含む）自体は無変更（差分表とは
  別枠の「固定日程」。今後の別ラウンドで対応）。
- 総需要の上限（18）とメイン客合計の下限（3。Day2〜7は名前あり客が常に3人＝各1杯）
  から、組数は理論上4を超えない（配置の固定順テーブルが4件しか無いのはこのため）。

### 時間帯（宵の口・夜半・明け方）

OPEN の客キューを時間帯ごとに区切る。`day_count` によって並びが変わる
（実装済み。**Day2の客：新人警官**参照）。

```
day_count == 1（Day1・Day3以降も同じ並びを再利用）:
  宵の口 : [delivery_man, dock_workers]
  夜半   : [thug]
  明け方 : [granny]

day_count == 2:
  宵の口 : [officer, dock_workers]（dock_workersは mob_count > 0 のときだけ）
  夜半   : []（客なし）
  明け方 : []（客なし）
```

- データは `{ name, customers[] }` の配列（`Day1Events.customer_schedule()`）。
  時間帯名と客リストを同居させているので、将来「その時間帯のモブ人数」
  「切り替わりテキスト」を足すときも置き場所が決まる。
- `customer_schedule(mob_count)` は関数の中で `GameState.day_count` を直接読み、
  `day_count == 2` のときだけ別の配列を返す（`_market_options()` が `day_count`
  を直接読むのと同じパターン）。`day_count == 1` と `day_count >= 3` の戻り値は
  変えていない。
- `OpenController` は `slot_index`（何番目の時間帯か）と `index`（その中で何人目か）を持つ。
- **外向きのメソッド名は変えていない**（`current_customer` / `has_more` /
  `advance_customer` / `is_open_done`）。意味は「OPEN全体で見て」のままなので、
  呼ぶ側は時間帯を意識しなくてよい。DebugPanel の客送りは無改修で時間帯をまたぐ。
- 客が0人の時間帯は読み飛ばす（`_skip_finished_slots()`。将来モブ0人の日が
  あり得るための実装だったが、Day2の夜半・明け方＝時間帯そのものが空、という
  ケースで実際に使われた最初の例になった。読み飛ばした先が更に空なら連鎖して
  OPEN終了まで進むことを確認済み）。

### 鍋（残量・濃さ・資源）

```
GameState.soup
  base_id
  tags[]
  remaining_servings   # あと何杯出せるか
  strength             # 濃さ（仕込み時は3。水で0まで下がりうる／だしで5まで
                       # 上がりうる。下記「濃さの上限・下限」参照）
  water_doses          # 今夜使える水の回数（毎朝2回分）

GameState.dashi_units   # 濃縮だしの保有回数分（soup の外）
```

**`dashi_units` だけ soup の外に置く理由**：寿命が違う。
`soup` は `reset_for_new_day()` で消えるが、濃縮だしは**翌日へ持ち越す**
（DESIGN.md 7.6。予備ベース時代の`reserve_base_units`と同じ理由。2026-09-26改訂で
予備ベースから置き換え）。soup の中に入れると毎晩消えてしまう。

### 鍋の状態変化

| 操作・出来事 | 残量 | 濃さ | 資源 |
|-------------|-----:|-----:|------|
| 一杯提供する | −servings | 変化なし | |
| 明け方（最後の時間帯）に入る | **変化なし** | ＋1（1晩1回だけ） | |
| 水を一回足す | ＋2 | −2 | water_doses −1 |
| 濃縮だしを一回足す | **変化なし** | ＋2 | dashi_units −1 |

**（2026-09-26改訂・濃さメカニクス三点セット。`BALANCE_REDESIGN_PLAN.md`§1・§2
差分表8・9・10項目め）3点変更**：
1. **水の効果を濃さ-1から-2に変更**（差分表8項目め）。
2. **濃さを上げる手段を予備ベース／`add_base()`から濃縮だし／`add_dashi()`へ置き換え**
   （差分表9項目め。残量を増やさず濃さだけ上げる役割は同じ。下記「濃縮だしの購入」参照）。
3. **鍋が煮詰まる自動+1を、時間帯が変わるたび（1晩最大2回）から明け方（最後の時間帯）に
   入った瞬間だけ（1晩1回）に変更**（差分表には無いが実装時に発見した論点。旧仕様の
   ままだと目標仕様「開始3、明け方に1回だけ+1、正常域2〜4」の到達点（何もしなければ
   3→4）と合わなくなるため。`OpenController`は無改修（「時間帯が進んだか」だけを返す）で、
   「それが最後の時間帯か」は`slot_index == schedule.size()-1`をDebugPanel側
   （`_advance_open_queue_if_customer_done()`）で見て判定する）。

**残量を増やせる操作は水だけ**（濃縮だしは濃さを上げるだけで量は増やさない）なので、
「鍋を補充できるか」の判定は水の有無だけで決まる。

- **蒸発は入れない**（時間で量は減らない。濃さだけ上がる）。
- **濃さの上限・下限で効果を切り捨てない**（2026-09-26改訂。下記「濃さの上限・下限」
  参照）。旧実装は`clampi`で黙って丸めていたが、今は`can_add_water()`/`can_add_dashi()`が
  「実行後の濃さが範囲に収まるか」を事前にチェックし、収まらない操作はボタン側で
  無効化する。

### 濃さの上限・下限（濃さメカニクス三点セット・実装済み・2026-09-26）

`BALANCE_REDESIGN_PLAN.md`§1・§2差分表10項目め。濃さの範囲を超える操作は、
実行時に`clampi`で黙って切り捨てるのではなく、**その操作ができるボタン自体を
無効化する**方式に変えた（`can_add_water()`/`can_add_dashi()`が事前にガードするので、
`add_water()`/`add_dashi()`側はもうclampiしない）。

```
GameState.STRENGTH_MIN = 1          # 評価が1段階下がる下側の境界（judge_bowl参照）
GameState.STRENGTH_MAX = 5          # 評価が1段階下がる上側の境界（judge_bowl参照）
GameState.STRENGTH_HARD_FLOOR = 0   # 水を足せるかどうかの下限。0＝提供不可
```

- **`STRENGTH_MIN`/`STRENGTH_MAX`は「評価が1段階下がる境界」のまま変えていない**
  （`judge_bowl()`の`bad_strength`判定はこの2つを直接見ており無改修）。水を足すと
  濃さは0まで下がりうるが、これは評価が下がる境界（1）とは別次元の、**提供そのものが
  できなくなる新しい下限**（`STRENGTH_HARD_FLOOR`）。`STRENGTH_MIN`自体を0に変えると
  `judge_bowl()`の「濃さ1で評価-1段階」が壊れる（0と1を取り違える）ため、意図的に
  別の定数として分離した。
- **濃さ0は「提供不可」**：濃さが0の鍋では、名前あり客・配達員はADJUST中に
  `[入力完了]`が無効化される（`_is_strength_zero_in_adjust()`。残量不足の
  `_is_short_in_adjust()`と同じ役割の独立した条件）。万一そこをすり抜けてREACTへ
  到達しても、判定せず保留（`_pending_shortage_ev`）に落ちる安全策を重ねている
  （残量不足のREACT側フォールバックと同じ形だが、こちらは**自動閉店には倒さない**
  ——濃縮だしがあれば`[鍋を見る]`で救える可能性が残るため）。モブ客は
  `_mob_achievable_servings()`が濃さ0のとき強制的に0を返し、既存の「達成可能人数0なら
  断るしか出せない」という団体オーダーの仕組みにそのまま乗る（新しいUI分岐は増やさない）。
- **濃さ0からの回復手段は濃縮だしだけ**：水はこれ以上足せない（`STRENGTH_HARD_FLOOR`で
  塞がる）が、濃縮だしは0+2=2で上限（5）以内に収まるため`can_add_dashi()`がtrueになる。
  だしを持ち合わせていないまま濃さ0に達すると、その夜はだしを買い足せる翌朝まで
  回復できない（資源管理の失敗として許容する。`BALANCE_REDESIGN_PLAN.md`の
  「供給量に廃棄の余裕はない」という設計思想と同じ考え方）。
- **鍋モードの`[戻る]`は水待ち・だし待ちの二重ロック**：`_pot_locked_until_water()`
  （残量0で入室）と`_pot_locked_until_dashi()`（濃さ0で入室）がそれぞれ独立し、
  どちらのロックも「対応する資源が実際に無ければ塞がない」（出口は必ずある）という
  同じ設計。両方のロックが同時に成立していても、それぞれ該当する資源を入れれば解除される。
- **新しい相互作用**：濃さ3スタートのまま水を連続2回使うことはできない
  （1回目で3→1、2回目は1-2<0でブロックされる）。明け方の自動+1（3→1→(+1)→2）を
  挟んで初めて2回使い切れる。

  > **【2026-10-04追記・3-6実装済み】** 「一晩の最大供給＝小12・中15・大18（水2回込み）」
  > という旧目標値は、鍋の同時容量14（下記「鍋の同時容量14」参照）の導入により変わった。
  > 容量ガードのため、水を分散して使っても中仕込み・大仕込みは2回使い切れない
  > （小12・中13・大14。詳細は下記参照）。18という総供給上限の数値自体は
  > DESIGN.md 10.3.8に残っている。【2026-10-18訂正】「実際に到達する経路は無い」は誤りで、営業中の水足しで一晩の総杯数は小12／中15／大18に届く（下の訂正注記と「運営費75の確定」の実測を参照）。

### 鍋の同時容量14（3-6実装済み・2026-10-04・DESIGN.md 10.3.8）

自動試遊レポート（2026-09-26実施）で指摘された「14杯・濃さ3・水2・だし1から
水→だし→水で同時残量18」という不整合（`remaining_servings`に上限コードが
元々存在しなかったため、仕込み杯数が増えると際限なく積み上がっていた）を解消した。
`Rules.pot_capacity()`はF1（3-1）時点で既に実装・`week7.json`に`14`で宣言済み
だったが、`game_state.gd`側のどこからも参照されていなかった（宣言のみ・3-6で消費、
という3-5の`day_overrides.mobs`/`kit`と同じ位置づけ）。

- `can_add_water()`に「`remaining_servings`が`Rules.pot_capacity() - WATER_SERVINGS`
  （14-2=12）以下のときだけ足せる」という条件を、濃さの条件とは独立した`and`条件
  として追加した（水を足すと残量が+2されるため、足した後に容量14を超えないための
  事前ガード。既存の「超える操作はボタン側で無効化し、`add_water()`側ではclampi
  しない」という濃さメカニクス三点セットの方針をそのまま踏襲）。
- `water_reachable()`（だし経由の回復判定）にも同じ容量条件を、だしブーストの判定
  より前の独立したガードとして追加した。濃縮だしは濃さしか上げず残量（容量）は
  回復できないため、「だしを入れれば水が出せるか」を見るより先に、容量超過なら
  即falseにする。
- `add_water()`自体とUI側（`debug_panel.gd`）は無改修。UIのボタン有効・無効は
  すべて`can_add_water()`/`water_reachable()`の戻り値経由のため、ロジック側の
  修正だけで自動的に反映される。

容量ガードの導入により、仕込み段階ごとに「水を使える回数」自体が変わる
（以前は3段階とも水2回を使い切れて小12・中15・大18杯だった）：

| 段階 | 初期残量 | 1回目の水 | 2回目の水（明け方+1後） | 最終残量 |
|---|---:|---|---|---:|
| 小仕込み | 8 | 適用（8→10、濃さ3→1） | 適用（10→12、濃さ2→0） | **12**（変化なし） |
| 中仕込み | 11 | 適用（11→13、濃さ3→1） | **残量13が容量12を超えるためブロック**（濃さは2に回復済みでも入らない） | **13**（旧15から変更） |
| 大仕込み | 14 | **最初から残量14が容量12を超えるためブロック**（濃さ3のまま） | 同様にブロック（明け方+1は濃さ3→4に効くだけ） | **14**（旧18から変更。水0回） |

一晩の総供給上限18（14＋水2回×2）という表示上の数値はDESIGN.md 10.3.8に理論値
として変えずに残しているが、容量ガードのため大仕込みでは水を1回も足せず、実際に
18杯へ到達する経路は無い（中仕込みも13杯が上限で15には届かない）。

> **【2026-10-18訂正・先に直す④の実測】上の2行（「18杯へ達する経路は無い」「15には
> 届かない」）は誤り。** 容量ガードが止めるのは「**鍋に一度に入る量**が14を超えること」
> だけで、営業中に残りが減って12以下になれば水は足せる。実測（鍋レベル8/11/14）：
>
> | | 小 | 中 | 大 |
> |---|---:|---:|---:|
> | 夜の始まりに鍋へ入れられる最大（だしあり／なし） | 12／10 | 13／13 | 14／14 |
> | **一晩に出せる総杯数**（だしあり） | **12** | **15** | **18** |
> | 同（だしなし） | 10 | 13 | 16 |
>
> 上の表の「最終残量」は**夜の始まりの時点で鍋に入れられる量**として読むこと。
> 試遊ハーネスの`TIER_REACH`（12／13／14）は、この「夜の始まりの量」としては正しい。
> 一晩の総杯数は12／15／18で、DESIGN.md 10.3.8の「総供給上限18」とも合う。
> 【2026-10-18再訂正】ただし、ハーネスが仕込み段階を選ぶ基準（`choose_tier()`）に「夜の始まりの量」を使うのは
> 目的に合わなかった（営業中の水足しで足りる夜にも大仕込みを選んでいた）。選ぶ基準は一晩の総杯数12／15／18で、
> 引数`reach_true`で取り直した（§「運営費75の確定」）。

**更新テスト**：`tests/prep_tier_test.gd`のwater_cases（小中大を共有ループで回す
旧実装）を、水の使える回数が段階ごとに異なることを明示する3つの個別ブロックへ
書き換えた。`tests/soup_strength_test.gd`に、容量境界そのもの（残量12は足せる・
残量13は足せない・容量超過時は`add_water()`がno-op・だしで濃さを回復しても容量
超過なら`water_reachable()`はfalseのまま、等）を直接確認する新規シナリオを追加
した。全534件が通過（コミット`b4967db`）。

### 濃縮だしの購入（実装済み・2026-09-26改訂・予備ベースの後継）

食肉仲卸（`meat_wholesale_goods()`）で「濃縮だし」（¥16）を買える
（`day_count >= 2` から。他の追加購入と同じ解禁条件）。市場のUI上は他の具材購入と
同じボタンだが、`inventory`（在庫dict）には入れず、`GameState`側の専用フィールドで
効果だけを適用する（予備ベースと同じ扱い）。

```
GameState.dashi_units   # 濃縮だしの保有回数分
```

- **予備ベースと違い、1周1回の制限・期限・傷みの概念は無い**：市場で**毎日何度でも**
  買える単純なカウンタ。`buy_dashi()`は`dashi_units += 1`するだけ（支払いは呼び出し側
  `_on_shop_item_selected`の役割のまま）。
- **効果は`add_dashi()`**：残量は変えず、濃さ+2（`DASHI_STRENGTH_DELTA`）・
  `dashi_units`-1。`can_add_dashi()`（濃さ+2が`STRENGTH_MAX`(5)以内）が事前ガードする
  ので`clampi`はしない（上記「濃さの上限・下限」参照）。
- **判定には使わない**：濃縮だしは3枠へ入れる具材ではないので、`judge_bowl()`・
  `is_topping()`には一切関わらない。
- **日をまたいで持ち越す**：`reset_for_new_day()`では触らず、`reset_for_new_game()`で
  0に戻る（予備ベース時代の`reserve_base_units`と同じ理由。§11「終了日」参照）。

### 鍋を触る操作

`[鍋を見る]` ボタンで**鍋の操作モード**に入る。

- モード中は `[水を足す] [だしを足す] [戻る]` が出る（既存の OptionsRow を使い回す。
  2026-09-26改訂：`[ベースを足す]`は`[だしを足す]`へ置き換え）
- **EventRunner には一切触れない**。index も status も動かない＝会話が止まるだけ。
  `[戻る]` で止まっていた位置から再開する
- モード中は `[次のEvent]` / `[入力完了]` を無効化（会話が止まることを見た目にも合わせる）
- **ADJUST 中（3枠を選んでいる間）は、原則 `[鍋を見る]` を押せない**（実装変更・
  フェーズ1ステップ2）。既に椀を作り始めているので、今さら鍋を変えても遅い……という
  当初の考え方はそのままだが、**鍋の残量が客の`servings`に満たない（不足）、または
  濃さが0（提供不可）のときだけ例外的に押せる**（`_is_short_in_adjust()`／
  `_is_strength_zero_in_adjust()`。2026-09-26改訂：濃さ0の条件を追加）。補充できる
  ものが何も無ければ`[鍋を見る]`は出さない（入っても出口が無くなるため）。水やだしを
  足して`[戻る]`すると、選んでいた具材を残したままADJUSTに戻れる
  **【2026-10-25・UI準備C④で変更】上の「原則押せない」は廃止した。** ADJUST中も、**足りているときを
  含めて、足せるものがあれば鍋を触れる**（`PlaySession.can_touch_pot()` から、ADJUST中の例外を外した）。
  濃さは判定（REACT）の瞬間に読むので、椀を作る途中にだし・水を足した濃さで判定される
  （`tests/pot_adjust_test.gd`）。**SERVE中（椀を確定してから判定まで）は、今までどおり触れない**
  （判定の前に濃さを変えられないため）。足せるものが何も無ければ、ADJUST中も触れない。
  DebugPanelの`[鍋を見る]`も同じ問いで押せる。本番UIでは、鍋タブでだし・水を押せ、減点の予告の
  「鍋タブでだし +2」「鍋タブで水」がADJUST中にも出る。自動試遊（既存13方針×30シード）は、客の最初の
  イベントで鍋を整える動きなので、結果は変わらなかった（v2と390/390周で全キー一致）
- 資源が尽きた操作はボタンが無効になる
- `[戻る]`が塞がれるのは、水待ちなら「水を足せば解ける」とき、だし待ちなら
  「だしを足せば解ける」ときだけ（`_pot_locked_until_water()`／
  `_pot_locked_until_dashi()`がそれぞれ`can_add_water()`／`can_add_dashi()`と組み
  合わさる。2026-09-26改訂：だし側を追加）。資源が無ければ塞がない＝鍋モードには
  必ずどこかへ抜ける道がある（フェーズ1ステップ1で直した「空の鍋から抜け出せない」
  不具合の再発防止と同じ設計をだし側にも複製）

`add_water()` / `add_dashi()` は**複合操作をまとめた入口**にしている
（`apply_money` のような「量は受け側が決める」形にしない）。
資源の消費と2つの数値の変化が常にセットで、分けて呼べると呼び忘れで壊せるため。

### スマホUI（シェルのみ・実装済み）

常時表示の`[スマホ]`ボタン（`EventRow`）。WAKE・PREP・OPEN（ADJUST中を含む）の
どのフェーズでも常に押せる。押すと**3つ目の入れ子モード**（`_phone_mode`）に入る。
「鍋モード」（`_pot_mode`）・「市場モード」（`_market_shop`）と同じ考え方だが、
この2つより一段上の優先度を持つ点が違う。

- **鍋モード中・市場のどの店の中からでも開ける**（排他にしない）：
  `_update_options_row()`が`_phone_mode`を鍋・市場・ADJUSTのどの判定よりも先に見るため、
  スマホを開いても`_pot_mode`/`_market_shop`の値は裏でそのまま保持される。
  `[閉じる]`を押すと、鍋モード中だったら鍋の続き、市場中だったらその店の続き、
  ADJUST中だったら選んでいた具材はそのままに、それぞれ自動的に復帰する
  （退避・復元の処理は書いていない。値を変更していないので描き直すだけで戻る）。
- **開いている間は`[次のEvent]` `[入力完了]` `[鍋を見る]` `[閉店]` `[次のPhase]`
  `[スマホ]`自身をすべて無効化**し、会話・調理・フェーズ進行を完全に止める
  （デバッグ用の`[Day+1]` `[所持金±50]` `[モブ人数]`は対象外。従来通り押せる）。
- 中身は**レシピ／ニュース／SNS／ログの4タブ＋`[閉じる]`**。今のタブのボタンは自身を
  無効化する（押し直せない）。**4タブすべてが実データ**：SNS（客足予報。下記）、ニュース（日別ニュース。
  下の「日別ニュースと必須情報」節）、レシピ（保存レシピと客ごとの「いつもの」）、ログ（注文の要約と
  今日の会話ログ）。レシピ・ログは下の「レシピ保存・『いつもの』・会話ログ・既読スキップ（手順4-7）」節。
- `_set_runner_for_phase()`（フェーズが変わるたび）で`_phone_mode`・選択中タブを
  既定値にリセットする（鍋モード・市場モードの防御的リセットと同じ扱い）。

#### SNSタブ（客足予報・朝の一画面）（3-7実装済み・2026-10-11・DESIGN.md 10.4）

> **【2026-10-25・UI準備C①】本番UIではこの予報を出さない**（DESIGN.md 10.4）。本番UIのSNSタブは
> DM（下記「ルールと情報の変更（UI準備C）」）。ここ（DebugPanelのSNSタブ）の予報メモは**検証用**として
> 残し、見出しは「◆本日の客足予報（検証用）◆」。以下は、その検証用の予報メモの仕様。

`_format_tonight_memo()`が、WAKEで確定した`GameState.today_plan["slots"]`を
時間帯ごとに並べ、その下に集計を足す。`today_plan["slots"]`が空（起床前など）なら
「SNS：まだ新着はありません」。**表示のみで、ここから仕入れる操作（自動購入）は無い**。
集計は`Forecast`（`scripts/forecast.gd`）が返す。

- **予報の精度は`Forecast.mode()`で2通り**：`Rules.day_overrides(day).forecast`が
  `"exact"`の日（Day1）は`"exact"`、それ以外は`Rules.forecast().total`（`"range"`）。
- **exact（Day1・見出し「本日の客足予報（確定）」）**：総杯数は実際の合計（9杯）。
  配達員は`Forecast.orders_of(cid)`（`customer_events()`のREACTを走査。
  `Day1Events._customer_total_servings()`と同じ流儀で、3杯目の`wanted_tags`を
  別定数に重複させない）から「HOT/POWER×2・MELLOW/GENTLE×1」のように出る。
  モブは「港湾労働者2人（HOT/POWER）」と人数つきで出る。必要数は実際のplanから
  （案は「確定」の1つ）。
- **range（Day2以降）**：総杯数は**実際に引いた値ではなく`today_plan["demand_center"]`
  ±`Rules.forecast().range_width`（1）**の幅（例：「10〜12杯」）。「中心＝実際」に
  読めないための設計。モブは「客層:港湾労働者（HOT/POWER）」と**種類のみ（重複除去・
  人数も組数も出さない）**。種類名は`data/mobs/*.json`の`"name"`
  （`Day1Events.mob_display_name(type_id)`。無ければ種類idをそのまま返す）。
  名前あり客は基本注文（【4-4aで変更】客プロフィールの`wanted_tags`。旧：その日の`customer_data`）と、既知の好物のみ。「今日の頼み」は
  会話で判明するので出さない。
- **必要な味・具の数は2案（range日）**：全タグ合計÷2で実際の総杯数が逆算されて
  幅の意味が無くなるのを避けるため、名前あり客は基本注文から正確に、モブ分は
  「モブ杯数＝`max(案の総杯数−名前あり客の合計杯数, 0)`をplanに出るモブの種類へ
  均等に割り振る」推定にした（`required_estimated()`）。**平均案**＝中心、
  **上限案**＝中心＋幅。実際の組の人数配分は使わない（人数・組数が漏れない）。
  exact日は`required_exact()`（実際のplan）。表示順は味の軸→具の軸（`Forecast.TAG_ORDER`）。
- **在庫との過不足**：`Forecast.supply_tags()`が`GameState.inventory`を
  `Ingredients.tags_for()`でタグ換算（複数タグの品目は各タグに1個ずつ。傷み・鮮度は
  区別せず1個＝1個）、`shortages()`が必要数との差のうち不足のタグだけ「HOTあと2個」の
  形で返す。**タグ単位の個数比較の目安**で、1杯が味＋具の組み合わせでできる点までは
  見ない。案ごとに「不足なし」または不足タグを出す。
- **使える現金**：`Ledger.usable_cash()`＝残金−確保。「使える現金: N円（残金N／確保N）」。
  （**【2026-10-18】確保の定義が変わった**：確保＝まだ払っていない請求（徴収日の場所代90＋
  水道代50）だけ。払い済みの運営費75は含めない。Day1は残金225／確保140／使える**85**
  （運営費65の当時は残金235／使える95。さらに前は確保205／使える30で、運営費を二重に引いていた）。）
  STATE VIEWERの`budget`行の第3項と同じ値。
- **テスト**：`tests/morning_forecast_test.gd`（22件。Day1完全公開・範囲が中心基準・
  モブは種類のみ・使える現金とbudget行の一致・`demand_center_today()`と
  `total_demand_today()`の整合）。全556件成功（コミット`6ea34f1`）。
- **DESIGN.md 6章「スマホ＝操作解禁の合図」との関係**：WAKEには既に
  「スマホを見る。」という一言（`WAIT_INPUT`。演出のみで今回のスマホUIとは無関係の
  別の仕組み）があるが、今回は変更していない。本物のスマホが押せるようになったことで
  この演出とどう繋げる（残す／変える）かは、実機で触ってから決める別タスクとする。

### 計器盤の表示

```
soup(今日の鍋): bone_broth 残量7杯 濃さ3 tags=["meaty"]
pot(鍋の資源): 水2回 / 濃縮だし2回分
```

残量に**分母は出さない**（水を足すと初期値を超えるため。判断材料は
「あと何杯出せるか」と「残りの客が何杯注文するか」の比較）。

### 濃さ・傷んだ具材が評価に影響する

判定に「悪条件による減点」を組み込んだ。順序は
「一致数 → favorite で上げる → 悪条件で-1段階（濃さ・傷んだ具材）」。

```
濃さ 1 または 5      → 減点条件が成立
濃さ 2〜4            → この条件では成立しない
傷んだ具材（3日目）を使った → 減点条件が成立
```

（2026-09-26改訂：濃さの範囲は水・だしの効果変更で0〜5まで広がったが、この
`judge_bowl()`の判定自体は無改修。濃さ0の鍋はこの判定に到達する前に「提供不可」として
別扱いされるため（§5「濃さの上限・下限」参照）、`judge_bowl()`が濃さ0を見ることは無い）

- **減点は条件の数にかかわらず最大-1段階**。濃さが悪く、かつ傷んだ具材も
  使った場合でも-2段階にはならない（実装済み・確定）。
- **鍋・具材の状態で評価を上げることはしない**。悪い状態だけが足を引っ張る。
- **favorite の後に適用するので、悪さは favorite で取り返せない**。
  好物を入れても、鍋が崩れていたり具材が傷んでいれば最高評価には届かない。
- 判定時点の濃さを `current_bowl["strength_at_judge"]` に固定して残す
  （`reaction_variant` と同じ考え方。判定後に鍋をいじっても表示がずれないように）。
  傷み判定も、選んだ時点で椀に記録する（在庫が0になってキーが消えると
  後から状態を引けなくなるため）。
- `judge_bowl` が `GameState.soup.strength` を直接読む（`bowl_addition_tags()` が
  鍋を直接見るのと同じ流儀。wanted_tags/favorite は客ごとのデータなので引数、
  strength は鍋の状態なので判定側が見に行く）。
- 計器盤のjudge欄に減点理由を表示する：「濃さ○で1段下げ」／「傷んだ具材で1段下げ」／
  両方成立のときは併記（ただし段階は-1のまま）。

### 鍋が尽きたときの対応（実装済み・フェーズ1ステップ1・2）

**【2026-09-23：モブ客（団体オーダー）はこのフロー自体の対象外に変更】** 「拒否と部分提供」
（上記「団体客の人数調整」参照）の実装で、モブ客の鍋不足はこのフロー（下記）を経由せず、
達成可能人数の計算に鍋残量を含めた上で「N人分を提供／注文を断る」の選択に一本化された。
以下の記述（`[入力完了]`のブロック・保留・自動閉店）は**名前あり客・配達員には無変更の
まま適用される**。

**2026-09-26改訂：濃さ0（提供不可）という、残量不足とは独立したもう1つの「詰まり」が
増えた**（濃さメカニクス三点セット。§5「濃さの上限・下限」参照）。判定条件・関わる
関数はそれぞれ別（残量不足＝`_is_short_in_adjust()`/`_no_resources_left()`、濃さ0＝
`_is_strength_zero_in_adjust()`/`can_add_dashi()`）だが、`[鍋を見る]`・`[入力完了]`・
`[閉店]`をブロック／解禁する役割の持たせ方は同じ形を複製している。以下は残量不足側の
記述（無変更）。

**共通ルール（実装済み・現在の一次判定）**：鍋の残量が客の`servings`以上
あるときだけ、提供（`[入力完了]`）も廃棄（`[廃棄する]`）もできる
（`_is_short_now()`）。ADJUST中（3枠を選んでいる間）にこれが成り立たない
（不足）とき：

```
ADJUSTで不足（残量 < servings）
  ├ [入力完了] [廃棄する] … 無効（足りない一杯は出すことも捨てることもできない）
  ├ [鍋を見る] … 例外的に押せる（原則ADJUST中は押せないルールの例外）。
  │   水があれば有効。無ければ出さない（入っても出口が無いため）
  │     └ 鍋モードで水を足す → 足りれば [戻る] でADJUSTへ戻り、
  │       選んでいた具材を残したまま続けられる（再チェックはADJUSTに
  │       戻った時点の残量で自然に行われる＝ [入力完了] がまた無効かどうかで決まる）
  └ [閉店] … 水が無くて補充できないときだけ有効（`_can_close_now()`）。
      押すと理由テキスト「（今日はここで店じまいにする。）」を添えて CLOSE へ
```

- **残量を増やせるのは水だけ**（§5「鍋の状態変化」参照）なので、「補充できるか」の
  判定は水の有無だけで決まる（`_no_resources_left()` は `not can_add_water()`）。
- この一次判定のおかげで、**REACT（提供の確定）に来る時点では常に残量が足りている**
  （足りないままADJUSTを抜ける経路が無いため）。

**REACTの分岐（実装済み・現在は使われない保険として残す）**：上記のADJUST側の
判定より前に作った分岐で、REACT自身も「足りない」を検知したときの動きを持つ。
通常プレイではADJUSTで先に止まるため到達しないが、削除はせず安全網として残した。

```
条件1: 名前あり客（delivery_man/thug/granny）が、今の客を含めて
       これ以降もう出てこない（残っているのはモブだけ、または誰もいない）
条件2: 水が無い（ベースは残量を増やせないので条件から外した）

条件1 かつ 条件2（両方）   → 自動的に CLOSE へ強制移動（理由「（鍋が尽きた。今日はもう終いだ。）」）
それ以外（片方だけ／どちらも不成立） → 保留にする（_pending_shortage_ev。下記「プレイヤーが選ぶ画面」）
```

- **【変更済み】「どちらも不成立→薄めて出る」は無くした**：以前はここに落ちると
  水もベースも使わず満額で提供できてしまっていた（例：残量1杯で3杯注文でも150の
  売上）。ADJUST側の一次判定で本来ここには来ないはずだが、保険としてもこの分岐に
  落ちたら必ず保留にし、薄めて出す道は残さない。
- **【解消済み】空の鍋から抜け出せなくなる不具合（フェーズ1ステップ1で修正）**：
  以前は残量0・水0で普段どおり`[鍋を見る]`に入ると出口が無くなっていた。今は
  `[戻る]`が水待ちで塞がれるのは「水を足せば解ける」ときだけで、水が無ければ
  塞がない＝鍋モードには必ず抜ける道がある。
- **【解消済み】SERVE〜REACTの間に鍋を触ると判定が変わる不具合（フェーズ1ステップ4）**：
  判定（`judge_bowl`）はREACTが適用される瞬間の濃さをその場で読むため、椀の中身
  （additions）はADJUSTで確定済みでも、提供の台詞（SERVE）が出てから次へ進むまでの
  間に鍋を触って濃さを変えると、判定を後から動かせてしまっていた。`DebugPanel`に
  `_is_awaiting_react()`（現在のEventがSERVEか）を追加し、`[鍋を見る]`の無効化条件
  （`_update_options_row()`の`pot_disabled`）にこれを足して、SERVE中は鍋モードに
  入れないようにした。`[廃棄する]`は選択肢行がADJUST中しか描画されない、`[閉店]`は
  `_can_close_now()`がSERVE中は`false`になる、のでどちらも元々このタイミングでは
  操作できず、塞ぐ必要があったのは`[鍋を見る]`だけだった。REACT自体はEventが
  currentになった瞬間に同じ処理内で即座に適用される実装（判定前に「REACTだけ見えて
  いてまだ適用されていない」状態は存在しない）なので、SERVEを塞ぐだけで判定前に
  鍋をいじれる隙間は無くなる。

- `FlowController.force_phase(phase)` という新しい入口を追加。
  既存の `advance_phase()`（一方向に1つ進む）とは別に、任意のフェーズへ
  直接飛ばせる。**フェーズゲートを通さない**ので、乱用しないよう
  呼び出し側の責任と明記してある。
- CLOSE に入るとき理由テキストを先頭に差し込む（`close_events()` 自体は変えない）。
  自動閉店は「（鍋が尽きた。今日はもう終いだ。）」、選択での閉店は
  「（今日はここで店じまいにする。）」。
- **Day1 の並びでは、ADJUST側の一次判定が先に効くため、REACT側の分岐（自動閉店・
  保留のどちらも）は通常プレイでは発火しない**。動作確認は customer_schedule() の
  末尾に検証用のモブ客を一時的に足して行い、確認後に削除した。

### プレイヤーが選ぶ画面（`_pending_shortage_ev`が立ったとき）

`[入力完了]` の隣に `[鍋を見る]`、その隣に `[閉店]` を常設。
`[閉店]` は保留中、または「ADJUST中で残量不足かつ水が無い」、または「ADJUST中で
濃さ0かつだしが無い」ときだけ有効（`_can_close_now()`。2026-09-26改訂：3つめの
条件を追加）。それ以外は常に無効。

以下は残量不足で保留に落ちた場合の記述（無変更）。**濃さ0（提供不可）でも同じ
`_pending_shortage_ev`に落ちるが、原因・回復手段は独立している**（濃さ0は
「濃縮だしがあれば有効」「だしを入れると解除」となり、自動閉店には倒さない。
§5「濃さの上限・下限」参照）。

```
保留中（REACT側の分岐で到達。通常プレイでは発火しない＝上記参照）
  ├ [鍋を見る]（作り直す）… 水があれば有効
  │   └ 鍋モードに入る。残量が実際に0以下なら、水を入れるまで
  │      [戻る] が無効（だしだけでは煮出す水が無く意味がない。水が無ければ塞がない）
  │      水を入れると解除 → [戻る] で提供を続行 する
  └ [閉店] … 有効。押すと CLOSE へ
```

- EventRunner には一切触れない（ADJUST と同じ流儀。保留は DebugPanel 側の
  フラグ `_pending_shortage_ev` で足止めする。REACT に新しい type を増やさない）。
- 鍋を閉じる条件は「鍋モードにどうやって入ったか」ではなく
  「**残量が実際に空かどうか**」で判定する。保留経由でも普段の任意タイミングの
  訪問でも同じルールが自然にかかる。
- `[戻る]` で提供を再開するとき、**足りているか再チェックはしない**（一度作り直すと
  決めたら、その結果のまま提供する）。
- 断ったとき（[閉店] を選んだとき）の評判への影響は**今は無し**。
  評判にインフレが見られたら検討する。
- **【解消済み】閉店で場所代を避けられる不具合**：徴収日に、場所代（チンピラのPAY）
  より前でこの`[閉店]`（またはADJUST側の`[閉店]`、鍋が尽きての自動閉店）を押すと、
  場所代を払わずに済んでしまっていた。今は`GameState.rent_paid_today`で「その日
  もう払ったか」を持ち、まだなら閉店の直前に`_reason_after_collecting_rent()`が
  `RENT_PRICE`（90。2026-09-26改訂：150→90）を特別請求する。払えなければ通常の場所代と同じくゲームオーバー、
  払えれば理由テキストに一言添えて（例：「今日はここで店じまいにする。ただし、
  今月の場所代は先に払わせてもらった。」）CLOSEへ進む。チンピラの番で通常どおり
  払われている場合は素通りする（二重請求しない）。詳細は§11参照。

### 未実装

- **市場で濃縮だしを買う操作は実装済み**（食肉仲卸・¥16・1周1回の制限や期限は
  無く毎日何度でも購入可。2026-09-26改訂：予備ベースの後継。§5「濃縮だしの購入」参照）
- 濃さの表示名（水っぽい・煮詰まりすぎ 等。今は数値のみ）
- 断ったときの評判への影響（評判にインフレが見られたら検討）
- 品目ごとに腐敗速度を変える・傷みからの回復（今は一律2日で新鮮→3日目で傷む）
- 評判の上限・逓減調整（評判20以上の帯はDay1だけでは到達確認できていない）
- **Day2の客データ・会話は新人警官（officer）を実装済み**（§5「Day2の客：
  新人警官」参照）。Day3以降はまだDay1の再利用のまま（日別スケジュールの
  汎用データ駆動化・残りのメイン客・ランダム再来店は今後のテーマ）


---

## 6. Day1 の内容（実装済みの台本）

### WAKE（日々の運営費の支払いは2026-09-26改訂・場所代/水道代の再編＋日々の運営費。処理の順序は2026-10-11・4-1で変更→「朝の保存と1枠セーブ（4-1）」参照）

> **【2026-10-25・UI準備D・D-4】以下の「WAKEで日々の運営費を天引き」は、今は「WAKEでは払えるかだけを見て、運営費75を支払い予定として確保（`Ledger`の`reserve`、`ref:"operating"`）し、市場を出るとき（`PlaySession.exit_market`）に引く」に変わった。**払えない朝（残金＜運営費）のゲームオーバーは今までどおり朝（市場の前）で、所持金は動かない。朝の保存の辞書は運営費を確保する前（所持金は朝の値）のままで、再挑戦・続きからでWAKEをやり直すと確保も1回だけ付く。引いた時点で`daily_cost`を記帳し確保を解く（`release`、`ref:"operating"`。日次ログのキー・金額は変わらない）。市場を通らずに開店へ進むときは開店に入るときに引く（保険）。画面の文は朝「水と炭の支払い（運営費 ¥75）は、市場を出るときに払う。」、市場を出るとき「水を汲み、炭を買った（−¥75）。」。
起床 TEXT → スマホ（WAIT_INPUT で停止）→「今日の分を取っておく」TEXT →「準備へ」TEXT

- **`DAILY_OPERATING_COST`(現在75。当時80)は、この4つのEventが動き出すより前に
  `debug_panel.gd._set_runner_for_phase(WAKE)`が直接支払う**（`wake_events()`の
  中にPAY Eventとしては置かない）。理由：WAKEは`_phase_can_skip=true`で
  `[次のPhase]`がrunnerを1つも消化せずに先へ進められるため（§3「フェーズゲート」
  参照）、支払いをEvent列に頼ると毎回スキップできてしまう。水道代の
  `_visit_water_stall()`と同じ「Eventを介さず直接コードで払う」方式に揃えた。
- 払えずゲームオーバーになったときは、直後に`flow.set_runner(Day1Events.wake_events())`
  を呼ばずに`return`する（`force_phase(GAME_OVER)`が既に同期的に
  `_set_runner_for_phase(GAME_OVER)`を呼んでrunnerを組んでいるため、呼ぶと
  上書きしてしまう）。
- `wake_events()`内の3つ目のTEXT「共同水道と炭屋への払い（¥75）は、もう済ませた。」
  は表示専用（効果なし。金額は`DAILY_OPERATING_COST`から埋め込む）。実際の天引きは
  WAKEで済んでおり、確保にも積まない（先に直す③）。【2026-10-18・`ad4e68f`】以前は
  「市場を出るときにまとめて渡す分として先に取っておく」という前振りだったが、
  払い済みで確保もしない今の動作とずれたため「もう済ませた」に変えた（文の数・種類は
  同じ）。市場を出る場面の「共同水道と炭屋に寄り、市場を出た。」はそのまま。

### 支払い予定（`pending_bills_today`・表示専用・実装済み・2026-09-26改訂）

> **【2026-10-25・UI準備D・D-4】名前を「確保」から「支払い予定」にそろえた**（本番UIの予算の枠。STATE VIEWER〔検証用〕は「確保」のまま）。支払い予定＝日々の運営費（水と炭）75（市場を出るまで）＋徴収日（Day1）の場所代90・水道代50（払うまで）。**残金は所持金そのもの**、使える＝残金−支払い予定。Day1の朝は残金600／支払い予定215／使える385（初日セットのあとは使える175）。場所代・水道代を払うタイミングは変えていない（水道代＝市場を出るとき、場所代＝開店中のチンピラの来店。閉店直前の特別請求も今までどおり）。

> **【2026-09-28追記・F4実装済み】** 以下は`pending_bills_today`フィールドが
> 存在していた時点の記録（履歴として残す）。F4（帳簿）の実装により
> `pending_bills_today`・`set_pending_bills_for_today()`・
> `settle_daily_cost_pending()`はすべて削除された。表示専用の「支払い予定」は
> 今は`Ledger.pending_bills_today()`（`GameState.ledger`から`reserve`/`release`の
> 差分を都度計算）に置き換わっている。STATE VIEWERの表示も
> `budget(残金/確保/使える): N / M / N-M`という形に変わった（`debug_panel.gd`
> `_format_game_state()`）。moneyそのものに影響しない二次的な値、という性質は
> 変わっていない。以下の`set_pending_bills_for_today()`等の説明は当時の実装の
> 記録として残す。
>
> **【2026-10-01追記・3-5実装済み】** F4導入時点の確保額（徴収日は運営費80＋
> 場所代90＝170）には水道代が含まれていなかった（試遊時に指摘された「予算表示の
> 不一致」の原因そのもの）。3-5（DESIGN.md 10.3.5）で水道代50も確保対象に加え、
> 徴収日のWAKE直後の確保額は**170→220**（80＋90＋50）になった（3-8で運営費が65になったため、当時は**205**＝65＋90＋50。現在は下の2026-10-18訂正のとおり運営費を含めず140）。`[市場を出る]`時に
> 水道代の支払いと同時に`Ledger.record("release", WATER_PRICE)`を呼ぶことで対にし、
> 実際の支払いタイミング（水場訪問時）自体は変えていない。
>
> **【2026-10-18訂正・先に直す③`c5d1fae`】確保の定義を「まだ払っていない請求だけ」に
> 直した。** WAKEは運営費65を直接払った**うえで**同じ65を`reserve`にも記帳しており
> （市場を出るときに`release`で対にしていた）、使える現金（残金−確保）が毎日65少なく
> 出ていた。直し：WAKEでは徴収日の**場所代90＋水道代50＝140だけ**を`reserve`に記帳し、
> 非徴収日は記帳しない（ledgerの行数が減るが集計には無関係）。市場を出るときの運営費
> `release`も対で外した（場所代・水道代の`release`は払った瞬間のまま）。上の「205」は
> 旧値で、この訂正の時点の徴収日（Day1）は**確保140／使える95**（運営費75にした2026-10-18以降は使える85）。`RepairFund.safe_limit`の式は
> 変えていない（基金はCLOSEで使い、そこでは確保が通常0。翌日の運営費は`next_day_reserve`が
> 別に引くので二重ではない）。試遊39本・基金方針の結果は変わらなかった（使える現金を
> 判断に使っていないため）。テストは`upkeep_test`の期待値（確保140／使える95）を直した。
> なお朝の文は、運営費がWAKEで払い済みなので今の動作とずれていたため、
> 「共同水道と炭屋への払い（¥65）は、もう済ませた。」に直した（`ad4e68f`・文言のみ・修正済み。金額は定数から埋め込むので、運営費75の現在は¥75）。

日々の運営費は実際にはWAKEで即天引き済みだが、プレイヤーへは「今日まだ物語上の
けじめが付いていない金額」として、STATE VIEWERのmoney行に`（支払い予定NN）`の
注記で見せる（`GameState.pending_bills_today`。moneyそのものには影響しない
二次的な値）。

- `set_pending_bills_for_today()`（WAKEで確定）… 徴収日は`DAILY_OPERATING_COST + RENT_PRICE`
  （現在の値で165＝75＋90。運営費75の値。3-8で65にした後は155、当時は170）、それ以外は`DAILY_OPERATING_COST`のみ（現在75。3-8で65、当時80）。水道代
  （`WATER_PRICE`）は含めない（水場は押した瞬間にその場で金額が見えるので
  先出しで見せる必要が薄いため）。
- `settle_daily_cost_pending()`（`[市場を出る]`を押した瞬間に決済）… 運営費（現在75。3-8で65、当時80）を引く
  （0未満にはクランプ）。
- `mark_rent_paid()`（場所代を払い終えた瞬間に決済。通常のチンピラPAY経由でも
  未払いのままの特別請求経由でも、どちらから呼ばれても同じ1箇所で決済される）
  … 90を引く（0未満にはクランプ）。
- 徴収日は「WAKE直後155（3-8以降。当時170）→（市場を出る）→ 90 →（チンピラへ場所代を払う）→ 0」、
  非徴収日は「WAKE直後65（3-8以降。当時80）→（市場を出る）→ 0」という推移になる。0になると
  STATE VIEWERの注記自体が消える。

### PREP（市場を経由する形に変更・7.7／仕込み3段階化は2026-09-25改訂）

```
（Day1のみ：初日セット購入イベント。TEXT「いつもの仕入れ先で、仕込みに使う分を
  まとめて受け取った。」→ PAY(kind:"kit"、¥210) → ADD_ITEM×7（単価付き。詳細は
  上記「初日セット」参照）。`Rules.day_overrides(day).kit`が宣言されている日だけ
  差し込まれる・3-5実装済み）
食肉売場へ来た（TEXT）… 所持金 >= 仕込み最安値(小仕込み=80) の場合
  PREP_TIER（options=小8杯/80・中11杯/110・大14杯/140）… ここで止まる（WAITING_INPUT）
    選ぶと即座に GameState.apply_money(-価格) → 選んだ段階のラベルTEXT →
    ベース受け取り（ADD_ITEM soup_base）… 残りのPREP列を選択後に組み立てて差し替える
端材屋（半端市「拾味」）へ来た（TEXT）… 所持金 < 仕込み最安値(80) の場合
  代金なし・クズ野菜を譲ってもらう（ADD_ITEM soup_base、PAYなし。杯数は小仕込みと
  同じ8固定）… 3段階を選ばせず自動でこちらへ
（Day2なら新人警官の立ち話）
MARKET（options=6店舗。2026-09-26改訂：水場のボタンを廃止し7→6）… ここで止まる（WAITING_INPUT）
  食肉仲卸 … Day1は自動で済んでいるため「（訪問済み）」表示でグレー。
    day_count>=2で解禁され、モツ・軟骨・すじ肉を追加購入できる（下記参照）
  端材半端物 … Day1にクズ野菜ベースを譲ってもらった日だけ「（訪問済み）」表示で
    グレー。それ以外（通常のDay1・Day2以降はクズ野菜の日でも）はday_count>=2で
    解禁され、くず肉団子・割れた餃子皮を購入できる
  青果（永順青果） … day_count >= 2 で押せる（実際に買い物できる・下記参照）
  乾物調味料／豆腐麺／海鮮 … day_count >= 2 で押せる（実際に買い物できる・下記参照）
  [市場を出る]（OptionsRow内の専用ボタン）… 押すと退出。水道代の支払い（後述）は
    ここで自動的に済む。あわせて日々の運営費の支払い予定（表示専用）も決済する
仕込み（REMOVE_ITEM soup_base）
「共同水道と炭屋に寄り、市場を出た。」TEXT（表示専用・2026-09-26改訂）
SET_SOUP（servingsは選んだ段階の杯数。クズ野菜の日は濃さ1スタート・下記
  「クズ野菜ベース」参照）
```

- **水場は市場のボタン一覧には出さない**（2026-09-26改訂・場所代/水道代の再編：
  以前は「水場」という7店舗目のボタン（押すと水道代PAY・専用の訪問セリフ）が
  あったが、廃止した）。水道代の支払い自体（`_visit_water_stall()`）は残っており、
  **`[市場を出る]`を押した瞬間、まだ水場に寄っていなければ必ず自動で1回呼ばれる**
  （払わずに素通りする抜け道を作らない。押し忘れも起こらない）。
- MARKET中は `[次のEvent]` / `[入力完了]` を無効化する。抜ける経路を
  `[市場を出る]`だけに絞り、自動訪問の安全策を必ず通す。
- MARKETは新しい Event type だが、EventRunnerは無改修（`options`を持つ
  Eventは型を問わず入力待ちになる、というSTEP17.6の一般化ルールに乗っている）。
- 水場の処理（水道代PAY）はEventRunnerの流れの外で行う。`[鍋を見る]`中の
  `[水を足す]`と同じ構造（受け側が直接GameStateを呼ぶ、状態が止まったまま操作できる）。
- **PREP_TIER中も`[次のEvent]`/`[入力完了]`を無効化する**（実装済み・2026-09-25改訂。
  `_is_in_prep_tier()`。MARKETと同じ理由：選ばずに素通りされると、その先の
  ADD_ITEM/SET_SOUPが無いまま仕込みが成立しなくなるため。抜ける経路を3段階の
  ボタンだけに絞る）。詳細は次項「仕込みの3段階化」参照。
- **日ごとの解禁（実装済み・確認済み）**：各店の `enabled` はデータ側
  （day1_events.gd の `_market_options()`）が `GameState.day_count` を読んで
  都度計算する。水場は上記のとおりボタン自体が無いため対象外。残る6店
  （食肉仲卸の追加購入・青果・乾物調味料・豆腐麺・海鮮・端材半端物）は
  `day_count >= Rules.market_open_from_day()`（値は2。**システム整理Aで直書きから置き換え**）で一斉解禁（Day1はグレーアウト、Day2以降は全店押せる）。
  **食肉仲卸・端材半端物の「（訪問済み）」表示はDay1限定**：その日に自動で
  済んだ方（通常は食肉仲卸、クズ野菜の日は端材半端物）だけにグレーの理由と
  して付き、day_count>=2になると外れる。クズ野菜の日でも端材半端物で購入
  できるようにするための決定（外さないと、一番お金が無い日にこそ一番安い
  商品＝くず肉団子・割れた餃子皮が買えなくなってしまうため）。
  **Day2は新人警官（officer）が初登場する専用の客スケジュールになった**
  （§5「Day2の客：新人警官」参照）。ベース入手の直後・MARKETの前に昼の市場の
  会話が挟まる点だけがDay1のPREPとの違いで、それ以外（食肉仲卸／端材屋の分岐・
  MARKET・仕込み・SET_SOUP）は共通のまま。Day3以降はDay1の客スケジュールを
  そのまま再利用する（従来どおり）。
  ※ `enabled` はEvent列生成時点の値を持つ（他店と同じ既知の制約。フェーズへ
  再突入しないと新しい値を見ない）。
- 押した店だけ訪れる（全店を回る必要はない）。店同士は自由に行き来できる
  （どの店からも他の店・市場を出るへ戻れる）。

### 仕込みの3段階化（実装済み・2026-09-25改訂）

`BALANCE_REDESIGN_PLAN.md`§1・§2（差分表6項目め「仕込み」・7項目め「鍋の同時
容量」）。従来は食肉仲卸で固定¥80・10杯だったのを、小/中/大の3段階から毎朝選ぶ
形に変えた（コミット`9a49e90`）。

| 段階 | 杯数 | 価格 | 水2回込みの一晩の最大供給 |
|---|---:|---:|---:|
| 小仕込み | 8 | 80 | 12 |
| 中仕込み | 11 | 110 | 15 |
| 大仕込み | 14 | 140 | 18 |

- `Day1Events.PREP_TIERS`（3段階のid/label/price/servings）・`prep_tier_options()`・
  `prep_tier_by_id(id)`を新設。`GameState.SERVINGS_PER_BASE`は全呼び出し元が
  PREP_TIERSの値に置き換わったため削除した。`GameState.BASE_PRICE`（80）はこの時点
  では予備ベース購入（`buy_reserve_base`）専用に意味を分離しただけだったが、
  **2026-09-26（濃さメカニクス三点セット）で予備ベースごと濃縮だしへ置き換わり、
  `BASE_PRICE`自体が削除された**（意味を分離しておいたおかげで、仕込み額の閾値
  （`PREP_TIERS[0].price`）は巻き添えを受けずに済んだ。§5「濃さの上限・下限」参照）。
- **選択の仕組み**：食肉仲卸での固定PAYを、`PREP_TIER`という新しいEvent型
  （MARKETと同じ`options`方式。3ボタンにラベル・価格・杯数を表示し、所持金不足の
  段階はボタン側で無効化）に置き換えた。選ぶと即座に`GameState.apply_money(-価格)`
  し、選んだ段階の杯数で残りのPREP Event列（ベース受け取り→(Day2なら立ち話)→
  MARKET→仕込み消費→SET_SOUP）を`Day1Events.prep_after_tier_events(tier, false)`
  で組み立て直し、`flow.set_runner()`でrunnerごと差し替える（`prep_events()`を
  呼んだ時点ではまだ段階が決まっていないため、SET_SOUPの杯数はここで初めて確定する）。
- **「index 0の効果は適用されない」という既存仕様への対処**：`[次のEvent]`/
  `[入力完了]`は「indexが動いたときだけ効果を適用する」実装のため、`set_runner()`で
  差し替えた直後の先頭Eventは誰も効果を適用しない（`_load_current_customer()`が
  客ごとに使っている既存パターンと同じ）。`prep_after_tier_events()`はこれに対処し、
  差し替え後の列の先頭を必ず効果の無いTEXT（「○○にした。」）にしている。
- **鍋の同時容量拡大（差分表7項目め）は追加実装なしで達成**：`remaining_servings`
  に上限を設けるコードはもともと存在せず（`add_water()`は`+= WATER_SERVINGS`と
  単純加算するだけ）、仕込み杯数を増やすだけで水込みの上限（12/15/18杯）も
  自動的に伸びる（【3-6・2026-10-18訂正】3-6で鍋容量14のガードが入った。「夜の始まりに
  入れられる量」は12／13／14だが、営業中の水足しで一晩の総杯数は12／15／18のまま。
  詳細は「鍋の同時容量14」の訂正注記）。
- **新規テスト**：`tests/prep_tier_test.gd`（33項目。3段階それぞれの価格・杯数・
  水込み上限、端材屋フォールバックの杯数・支払い無し・濃さ1、所持金不足の段階を
  直接選ぼうとしても何も起きないこと（ボタン無効化の二重防御）、
  `prep_after_tier_events()`の先頭が必ずTEXTであること、Day2の立ち話挿入、
  既存`prep_events()`の先頭（傷み通知）の回帰）＋全7スイート404項目（既存分含む）
  ＋Godot実機で確認済み。

### クズ野菜ベース（お金が無い日の代用・実装済み／仕込み3段階化に伴い2026-09-25改訂）

所持金が仕込み最安値（`Day1Events.PREP_TIERS[0].price` = 80）未満のとき、
3段階から選ばせず食肉仲卸ではなく**端材屋**（端材半端物の店・半端市「拾味」）へ
自動で向かい、代金なしでベースを譲ってもらう。

- **判定タイミング**：PREPのEvent列を生成する瞬間に`GameState.money`を見て
  固定する（`_scraps_base = money < Day1Events.PREP_TIERS[0].price`。市場の
  `enabled`と同じ扱い）。**`GameState.BASE_PRICE`は見ない**（2026-09-25改訂：
  値はどちらも80で同じだが、`BASE_PRICE`は予備ベース購入専用の別概念として
  分離したため、意図的に参照先を分けた。2026-09-26改訂：`BASE_PRICE`自体はその後
  削除されたが、この閾値は元々`PREP_TIERS[0].price`しか見ていなかったため無影響）。
  プレイヤーが選ぶ場面ではなく自動的に切り替わる。WAKE中など、PREPに入る前の
  所持金で決まる。
- **違いは杯数と濃さの初期値**：通常のベースは濃さ3スタートだが、クズ野菜は
  **濃さ1スタート**（既存の「濃さ1は-1段階」ペナルティがそのまま効く）。杯数は
  3段階から選べず、**小仕込みと同じ8杯に固定**（2026-09-25改訂：旧`SERVINGS_PER_BASE`
  は10だったが、3段階のうち最小と揃える形にした。「一番安い仕込みすら買えない
  →一番小さい量」という筋を通すため）。
- 鍋の`base_id`は`veg_scrap_broth`、`tags`は`["vegetal"]`になる
  （鍋のtagsは判定に数えないので味への影響はない。表示上の区別のみ）。
  `soup(今日の鍋)`の表示でクズ野菜の日だと分かる。
- 市場のMARKET画面で「食肉仲卸」と「端材半端物（訪問済み）」の表示が
  入れ替わる（食肉仲卸ではなく端材屋の方が「訪問済み」になる）。
  **これはDay1限定**：day_count>=2になると、クズ野菜の日でもどちらの店にも
  「訪問済み」は付かず、両方とも通常どおり購入できる（上記「日ごとの解禁」参照）。
- **デバッグ用の所持金操作ボタン**（`[所持金 -50]` / `[所持金 +50]`）を追加。
  `[Day +1]`の隣にあり、下限は設けていない（ゲームオーバー確認にも使う想定）。
  PREPに入る前（WAKE中など）に押す必要がある。

### 市場での購入 — 永順青果（実装済み・7.7／価格・購入単位は2026-09-23改訂）

Day2以降、青果を押すと商品2品の選択画面に入る（MARKETと同じ「optionsを持つ
Event」パターンを流用）。

| 商品 | id | 価格 | 1回の購入で増える量 | tag |
|------|----|----:|----:|-----|
| 冬瓜 | winter_melon | ¥50 | 5個 | GENTLE |
| 苦瓜 | bitter_melon | ¥12 | 3個 | BITTER |

- 1回押すとその商品の`count`個（品目ごとに異なる。下記「購入単位を品目ごとに
  持たせる仕組み」参照）まとめて在庫に入る。何度でも買い足せる。
- 所持金が価格未満だとボタンが無効化される（買えない商品は押せない）。
- 買った具材はその夜のADJUSTに**即反映**される（在庫辞書に足すだけなので、
  ADJUSTの動的生成が自動で拾う。専用の連携コードは無い）。
- **規格外野菜（クズ野菜）はここに入れていない**：企画当初の位置づけが
  「お金が無いときのベース代用品」であり、トッピング用の具材ではないため。
  永順青果の商品としては扱わず、将来ベースの代用ルートとして別途検討する。
- **食肉仲卸の追加購入・乾物調味料・豆腐麺・海鮮・端材半端物の5店は実装済み**
  （下記「市場での購入 — 残り5店」参照）。**水場は2026-09-26改訂でボタン自体を
  廃止した**ため、「水場で何か追加購入する」という構想も入れ物ごと対象外になった。

### 市場での購入 — 残り5店（実装済み・7.7／価格・購入単位は2026-09-23改訂）

食肉仲卸の追加購入・乾物調味料・豆腐麺・海鮮・端材半端物も、永順青果と同じ
「optionsを持つEvent」パターンで実購入できる（day_count>=2で解禁。食肉仲卸・
端材半端物の解禁条件・「訪問済み」表示の扱いは上記「日ごとの解禁」参照）。

| 店 | 商品 | id | tag | 価格 | 1回の購入で増える量 | 腐るか |
|---|---|---|---|---:|---:|---|
| 食肉仲卸（追加購入） | モツ | offal | POWER | ¥30 | 3個 | 腐る（初期在庫と同id・唯一の補充経路） |
| 〃 | モツ(小口1個)【新規】 | offal_single | POWER | ¥12 | 1個 | 腐る（在庫はパック購入と同じ`offal`へ足す） |
| 〃 | 軟骨 | cartilage | BITE（新軸） | ¥24 | 3個 | 腐る |
| 〃 | すじ肉 | tendon_meat | **POWER＋BITE**（新軸。2026-09-23追加） | ¥36 | 3個 | 腐る |
| 乾物調味料（南興乾貨行） | ナムプリックパオ | nam_prik_pao | HOT | ¥25 | 5個 | 腐らない |
| 〃 | ココナッツミルク | coconut_milk | MELLOW | ¥15 | 3個 | 腐る（唯一の補充経路） |
| 〃 | 薬膳ナンプラーだれ | herbal_sauce | SAVORY | ¥25 | 5個 | 腐らない |
| 〃 | 塩漬けライム | pickled_lime | SOUR | ¥20 | 5個 | 腐らない |
| 〃 | 乾燥きくらげ | dried_wood_ear | BITE（新軸） | ¥50 | 5個 | 腐らない |
| 豆腐麺（福生豆腐麺房） | 豆腐 | tofu | GENTLE | ¥24 | 3個 | 腐る（唯一の補充経路） |
| 〃 | 米麺 | rice_noodle | FILLING | ¥40 | 5個 | 腐らない |
| 海鮮（海隆鮮貨） | 海老 | shrimp | TREAT（新軸） | ¥54 | 3個 | 腐る |
| 〃 | 海老(小口1個)【新規】 | shrimp_single | TREAT（新軸） | ¥20 | 1個 | 腐る（在庫は同じ`shrimp`へ足す） |
| 〃 | 貝 | clam | TREAT（新軸） | ¥48 | 3個 | 腐る |
| 〃 | 魚の浮き袋 | fish_maw | TREAT（新軸） | ¥100 | 5個 | **腐らない（2026-09-23：腐る側から移動）** |
| 端材半端物（拾味） | 割れた餃子皮 | broken_wrapper | FILLING | ¥18 | 3個 | 腐る（唯一の補充経路） |
| 〃 | 肉団子（旧ラベル「くず肉団子」） | meat_ball | POWER | ¥24 | 3個 | 腐る（唯一の補充経路） |

- 商品リストは`Day1Events.meat_wholesale_goods()` / `dry_goods_goods()` /
  `tofu_noodles_goods()` / `seafood_goods()` / `scraps_goods()`（永順青果の
  `produce_goods()`と同じ形）。`DebugPanel._shop_goods()`のmatch文が店名から
  これらを引く。
- **購入単位を品目ごとに持たせる仕組み（2026-09-23・①具材の購入単位・
  `BALANCE_REDESIGN_PLAN.md`§3。コミット`e6fbc27`）**：`INGREDIENT_SERVINGS_PER_PURCHASE`
  （一律5杯分固定）は廃止し、各`*_goods()`の要素が`"id"`（ボタン識別・検索キー）・
  `"item"`（在庫に足す品目id）・`"count"`（1回の購入で増える個数）を個別に持つ形へ
  変わった。同じ品目に複数の購入選択肢（パック・小口）を持たせたいときは、`item`を
  同じにしたまま`id`だけ変えた別要素を追加する（モツ・海老の小口購入がこの形）。
  `_on_shop_item_selected()`は`item`/`count`を読んで`GameState.add_inventory(item,
  count, unit_price)`を呼ぶ（`unit_price = price / count`）。
- **市場ボタンの表示に個数・単価を追加（F4・実装済み・2026-09-30追記）**：
  ボタン文言が`"%s（-%d・%d個入り・単価%d）" % [label, price, count, unit_price]`に
  変わり、値段だけでなく1回の購入で増える個数と単価もボタン上に出るようになった
  （`debug_panel.gd`のPREP以外の通常市場ボタン生成箇所）。仕入れ判断に必要な情報を
  増やしただけで、購入時の処理（`_on_shop_item_selected()`）自体は変わっていない。
- **ロットごとの実際に払った単価を記録**（同日）：`add_inventory()`に`unit_price`
  引数が増え、`perishable_batches`の各ロットが`unit_price`を持つ（詳細は上記
  「具材の腐敗」参照）。同じ品目を同じ日にパックと小口の両方で買うと、単価が違う
  ため**別々のロットのまま**保持される。
- **廃棄額はロットの実額の積算に変更**（従来は市場価格からの概算）：
  `discard_spoiled_inventory()`の返り値が`{item: 個数}`から
  `{item: {"count": 個数, "value": 実額}}`へ拡張された。`DebugPanel._spoiled_value()`
  （旧`_spoiled_value_approx()`）はこの`value`を合計するだけになり、日次ログの
  キー名も`spoiled_value_approx`→`spoiled_value`に変わった（`Day1Events.ingredient_prices()`
  は廃棄額計算には使わなくなったが、代表価格を返す小さな関数として残している）。
- 新規具材7品目（軟骨・すじ肉・乾燥きくらげ・米麺・海老・貝・魚の浮き袋）を
  `Ingredients._TAGS`と`Day1Events._ADJUST_LABELS`に追加。腐る4品目（軟骨・
  すじ肉・海老・貝）は`_PERISHABLE`・`_NAMES`にも追加（魚の浮き袋は上記の通り
  2026-09-23に腐らない側へ変更）。乾燥きくらげ・米麺は腐らない。
- **これで初期在庫の腐る5品目（ココナッツミルク・モツ・肉団子・豆腐・
  割れた餃子皮）すべてに補充経路ができた**（§5「具材の腐敗」の既知の制約は解消）。
- **新しい具の軸（BITE・TREAT）を導入**（モツ・肉団子等の既存POWER/GENTLE/
  FILLING軸とは別）。現状Day1〜7（流用中）のどの客もBITE・TREATを欲しがらない
  ため判定には影響しないが、フルで実装しておく方針で決定済み（§11参照）。
  すじ肉だけはPOWER・BITE両方を持つため、POWER要求の客（配達員・チンピラ等）にも
  一致する（`judge_bowl`は無改修。タグ照合の結果として自然に反映される）。
- **既知の食い違い（未修正・意図的）**：
  - 決定した価格（`BALANCE_REDESIGN_PLAN.md`§3の値をそのまま採用）はPRICING_SPEC.md
    §6・§7の例と一致しない。ドキュメント側の追記は別途必要（コードには影響しない）。
  - モブの人数によっては1回の購入（パック3個や5個）では足りず、複数回買う必要が
    ある（既存のservings連動消費どおり。追加対応はしない）。
  - 買い足すと在庫全体が「1日目」扱いにリセットされるわけではなく、同日・同単価
    ならロットを合算、それ以外は別ロットとして積み増される（上記「具材の腐敗」参照）。
  - 乾物調味料は商品5つ＋「市場に戻る」でボタンが横に収まらない可能性がある
    （`HFlowContainer`化は別途・シーン変更を伴うため今回は対象外）。
- Godot実機で動作確認済み（Day1のPREPで各店に入店・モツ/海老のパック購入と
  小口購入の両ボタンが並ぶこと・購入・所持金減少・在庫増加・肉団子のラベル変更・
  具材を放置して腐らせたときのPREP通知とBALANCE_LOGの`廃棄額=`表記を確認）。

### OPEN（名前あり客3人＋モブ1組）
```
宵の口 : delivery_man（1杯×3回）, dock_workers（モブ・Day1は4杯）
夜半   : thug（1杯）
明け方 : granny（1杯）
各客: GREET → ADJUST（3枠を選ぶ・入力待ち）→ SERVE → REACT（判定＋売上確定）
      ※delivery_man だけは、会話の合間に ADJUST→SERVE→REACT を3回くり返す
        （3杯目は持ち帰り・評価なし。§5「1杯ずつ接客する客」）
売上: PRICE_PER_SERVING(45) × servings（判定結果にかかわらず固定。2026-09-26改訂：50→45）＋チップ（UI準備H2：GREAT +10／杯・GOOD +5／杯。UI準備L：具の材料が2種類で GOOD 以上なら、さらに +10／杯）
      delivery_man +135 / dock_workers +180 / thug +45 / granny +45
thug のみ REACT 後に場所代 -90（PAY・try_pay経由・2026-09-26改訂：150→90）※徴収日のみ
```
- 時間帯・servings・判定・評判の詳細は§5参照。
- Day2以降はモブ人数が評判で変わる（§5「評判→モブ人数」）ので、売上も日によって変わる。

### CLOSE
閉店の締めくくり TEXT ×3（状態は動かさない）。**語りを読み終えた後に、任意の「修繕基金に積む」行が出る**
（4-9。下記「修繕基金」節）。**最終日はこの後に
「（終了）」TEXTが1つ追加される**（下記「終了日」参照）。鍋が尽きた自動閉店で
CLOSEに来た日も同じ（理由テキスト＋閉店TEXT×3＋（終了）と続く）。

### NEXT_DAY
中継フェーズ。`[次のPhase]`で入り、もう一度`[次のPhase]`を押した瞬間に
折り返し処理が走ってWAKEへ進む（リセットは2回目のボタン操作で起きる）。

- 最終日でなければ：日次リセット（soup / served クリア）＋ day_count +1
- **最終日なら**：【4-2で変更：日次リセットも日数加算もせず`Phase.RESULT`へ入る。以下は4-2以前の記述】日次リセットの代わりに`GameState.reset_for_new_game()`
  （下記「終了日」参照）

### 終了日（実装済み。**4-2で最終日の先が変わった**→「結果画面（4-2）」参照。以下は4-2以前の記述を含む）

`FINAL_DAY`（7日・本番版。体験版の3日から変更済み）で終了する。以下の仕組み
自体は日数によらず共通。

```
最終日のCLOSE
  → 閉店TEXT×3 → 「（終了）」TEXT
  → [次のPhase] でNEXT_DAYへ（中継）
  → [次のPhase] でreset_for_new_game() が走り、1日目のWAKEへ（4-2以降：RESULTへ入り、新しい周は結果画面の選択肢から）
```

- **全状態初期化**：`day_count`（→1）・`money`（→`INITIAL_MONEY`＝600）・
  `reputation`（→`INITIAL_REPUTATION`＝30）・`inventory`（クリア）・
  `perishable_batches`（クリア）・`rumors`（クリア）・`dashi_units`（→0）・
  `known_favorites`（クリア。【4-4b-1で撤去され`customer_memory`のクリアに置き換わった】）・`ledger`（クリア）・`phase`（→WAKE）・
  `soup`・`served`・`rent_paid_today`・`today_plan`（この4つは
  `reset_for_new_game()`内で呼ぶ`reset_for_new_day()`がクリア）が対象
  （`rent_paid_today`は「閉店で場所代を避けられる」不具合の修正で追加。
  2026-09-26改訂：予備ベース関連の`reserve_base_units`/`reserve_base_purchased`/
  `reserve_base_purchase_remaining`/`reserve_base_purchase_day`（4個）は削除され、
  後継の`dashi_units`（1個）に統合された。§5・§11参照。**2026-09-28追記・
  F1〜F4実装により変更**：`money`/`reputation`の初期値は`Rules`経由
  （`data/campaigns/week7.json`）の読み取りに変わった（値そのものは同じ600/30）。
  `pending_bills_today`はフィールド自体が削除され対象外に。`ledger`（F4）と
  `known_favorites`（好物の既知状態）が新たに初期化対象へ加わった。項目数の
  「12個」という数え方はここで実質的な意味を失ったため以後は数えない）。
- **初期在庫の積み直しは`DebugPanel`側の責務**：`GameState`はDay1の台本
  （`Day1Events`）を知らない設計を保つため、`reset_for_new_game()`自体は
  在庫を空にするだけで、`Day1Events.initial_inventory()`を積み直さない。
  代わりに`FlowController`が新しいシグナル`game_restarted`を発火し、
  `DebugPanel`がこれを受けて`_seed_initial_inventory()`（`_ready()`と共通化した
  関数）を呼ぶ。**2026-10-01追記・3-5実装済み**：`initial_inventory()`が空の
  辞書を返すようになったため、`_seed_initial_inventory()`は現在**実質何も
  積まない**（呼び出し自体や`game_restarted`シグナルの配線は残したまま、中身が
  空振りになった）。Day1の具材は、代わりに毎回のPREPで「初日セット」が
  固定購入される（上記「初日セット」参照）ため、リセット時点で在庫を先積みする
  必要自体が無くなった。腐敗の基準日（`stocked_day`）は、初日セット購入時の
  `add_inventory()`呼び出し（PREP中、`day_count`が1に戻った後）が記録するので、
  従来どおり正しく1日目として扱われる。
- 巻き戻り後のDay1は、**宵の口＝港湾労働者2人・夜半＝安宿の夜勤受付2人の
  固定編成**（3-5でモブ4人固定から変更。上記「客数の決め方」参照）・水道代あり・
  青果は使えない、という通常のDay1と同じ状態に戻る。
- 既知の注意点：デバッグ用`[Day+1]`をNEXT_DAY中（CLOSEの後）に押すと、
  「（終了）」テキストは出ていないのに折り返しで最終日扱いになるケースが
  ある。通常プレイでは起きない操作なので対処していない。

### ゲームオーバー（実装済み）

水道代・場所代が払えない（`PAY`直前に所持金が足りない）とき、ゲームオーバーになる。
ベース代（食肉仲卸）は通常プレイでは対象外（クズ野菜ベースが必ず賄うので、
食肉仲卸の`PAY`イベント自体、所持金が足りているときにしか組まれない）。

```
GameState.try_pay(amount) -> bool
  所持金 >= amount → apply_money(-amount) して true
  所持金 <  amount → 何もせず false（apply_moneyは呼ばない）
```

- **`apply_money`とは別の入口**：売上・市場購入（永順青果など「常に払える／
  受け取れる」場面）は従来通り`apply_money`を直接呼ぶ。「払えないかもしれない」
  支払い（水道代・場所代）だけが`try_pay`を通る。
- **受け側（`DebugPanel`）の`_pay_or_game_over(amount)`**が`try_pay`の結果を見て、
  `false`ならゲームオーバーへ遷移する。
  - `_apply_event`の`PAY`枝と`_visit_water_stall()`（水場での支払い）がこれを通る。
  - ベース代（食肉仲卸）も同じ`PAY`枝を通るが、払える所持金のときしかその
    イベント自体が生成されないため、通常プレイでは発生しない。デバッグ用
    `[所持金]`ボタンでPREPのEvent列生成**後**にベース代未満へ下げると発生し
    得るが、通常操作では起きないため対処していない。
  - `_visit_water_stall()`は成否（bool）を返すようになった。`[市場を出る]`の
    自動訪問（未訪問なら水場へ自動で寄ってから仕込みへ進む・§6「PREP」参照）で
    水道代が払えなかった場合、**仕込みへ進まずそこで止まる**。
  - **`_reason_after_collecting_rent()`（実装済み・「閉店で場所代を避けられる」の
    修正で追加）も同じ`_pay_or_game_over`を通る**：徴収日にチンピラの番より前で
    閉店（`[閉店]`または鍋が尽きての自動閉店）しようとすると、まだ払っていない
    場所代（`RENT_PRICE`）をここで特別請求する。払えなければCLOSEへは進まず
    ゲームオーバーへ。§5「未解決」参照。
- **`Phase.GAME_OVER`に入ると**：理由テキスト＋「（ゲームオーバー）」を表示する。
  理由は一度読まれると消える（使い捨て）。
- **GAME_OVER中の操作制限**：
  - `advance_phase()`が先頭でガードするため`[次のPhase]`が効かなくなる
    （§3「フェーズ遷移」参照）。
  - `[鍋を見る]`も無効化する。OPEN中に鍋が残った状態でゲームオーバーになっても
    鍋を触れないようにするため。
- **【2026-10-18追記・先に直す②`7266418`】出口が3つになった**：結果行（最後の朝／Day1の朝から／
  新しい周）をGAME_OVERでも表示して流用する。[最後の朝]＝記録があれば押せる（GAME_OVERでは
  「直近の朝からやり直す」）／[Day1の朝から]＝常に押せる。Day1の記録が無い周（[続きから]で
  始めた周）や記録が空のときは[新しい周]と同じ動作にフォールバックし、文面とツールチップで
  「新しい周と同じ」と出す／[新しい周]＝常に押せる。スマホ画面を開いている間は従来どおり
  押せない。RESULTの挙動は変えていない（Day1の記録が無いと[もう一度]は押せない）。
  朝の記録が空でも行き止まりにならない（これが修正の目的）。
- **復帰しない（【2026-10-11追記・4-1】仮ボタン[同じ朝からやり直す]による同じ朝への再挑戦と、起動時の[続きから]が加わった。`[次のPhase]`では復帰しない点は変わらない）**：ゲームオーバー後はGodotを再起動するまで復帰できない
  （セーブ未実装のため。§9参照）。
- **動作確認済み**（Godot実機・完全再起動後に確認。2026-09-26改訂：水場の手動
  ボタンが廃止され自動精算に一本化されたため、該当手順を更新した）：
  1. 日々の運営費：Day1のWAKE突入前に所持金を`DAILY_OPERATING_COST`(現在75。3-8で65、当時80)未満に
     しておく → WAKEに入った瞬間、運営費が引かれずゲームオーバーになる。
     理由と「（ゲームオーバー）」が出て、計器盤の`phase`は`GAME_OVER (5)`に
     なり`[次のPhase]`が効かない。
  2. 水道代：Day1のWAKEを無事通過した後、PREPの市場で所持金を`WATER_PRICE`(50)
     未満にしてから`[市場を出る]`を押す → 自動訪問経由で水道代が払えず
     ゲームオーバーになり、仕込みへ進まない。
  3. 境界：所持金がちょうど水道代分（50）なら払えて0になり、ゲームオーバーには
     ならない。
  4. 場所代：Day1のOPENでチンピラの接客中、PAYの前に所持金を`RENT_PRICE`(90)
     未満にして進めると、支払われず所持金は変わらないままゲームオーバーになる。
  5. 徴収日でない日（Day2以降。水道代・場所代のPAY自体が無い）は、水道代・
     場所代由来のゲームオーバーは起きない（日々の運営費はDay2以降も毎日
     発生するが、通常プレイでINITIAL_MONEY(600。2026-09-26改訂：300→600)から
     複数日分を使い切るにはかなりの連続した資金難が必要）。
- **既知の注意点（実装中に発見・対処せず記録のみ）**：`_ready()`が
  `flow.phase_changed.connect(...)`より前に`_set_runner_for_phase(GameState.phase)`
  を呼ぶ初期化順のため、もし**ゲーム開始直後の最初のWAKE**で日々の運営費の
  支払いに失敗すると、`force_phase(GAME_OVER)`のシグナルをまだ誰も聞いて
  おらずゲームオーバー画面のrunnerが組まれない（理由テキストが出ない）。
  ただし`INITIAL_MONEY`(600。2026-09-26改訂：300→600)は`DAILY_OPERATING_COST`(現在75。当時80)
  を必ず上回るため、現状の定数では実際には起こりえない。
- **実装中に見つかった不具合（別件・修正済み）**：`[鍋を見る]`の条件式に改行が
  文字として紛れ込んでおり、Godotが読み込めない状態になっていたため修正した。
- **場所代の特別請求（`_reason_after_collecting_rent`）も動作確認済み**（Godot実機で確認）：
  1. Day1で、配達員のADJUST中に鍋を空にして閉店（チンピラより前）→ 所持金が
     90減り、閉店の理由テキストに一言添えられる。
  2. 1の直前に所持金を90未満へ下げてから閉店 → 場所代が払えずゲームオーバーになる。
  3. チンピラの番を過ぎたあと（通常どおり場所代が払われている）に鍋を空にして
     閉店 → 所持金はそれ以上減らず、理由テキストにも一言は付かない（二重請求なし）。
  4. Day2（非徴収日）で同様に早期閉店 → 場所代のチェック自体が起きない。

### 所持金の推移（**2026-10-18改訂・運営費75を反映**〔2026-10-11の3-8で65、元は2026-10-01の3-5実装で80〕。初期現金600・日々の運営費80→65→現在75/
場所代90/水道代50/初日セット210・Day1は9杯構成）
- **Day1（徴収日）:** 600 →(-75 日々の運営費・WAKE)→ 525
  →(-210 初日セット -80 小仕込み・PREP)→ 235 →(-50 水道・`[市場を出る]`)→ 185
  →(+135 配達員3杯 +90 港湾労働者2人 +45 チンピラ +90 安宿受付2人 +45 老婆・OPEN。
  合計9杯・405)→ 590 →(-90 場所代・OPEN中チンピラの接客)→ **500**
  - 場所代（-90）はOPEN中、チンピラの接客（夜半）まで進んで初めて引かれる
    （§6「OPEN」参照）。水道代（-50）は`[市場を出る]`時点（PREP中）で既に引かれて
    いる。そのため**「PREP終了時点」で見える所持金は185**（運営費65の当時は195、80の当時は180。確保額を引いた値ではなく
    525-210-80-50=185。小仕込みの場合）で、場所代の90はまだ引かれていない。
    途中経過の数字を見て不具合と誤解しないよう注意。
  - また、新規ゲーム開始直後にプレイヤーが実際に目にする最初のSTATE VIEWERは
    600ではなく**525**（運営費65の当時は535、80の当時は520）になる（`_ready()`が画面表示より前に
    `_set_runner_for_phase(WAKE)`を呼んで日々の運営費75を即天引きするため。
    600という値はコード内部の一瞬にしか存在せず、画面には出ない）。
  - 9杯完売・小仕込みの場合の最終値は**500**（運営費を75にした後の値。65の当時は510、80の当時の495は、しまさんが3-5の動作確認時に実機で
    確認した値と一致した。500は自動試遊の全周（390/390周）と`upkeep_test`（Day1閉店時現金の検査）で確認済みで、実機での再確認はまだ）。
- **Day2（非徴収日）:** 500 →(-75 日々の運営費・WAKE)→ 425 →(-80 ベース・PREP。
  初日セットはDay1限定なのでDay2以降は無し）→ 345
  →(+135 配達員 +45 チンピラ +45 老婆 + 45×モブ人数・OPEN)→
  **570 + 45×モブ人数**（評判0〜19ならモブ1〜3人で615〜705。評判0未満ならモブ0人で570）
  ※場所代・水道代とも徴収日でないため出ていかない（日々の運営費は毎日出ていく）
- いずれも全員に提供でき、市場で追加購入しなかった場合の値。永順青果での購入
  （Day2以降）や、鍋が尽きての閉店・廃棄があればその分ずれる。

### 7日間の自動試遊と数値の暫定確定（3-8実装済み・2026-10-11・DESIGN.md 10.13）

3-1〜3-7後の仕様で7日間を自動で遊ばせ、10.13の合格ラインを判定した。ゲーム本体のロジックは
変えていない。変えたのは**運営費の数値1つ**（`week7.json`の`economy.daily_operating_cost`
80→65）と、それに依存するテスト（`tests/upkeep_test.gd`）だけ。

- **仕組み**：`planning/playtest_2026_10_11/`（`run_playthroughs.gd`起動→`playthroughs.gd`本体→
  `summarize_playthroughs.mjs`で集計）。実際の`debug_panel.tscn`を生成し、DebugPanelの
  操作ハンドラ・`GameState`・`EventRunner`・`OpenController`・`Rules`・`Ledger`・`Forecast`を
  実際に動かす。`user://`は`APPDATA`の差し替えで隔離（`runtime_data/`は未追跡・コミットしない）。
  旧版`planning/playtest_2026_09_26/`はそのまま残してある（旧仕様の結果で、今回の値とは比較不可）。
- **方針**：13方針×30シード＝390周（旧7方針＋新5方針＋比較用`decline_once`）。Day2以降の仕入れは
  朝の一画面（3-7の`Forecast`）が出す上限案と必要タグ数だけで決める。仕込み段階は
  「小12／中13／大14杯まで届く」で選ぶ（3-6の鍋容量14・水は残量12以下のみ、に従う）。【2026-10-18訂正】この「12／13／14」は夜の始まりに入れられる量で、仕込み段階を選ぶ基準としては営業中の水足しを含む総杯数12／15／18のほうが実機に合う。取り直した結果は下記「運営費75の確定」（引数`reach_true`）。
  提供不可（SaleRule）のときは個人客は[客を断る]、団体は注文を断る操作に倒し、停止させない。
  **修繕基金に積む方針は当時は見送り**（操作画面が未実装）。**4-9③④で別枠の方針（`POLICIES_FUND`。既定の一覧には入れない）を追加**した
  （§6「修繕基金」参照）。既存13方針は基金を操作しない。
- **結果の置き場所**：`planning/playtest_2026_10_11/PLAYTHROUGH_RESULTS.md`（3-8の最終版・運営費65。75の再測定は`PLAYTHROUGH_RESULTS_REMEASURE.md`・`PLAYTHROUGH_RESULTS_COST75.md`・`PLAYTHROUGH_RESULTS_COST75_V2.md`）と
  `playthrough_results*.json`。
- **コミット**：`17fbc4d`（スクリプト＋調整前の結果）→`f3e28af`（運営費80→70）→`604aa6e`
  （運営費70→65）。1因子ずつ・別コミットで調整した。

**運営費の調整経過（基本GOOD。80・70・65は旧ハーネス〔到達杯数12／13／14〕、75は`reach_true`の値で、直接は比べられない）**

| 運営費 | 平均最終現金 | 1500達成率 | Day1（小仕込み＋9杯完売） |
|---|---|---|---|
| 80（調整前） | 1519 | 60.0%（18/30） | 495 |
| 70 | 1589 | 80.0% | 505 |
| 65（3-8の最終。旧ハーネス） | 1624 | 86.7%（26/30） | 510 |
| **75（現行。2026-10-18・`reach_true`）** | **1636** | **93.3%（28/30）** | **500** |

需要表は触っていない。鍋の同時容量14で1晩の提供が最大14杯に頭打ちになるため、需要を上げても
売れる杯数は増えず、調整できるのは費用側だけだった。【2026-10-18訂正】「1晩の提供が最大14杯」は誤りで、営業中の水足しを含む一晩の総杯数は小12／中15／大18まで届く（`reach_true`の周で、中仕込みは最大15杯・大仕込みは最大18杯の提供を確認）。需要表は現在も触っていない。仕込み費（8→80／11→110／14→140）は
1杯10円の一直線を保つため変えていない。

**10.13の判定（運営費65・390周。旧ハーネス〔12／13／14〕での値）**：項目1（平均1500〜1700）＝1624で合格／項目1b（達成率85〜95%）＝
86.7%で合格（下限ぎりぎり。1周の差で83.3%になる位置）／項目2（安い完成料理1343・空の椀40は
基本GOODを上回らない）＝合格／項目3（品質失敗2件でも30/30周完走、平均1513）＝合格／
項目4（資金不足の休業0）＝0/360周で合格／Day1のキャッシュフロー＝390/390周が一致（510）。
進行停止は0。既存テスト556件は各段階で全件成功。

- **項目4の扱い**：運営費80の段階で、毎日1組を断る極端な方針（`decline_one_group`）のシード19が
  1周だけ破産した。「通常の営業判断の範囲で資金不足が起きない」と読み、注記つきで合格とした
  （1回だけ断る`decline_once`は30/30周完走）。運営費を下げた結果この1件は再現しなくなったが、
  それを目的にした調整ではない。字義どおり適用した場合の扱いはフェーズ5の人の試遊で見直す。
- **読み取れること**（運営費80時点の傾向。大筋は変わらない）：好物（既知・初回）は評判と常連実績を
  伸ばすが、追加仕入れで現金では基本GOODに劣る。大仕込み固定は需要が少ない日にも140を払うため
  基本GOODより現金が少ない。団体を分割しないと未提供が増える。小仕込み固定は早期閉店が起きるが
  ゲームオーバーにはならない（供給不足の学び）。
- **限界**：自動操作は人間の操作速度・読み間違い・面白さを測らない。30シードで全ルートの安全性は
  保証しない。Day1の510は実機では未確認（運営費75の現在は500）。最終確定は10.13のとおりフェーズ5の人の試遊で行う。
- **再現**：Godot 4.4.1 mono・ヘッドレス。`APPDATA`を`planning/playtest_2026_10_11/runtime_data`に
  向けて`run_playthroughs.gd -- 30 30 <出力JSON>`を実行し、`summarize_playthroughs.mjs`で集計する
  （手順は`PLAYTHROUGH_RESULTS.md`末尾）。

**運営費75の確定（2026-10-18・再測定`6f8bfe2`・`fdbaa9c`、確定`ef4c6d2`〜`bc0a8c3`。暫定値）**

- **きっかけ**：QA再評価（`claude/QA_REVIEW_2026_10_18.md` H1）の指摘のとおり、上の試遊ハーネスは仕込み段階を
  「夜の始まりに入れられる量（12／13／14）」で選んでおり、中仕込み＋営業中の水足しで足りる夜にも大仕込みを
  選んでいた。ハーネスに、引数で切り替える`reach_true`（届く杯数＝営業中の水足しを含む総杯数12／15／18）を
  足して取り直した。**既定（引数なし）の動きは変えていない**（既定の13方針×30シード390周が
  `playthrough_results_regulars.json`と全キー一致）。
- **到達杯数の補正（運営費65・基本GOOD・30シード）**：平均最終現金1622→1706（同じシードで平均+84.5、
  +58〜+104、30シードすべて増加）、1500達成率93.3%→100%、1600達成率60.0%→90.0%。仕込み代は1周あたり
  117円下がり、現金の増加84.5との差（約32.5円）は中仕込みで15杯出すためのだし代などと読める（推定）。
  評判・提供杯・GOOD以上率は変わらない。中仕込みで14〜15杯、大仕込みで16〜18杯を提供した夜が実在する
  （全13方針で中仕込み653夜は最大15杯〔15杯の夜101〕、大仕込みは最大18杯〔16〜18杯の夜77〕）。
- **運営費別（`reach_true`・基本GOOD・30シード）**：

  | 運営費 | 平均最終現金 | 1500達成率 | 1600達成率 | 10.13の項目1／1b |
  |---:|---:|---:|---:|---|
  | 65 | 1706 | 100%（30/30） | 90.0% | 不合格／不合格 |
  | 70 | 1671 | 96.7%（29/30） | 86.7% | 合格／不合格 |
  | **75（現行）** | **1636** | **93.3%（28/30）** | **70.0%** | 合格／合格 |
  | 80 | 1601 | 90.0%（27/30） | 53.3% | 合格／合格 |

  標準偏差はいずれも75.0。30シードでは1シード＝3.3ポイントで、帯85〜95%は26〜28シードの3通りしかない
  （70と75の差は1シード）。QA H1の見立てどおり、3-8で65に下げたのは旧ハーネスの取りこぼしを費用側で
  埋めた形だったと読める（旧ハーネスの65の平均1624に平均現金をそろえると、補正後は運営費約77に当たる。換算）。
- **運営費75の10.13の判定（`reach_true`・13方針×30シード・390周）**：項目1＝平均1636で合格／項目1b＝
  93.3%（28/30）で合格／項目2＝安い完成料理1251は基本GOOD1636を上回らず合格／項目3＝品質失敗2件でも
  30/30周完走／項目4＝空の椀を除く360周でゲームオーバー0／Day1＝390/390周が一致（小仕込み＋9杯完売の
  閉店時現金500）。65の結果から「7日×10」を引く試算との差は388/390周で一致（不一致は初回から好物の
  seed12〔+12〕と毎日1組を断るseed19〔+3〕。手持ち現金が苦しい夜に買い物が変わった型とみられるが、
  個別の確認はしていない）。**75は暫定値で、フェーズ5の最初の人の試遊のあとに見直す。**
- **中仕込みの落とし穴（切り分け済み）**：「濃さ・鮮度のミス」方針（だしの買い置きなし）は、`reach_true`で
  1568→1397（−170.7）、1500達成率66.7%→16.7%、早期閉店25→46夜に悪化した。だしの買い置きだけを基準方針と
  同じにした版（B1）は1628→1712（+84.5）・93.3%→100%・早期閉店0夜で、基本GOOD（1622→1706）とほぼ
  同じ。**原因は「中仕込みで15杯出すには水2回とだしが要るのに、だしを買っていない」こと**で、中仕込み56夜の
  うち水足しが止まった理由は`no_dashi`が43夜、濃さの下限`strength_floor`が1夜。大仕込みから中仕込みに変わった
  最初の21夜では、提供13.6→11.4杯、未提供0.4→2.6杯。現金で見る限り、濃さ・鮮度の「ミス」自体はほぼ損に
  なっていない（B1が基本GOODと同水準）。この罠を設計として許すか、予報や仕込みの画面で見せるかは未決で、
  **フェーズ5の観察項目**に入れた（DESIGN.md 10.13）。
- **修繕基金（運営費75・`reach_true`・各30シード）**：`cash_plus_repair`が基準方針と一致しない周0・
  ゲームオーバー0・完走しない周0。**安全上限が1晩の上限30を下回った夜は0**で、基金に積んでも損がない
  （現金＋修繕額は基準方針と基金3方針のすべてで1636）。MVPの方針（表示だけ）の範囲だが、QA M5
  「基金が選択になっていない」は75でも残る。
- **変えたもの**：`data/campaigns/week7.json`の`economy.daily_operating_cost`を65→75（1行）と、これに連動する
  テスト（`upkeep_test`の予算行・使える現金・WAKE後の所持金・ゲームオーバー理由の金額、`repair_fund_test`・
  `repair_fund_ui_test`の翌日の確保額と安全上限の境目〔運営費の定数から計算する形に変更〕、Day1閉店時現金500の
  検査を1件追加）。全44スイート2449件成功。旧`playthrough_results_regulars.json`（運営費65・12/13/14）とは
  **意図して一致しなくなった**（上書きしていない）。新しい基準は運営費75・`reach_true`の13方針×30シード
  （`playthrough_results_regulars_v2.json`。引数で明示して取る）。
- **【2026-10-25・UI準備C⑤】予報を使わない前提でも測った（v3）**：上の結果はすべて「予報で仕込みと仕入れを決める」基準方針（v2）での値。
  本番UIは予報を出さなくなったので、予報を読まないハーネス（引数`info=visible`／`visible_improvise`）でも測った。基本GOODの平均最終現金は
  v2の1636に対して、既定版418・補う版1316（どちらも1500達成0/30）。**この「75は暫定値」の結論は、予報を使わない前提では変わる可能性がある**
  （詳細は「ルールと情報の変更（UI準備C）」のC-6と`PLAYTHROUGH_RESULTS_V3.md`）。合格ラインの判断（ラインを変えるか、数値を調整するか）は、人の試遊のあとに決める。
- **結果の置き場所**：`planning/playtest_2026_10_11/PLAYTHROUGH_RESULTS_REMEASURE.md`（到達杯数の補正と運営費の感度）、
  `PLAYTHROUGH_RESULTS_COST75.md`（残り11方針と切り分け）、`PLAYTHROUGH_RESULTS_COST75_V2.md`（新しい基準と基金）。
- **限界**：自動操作は人間の読み違い・操作の手間・面白さを測らない。`reach_true`の基本GOODは、営業中の水足しと
  だしの買い置きを毎回正しく行う方針で、人はこれより下振れする（1500達成率も表より下がる）。75が人にとって
  適切かは、フェーズ5の人の試遊で見る。

### 朝の保存と1枠セーブ（4-1実装済み・2026-10-11・DESIGN.md 10.6・10.8.7 F7）

「ゲームオーバーから同じ客・同じ需要の朝へ戻る」と「朝から再開する1枠セーブ」。コミットは
`608c408`（朝の保存と同じ朝からの再挑戦）と`e5f3dbb`（1枠セーブ）。テストは672件成功
（既存556＋`save_state_test` 66＋`save_file_test` 50。既存テストの書き換えなし）。自動試遊も
3シード×13方針で運営費65の結果と39/39周が完全一致した。画面は仮ボタンのみ（本番UIはフェーズ6）。

- **保存項目**（`GameState.SAVED_FIELDS`）：`day_count`・`money`・`reputation`・`inventory`・
  `perishable_batches`・`rumors`・`dashi_units`・`known_favorites`（【4-4b-1で`customer_memory`に置き換え】）・`ledger`・`today_plan`
  （DayPlanを含む）。保存しない項目（`TRANSIENT_FIELDS`）：`phase`・`soup`・`served`・
  `rent_paid_today`・`morning_snapshots`。保存しない項目は朝の初期値で、`from_dict()`が
  `phase`をWAKEに戻す。**新しいGameState変数は、どちらかに分類しないと`save_state_test`が落ちる**
  （F5の来店記録を足すときは`SAVED_FIELDS`に入れる）。辞書は往復とも深いコピー。**【4-2で`day_records`を追加】**
- **封筒**（`MorningSave.capture()`）：`{version: 4（4-1は1、4-2で2、4-4aで3、4-4b-1で4）, campaign, day, state: GameState.to_dict(),
  panel: {day_summary_text}}`。`is_valid()`が版・キャンペーンID・各項目の型を確かめる。
  `panel`は画面側の最小限の付随情報で、前日成績の一言だけ（戻った朝にも同じ文を見せる）。
- **WAKEの処理順（4-1で変更）**：旧は「運営費→reserve→`DayPlanner.build()`」。新は
  日次ログのリセット→`DayPlanner.build()`（復元した朝は呼ばない）→朝の辞書化→運営費→
  記録（`GameState.morning_snapshots`）と1枠セーブへの書き込み→reserve→起床イベント。
  運営費の支払いは乱数を引かないので、乱数の消費順・通常プレイの結果は変わらない。
  **運営費が払えない朝は記録も書き込みもしない**（戻っても同じ不足で詰むため）。この場合
  `today_plan`はその日のDayPlanが残る（旧は空）。SNSタブはその日の予報を出す。
- **同じ朝からの再挑戦**：`DebugPanel.retry_from_morning()`（4-2の結果画面からも呼べる公開関数）。
  `morning_snapshots`（日番号→封筒。周回中の各朝で最大7件。`reset_for_new_game()`でクリア）の
  最大日番号の朝へ戻る。日中に詰んだ（Day1の場所代など）ならその日の朝、朝の運営費で詰んだなら
  前日の朝。`DayPlanner.build()`は呼ばず（`_plan_restored`の一度きりの印）、客・需要・組は
  保存したものと同一＝抽選の引き直しにならない。戻す前に営業中の途中経過
  （接客の集計・保留・団体の状態など）を捨てる。**反応文の2択（`reaction_variant`）は演出の
  乱数なので、再挑戦で変わりうる**。仮ボタン[同じ朝からやり直す]はゲームオーバー時のみ有効。
- **1枠セーブ**：`user://save.dat`（`MorningSave.save_path`。テストは差し替える）。形式は先頭に
  マジック文字列`YORUYUSAVE1`＋`var_to_bytes`（型を保つ。JSONは整数がfloat・整数キーが文字列に
  なるため使わない）。読み込みは`bytes_to_var`（Objectは復元しない）。書き込みは一時ファイル
  経由（**【2026-10-18・先に直す①`bac9a87`】旧版を消さない置換に変えた**：`.tmp`へ書いて
  読み戻して検証→本体があれば`.bak`へrename→`.tmp`を本体へrename→成功したら`.bak`を削除。
  本体への置換に失敗したら`.bak`を本体へ戻す。以前は旧本体を先に削除していたため、その
  間に落ちると読めるセーブが残らなかった。**読み込みは本体→`.tmp`→`.bak`の順**で、
  マジックと`is_valid`を通った最初のものを採る（置換の途中で落ちて「本体なし・`.tmp`が新版・
  `.bak`が旧版」になっても最新が読める。書きかけの`.tmp`は検証で弾く）。`has_file`は3つの
  どれかがあればtrue、`delete_file`は3つとも消す。テスト専用の失敗スイッチ
  `fail_install_for_test`あり。版は6のまま）。書くのは運営費が払えた朝のみ（調理中・会話途中は保存しない）。ゲームオーバーでは
  消さない（最後の朝が残るので、次回の[続きから]が再挑戦になる）。
- **起動時**：セーブが有効なら仮ボタン[続きから]が押せる。押すと、その朝を
  `morning_snapshots`へ入れて戻す（読み込んだ朝で詰んでも再挑戦できる）。押さずに最初の朝を
  抜けた場合は、その時点でセーブを上書きする（それまでは書かない＝起動直後のDay1の朝で
  上書きして続きを選べなくなるのを防ぐ）。
- **読めないとき**：無い・空・別の内容・途中切れ・版違い・別キャンペーン・型崩れは、例外なく
  新規ゲーム扱い（ファイルは消さず、次の朝の保存で上書き）。破損ファイルではGodotが
  `Error when trying to decode Variant`を出力するが、例外にはならない。
- **（(1)は4-2で解決済み。「結果画面（4-2）」参照）未対応・4-2以降で決めること**：(1) 結果画面の「もう一度（Day1から）」は、
  `reset_for_new_game()`が`morning_snapshots`を消すため、Day1の朝の記録を残す手段（実行前に
  退避して戻す／Day1の記録は消さない）が要る。Day1の再現は**Day1の客・需要のみ**で、2日目以降は
  評判次第で引き直しになる。(2) `balance_log.jsonl`は再挑戦した日が二重に記録される（**システム整理Aで`run_id`・`attempt`を足して区別できるようにした**）。
  (3) 実機での[続きから]の確認（保存→終了→再起動→同じ朝・同じ予報）は未実施。
  (4) 1枠セーブの書き換えは「古いファイルを消してから置き換える」順で、その一瞬の中断では
  セーブが消えうる（仮機能として許容）。

### 結果画面（Phase.RESULT・4-2実装済み・2026-10-11・DESIGN.md 10.6）

7日目の閉店後に結果画面が出て、そこから再挑戦などを選べる。コミットは`8a804eb`（累計データと
結果の集計。画面なし）と`33a70b4`（結果画面と`Phase.RESULT`）。テストは761件成功（4-1の672件に
`result_test`・`save_state_test`／`balance_log_test`の追加分で711件、`result_flow_test` 50件で761件。
既存テストの書き換えなし）。自動試遊は3シード×13方針で運営費65の結果と39/39周が完全一致し、
結果画面の集計値と日別集計も36/36周で一致した（残り3周は空の椀のゲームオーバーでRESULTに入らない）。
画面は仮表示（本番UIはフェーズ6）。

- **フェーズと最終日の流れ**：`Phase`の末尾に`RESULT=6`（`GAME_OVER=5`の次。既存の番号は変えていない）。
  `GAME_OVER`と同じ終端で、`advance_phase()`の先頭ガードで`[次のPhase]`は効かない。最終日の
  NEXT_DAYでは、`day_ending`を発火して最終日の記録を累計に足し、**日次リセットも日数加算もせず**
  `RESULT`へ入る。旧版の「最終日の翌朝に`reset_for_new_game()`＋`game_restarted`」は廃止で、
  `game_restarted`が発火するのは結果画面の「新しい周」だけ。最終日のあとは何も初期化しない
  （`day_count`は7のまま、`morning_snapshots`・`day_records`も残る）。
- **累計**：`GameState.day_records`（`SAVED_FIELDS`。`reset_for_new_game()`でクリア）。
  `DebugPanel._on_day_ending()`が組む`log_entry`（`balance_log.jsonl`と同じ辞書）を
  `record_day()`で1日ずつ足し、**同じ日の記録があれば置き換える**（試遊・テストが同じ日の
  `day_ending`を直接呼んでも二重にならない）。朝の辞書に入るので、再挑戦・続きからで戻した朝より
  後の日の記録は持たない（やり直した日を二重に数えない）。`log_entry`には4-2で追加キー
  `regular_cups`・`regular_great`・`regular_good_plus`・`regular_visits`を足した（キー追加のみ）。
  帳簿（`ledger`）には評価・未提供・廃棄が無いため、成績は帳簿ではなくこの記録から出す
  （金額＝現金・修繕額は引き続き`money`と帳簿から導く）。
- **集計と目標**（`Result`・静的クラス。画面から分離した純粋関数）：`summarize`／`judge_goals`／
  `format_report`／`format_goals`／`format_story`。定義は3-8の試遊と同じ。GOOD以上率＝
  Σ(GOOD＋GREAT)÷Σ評価対象需要（`judged_planned_cups`。未提供も分母に残す）。常連GREAT＝名前あり客
  （`customer`が`mob#`で始まらない）への提供でGREATだった**杯数**。未提供＝Σ(計画杯数−提供杯数)。
  廃棄＝Σ廃棄**額**（品目数も併記）。現金＋修繕額＝所持金＋帳簿`fund`の支出合計（修繕基金は4-9で
  積めるようになった。積まなければ0）。目標は`Rules.goals()`（標準1500／挑戦1600／料理0.85／常連GREAT 8杯）で、完走・
  標準・挑戦・料理・常連の順に判定する。**表示のみで、ゲーム状態には影響しない**（未達でも物語や
  続きのプレイを失わない）。GOOD以上率の境界（ちょうど85%）は杯数同士で比べて取りこぼさない。
  3-8の試遊では基本GOODの方針は常連GREATが0.0杯で、好物を狙う方針で14〜20杯。
- **結果画面の表示**：`_set_runner_for_phase(RESULT)`がTEXTイベント3本を積む（店の成績／目標／
  仮の物語欄）。物語欄（街で起きたこと／客との間に残ったこと）は、評判の上下・早期閉店の有無・好物を
  知った客のID・来た常連のID（と来店日数）だけで、**成績の数値・語は出さない**（料理成績を人間関係の
  善悪や真エンド条件にしない）。表示名は客データに無いためIDのまま。本文は4-4〜4-8。
- **選択肢**（`ResultRow`・RESULTのときに表示。**【2026-10-18】GAME_OVERでも表示して流用する**。§6「ゲームオーバー」参照）：[もう一度（Day1の朝から）]＝
  `retry_from_morning(1)`でDay1の朝へ戻り、累計も戻る（戻した日より後の朝の記録は捨てる。
  ボタンに「Day1の客・需要のみ同じ。2日目以降は評判次第で変わる」と表示。**[続きから]で始めた周は
  Day1の朝の記録が無いので押せず、理由が出る**）／[最後の朝からやり直す]＝
  `retry_from_morning()`（最終日の朝）／[新しい周]＝`reset_for_new_game()`→`game_restarted`→
  Day1のWAKE（画面側の一時状態も初期化）／[終わる（フェーズ6）]＝押せない仮ボタン。
  `retry_from_morning(day := -1)`は日番号を指定して戻れる（`GameState.morning_of(day)`）。存在しない
  日・記録が無い日を指定した場合は何もしない。
- **セーブの扱い**：結果画面に入ってもセーブファイルは消さない（最後の朝＝最終日の朝が残り、次回の
  [続きから]は最終日の朝のやり直しになる）。新しい周のDay1の朝の保存で自然に上書きされる。
  封筒の版は2に上げたので、4-1のセーブは読めない扱い（新規ゲーム）になる。
- **未確認・今後**：結果画面と各ボタンの実機確認は未実施。[続きから]の実機確認も未実施（4-1）。
  `balance_log.jsonl`は再挑戦した日が二重に記録される（システム整理Aで`run_id`・`attempt`により区別できるようにした）。修繕額は4-9で積めるようになった（積まなければ0）。
  「街で起きたこと／客との間に残ったこと」の本文は来店記録（F5）・場面データ（F6）・ニュースの後
  （4-4〜4-8）。

### 市場の店の画面の2行表示（実装済み・2026-10-11・コミット`c5bc1d6`）

市場の各店の中の画面（`_market_shop != ""`）で、商品をADJUSTと同じ2行に分けて並べる。表示のみの
変更で、購入処理・価格・個数・ラベル文面は変えていない。テストは795件成功（761件＋
`tests/shop_row_split_test.gd` 34件。既存テストの書き換えなし）。自動試遊は3シード×13方針で
運営費65の結果と39/39周一致。実機でも食肉仲卸の並びを確認済み。

- **行の決め方**（`DebugPanel._shop_good_row(good)`。判定は既存の`Ingredients.is_topping()`／
  `is_flavor()`のみで、新しい分類基準は無い）：具材→具材の行（`_options_row`。ADJUSTと同じく具材を
  優先）／調味料→調味料の行（`_seasoning_row`）／`dashi`（濃縮だし。`item`を持たない資源）→
  **調味料の行**（鍋の濃さを上げる素材として。肉卸の具材の行は具材だけになる）／それ以外→具材の行。
- `_add_pot_button(label, is_disabled, handler, row = null)`に省略可能な`row`を追加（省略時は従来どおり
  `_options_row`）。`[市場に戻る]`・店を選ぶ画面・`[市場を出る]`は従来どおり具材の行で、行は分けない。
  調味料の行は`_update_options_row()`の先頭で毎回クリアされるので、店を出ても残らない。
- **店ごとの並び**：青果＝調味料[苦瓜]／具材[冬瓜]。食肉仲卸＝調味料[濃縮だし]／具材[モツ・モツ(小口1個)・
  軟骨・すじ肉]。乾物調味料＝調味料[ナムプリックパオ・ココナッツミルク・薬膳ナンプラーだれ・塩漬けライム]／
  具材[乾燥きくらげ]。豆腐麺・海鮮・くず物＝調味料の行は空、全商品が具材の行。
- 苦瓜はタグが`BITTER`のみなので調味料の行に入る（ADJUSTと同じ既存仕様）。空の調味料の行は高さ0で、
  非表示にする処理は入れていない（デバッグ画面なので許容。本番UIはフェーズ6）。

### 常連の固定日程とモブ規則（4-3実装済み・2026-10-12・DESIGN.md 10.5.1・10.8.1）

常連の来店を抽選から10.5.1の固定日程（21枠）に切り替え、モブの抽選ルールを常連の枠から分離した。
コミットは`c26504d`（データ追加と読み込み。動作は変えない）と`0378166`（切り替え）。テストは
958件成功（`c26504d`の時点は974件。`0378166`で旧`day_schedule.json`との比較が不要になって減った）。
書き換えた既存テストは`schedule_test.gd`の1件だけ（Day2夜半・明け方が「3人のどれか」→
「夜半＝配達員・明け方＝チンピラ」。抽選から固定への仕様変更）。

- **データ**：`data/schedules/week7_regulars.json`（`{"days":{"<日>":[{"slot","regular"}…]}}`。
  枠は辞書なので、4-4以降で`episode_id`などを足せる）と`data/schedules/mob_rules.json`
  （`{"default":{"pool":[7種],"slots":{枠名:bool}},"days":{"<日>":{枠名: false | {"pool":[…]}}}}`）。
  `week7.json`の`regular_schedule`（"week7_regulars"）を`Rules.regular_schedule()`が返し、
  `ScheduleData.regular_schedule_data()`が`data/schedules/<id>.json`を読む。
- **互換層**：`ScheduleData.day_schedule(day)`は`compose_day_schedule(day)`が2ファイルから組み立てた
  旧と同じ形`{"slots":[{name, main, mob}]}`を返す（`mob`は`false`か`{"pool":[…]}`）。
  `customer_schedule()`・`_plan_mob_groups()`・`Forecast`・`DayPlanner`は無改修。定義の無い日
  （Day8以降）は常連もモブ規則もDay1へフォールバックする。旧`data/day_schedule.json`と
  その読み込みは削除した。**【4-4aで撤去済み】互換層（`compose_day_schedule`・`day_schedule`）と
  `_pick_main`の`main_pool`分岐は消え、DayPlanが日程を直接読む**（「客データの分割と場面ID（4-4a）」節）。
- **常連の固定日程（10.5.1）**：

| 日 | 宵の口 | 夜半 | 明け方 |
|---|---|---|---|
| 1 | 配達員 | チンピラ | 老婆 |
| 2 | 新人警官 | 配達員 | チンピラ |
| 3 | 夜の女 | 老婆 | 新人警官 |
| 4 | 配信者 | 夜の女 | 配達員 |
| 5 | チンピラ | 新人警官 | 配信者 |
| 6 | 配達員 | チンピラ | 夜の女 |
| 7 | 配信者 | 新人警官 | 老婆 |

  来店回数は配達員4・チンピラ4・新人警官4・老婆3・夜の女3・配信者3＝21。同日の重複なし。
  初登場は新人警官＝Day2、夜の女＝Day3、配信者＝Day4（いずれも宵の口）。Day7明け方は老婆。
  常連の選択に乱数を使わなくなった（`_pick_main`は常に`main`を持つ枠を見る）。
- **モブは変えていない**：Day1は`week7.json`の`day_overrides."1".mobs`の固定編成が優先（自動経路）。
  `mob_rules.json`のDay1の日別上書き（宵の口＝港湾労働者／夜半＝3種プール／明け方＝なし）は、
  デバッグ上書き（モブ人数を指定したDay1）で使われる。Day7の明け方もモブなし。Day2〜6の
  明け方はモブ可（組の3番目が入る）のまま。Day2以降は常連が毎日3人・各1杯なので、モブ杯数
  （総需要−3）と組の配分は従来と同じ。配達員の3杯の専用イベントはDay1だけ（Day2・4・6は1杯）。
- **21枠のデータ存在確認**：全枠で基本注文・好物・杯数・会話が存在し、10.5.1の基本注文と一致する。
  13枠は当日の日番号キーを持ち、8枠（配達員Day2・4・6、チンピラDay2・5・6、老婆Day3・7）は
  客JSONのDay1の内容へフォールバックする（「日によって変えない」方針どおり。内容はプレースホルダー）。
  4-4で客JSONの`days`を分けるとき、この8枠は「日番号キーが無い＝基本プロフィール」になる。
- **試遊（30シード×13方針・運営費65・数値は調整していない）**：進行停止0。10.13の各項目・Day1（510）・
  結果画面の集計一致（360/360周）が合格。基本GOODは平均現金1624→1622、1500達成率86.7%→93.3%
  （合格ライン85〜95%の内側だが上限に近い。30シードで1周≒3.3ポイントなので、固定日程による
  構造的な上振れかは判別できない。フェーズ5の人の試遊で見る）、GOOD以上率98.2%→98.5%。
  好物を使う方針の常連GREAT杯は14.5→14.8（既知好物）／20.7→20.8（初回から好物）で、目標8杯は
  好物を使えば届く水準のまま。結果は`planning/playtest_2026_10_11/PLAYTHROUGH_RESULTS.md`の
  4-3の節（全13方針、30シードとシード1〜3）。
- **未対応**：常連の注文カード・今日の頼み・来店記録・場面データは4-4以降。客JSONの`days`は未分割。

### 客データの分割と場面ID（4-4a実装済み・2026-10-17・DESIGN.md 10.8.1・10.8.2・10.9）

客の会話を「今日は何日目か」ではなく「今日の枠に割り当てた場面（episode）」で引く形にした。
**動作は変えていない**（会話・要求・好物・杯数・反応文・乱数の消費順は4-3と同一）。コミットは
`66ea16c`（データ追加。旧経路のまま）と`3127319`（切り替えと撤去）。ほかに`8721ae7`（テスト入口の
修正。下記）。テストは1211件成功（4-3の958件に、場面データの検証248件・`episode_flow_test`などを
追加）。3シード×13方針の自動試遊は4-3の結果と39/39周完全一致。

- **データ構成**：`data/customers/<id>.json`＝基本プロフィール`{is_mob, favorite, wanted_tags}`
  （基本注文は日によって変えない＝10.5.1。`days`は廃止）。`data/episodes/<客>/<客>_<連番>.json`＝
  来店場面`{id, customer, greet, reactions, servings}`（来店順に配達員・チンピラ・新人警官が`_01`〜`_04`、
  老婆・夜の女・配信者が`_01`〜`_03`の計21ファイル。`requires`・`callback`・`body`・`choices`・
  `today_request`は4-4aの時点では未実装。`requires`・`order`・`callback`は4-4b-2で読めるようになった）。中身は旧`days`をそのまま移した仮データで、各客で全日同一。
  `week7_regulars.json`の各枠に`episode_id`が付いた。
- **21枠と場面ID**：

| 日 | 宵の口 | 夜半 | 明け方 |
|---|---|---|---|
| 1 | delivery_man_01 | thug_01 | granny_01 |
| 2 | officer_01 | delivery_man_02 | thug_02 |
| 3 | hooker_01 | granny_02 | officer_02 |
| 4 | streamer_01 | hooker_02 | delivery_man_03 |
| 5 | thug_03 | officer_03 | streamer_02 |
| 6 | delivery_man_04 | thug_04 | hooker_03 |
| 7 | streamer_03 | officer_04 | granny_03 |

- **DayPlanの枠**：`today_plan["slots"]`の各枠は`{name, customers, regular_id, episode_id}`。
  `name`・`customers`（`[regular_id, "mob#N"…]`）・`mob_instances`は従来のままで、
  `OpenController`は無改修。`customer_schedule()`は`ScheduleData.regular_slots(day)`を直接読み、
  モブの可否は`ScheduleData.mob_rule_for(day, slot_name)`（`mob_rules.json`の既定＋日別上書き）で引く。
- **場面の引き方**（`Day1Events.episode_id_of(customer_id)`）：(1) `today_plan["day"] == day_count`なら
  その客の枠の`episode_id`（前日の枠で別の日の場面を引かないため、日が違うときは使わない）、
  (2) なければ`regular_slots(day)`の枠、(3) 日程に無い客はその客の最後の場面（3杯列を踏まない）。
  `_customer_flavor`は`customer_profile`＋`episode_data`をマージする。`Forecast`・杯数先読み・
  `Result`は`customer_events`経由なので無改修。
- **配達員の3杯列**：判定を`day_count == 1`の直書き（2箇所）から、定数`THREE_CUPS_EPISODE`
  （`delivery_man_01`）との場面id比較に置き換えた（**システム整理Eで、場面データの`cups`から組む形に
  置き換え済み。定数と専用列は無い**）。Day2・4・6の配達員は通常の1杯。
- **撤去**：4-3の互換層（`compose_day_schedule`・`day_schedule`）、`Day1Events._pick_main`
  （`main_pool`の抽選）、`ScheduleData._FALLBACK_DAY`・`customer_data(id, day)`、客JSONの`days`。
  日程の無い日（Day8以降）は枠が空＝客なし（実プレイでは最終日7でRESULTへ入るので起きない）。
- **保存**：封筒の版を2→3に上げ、`is_valid()`が各枠の`name`・`customers`・`regular_id`・`episode_id`の型を
  検査する。4-3以前の保存（版2）は読めない扱い＝新規ゲーム。
- **意図した差（ゲーム内で呼ばれない6組）**：日程に無い組（Day1の新人警官・夜の女・配信者、Day2の
  夜の女・配信者、Day3の配信者）は、旧データでは会話の無い空の客で、新実装では通常の場面を返す。
- **テストの書き方（`8721ae7`）**：`tests/run_tests.gd`は、読み込めない・インスタンス化できない・
  `run()`が無い・実行中のエラーで途中打ち切りになったスイートを、止まらず失敗として数える
  （書き換えたテストの構文エラーで73分終わらなかったため）。**各スイートの最後は
  `return c.finish()`にする**（`TestCheck.finish()`が集計表示と走り切った印`completed_runs`を記録し、
  `run()`の前後で増えなかったスイートを失敗にする）。存在しないスイートを指定したときも失敗で終わる。
- **未対応**：（来店記録と`known_favorites`の置き換えは4-4b-1、場面の選び方・前回を読んだ2行・注文カード・
  今日の頼みは4-4b-2で済み。下の節）新人警官の市場会話（`day_count == 2`）と
  チンピラの場所代の日番号判定は、システム整理Aで場面データ（`market_talk`）と`bills[].scene`へ移した。

### 来店記録（F5・4-4b-1実装済み・2026-10-17・DESIGN.md 10.8.5）

名前あり客ごとに「いつ来て、何を出して、どう評価されたか」を残す`GameState.customer_memory`を作り、
旧`known_favorites`を置き換えた。**記録するだけで、台詞・判定・乱数・好物の開示のタイミングは
変えていない**（3シード×13方針の自動試遊は4-3の結果と39/39周完全一致）。コミットは`30210f1`
（器と記録。`known_favorites`は残して一致を確認）と`3eb3d4b`（`known_favorites`の撤去）。
テストは1272件成功（4-4aの1211件に`customer_memory_test`などを追加。22スイートすべてが走り切る）。

- **形**：`customer_memory[客id] = {favorite_known: bool, visits: [{day, slot, served, grade, grades,
  ingredients, episode_id}], facts: {}, seen_episodes: [場面id…]}`。`visits`は来店1回につき1件、
  `facts`は空のまま（`CustomerMemory.set_fact`／`fact`の手段だけある。4-4b-2で`requires.facts`が読むようになったが、書く`sets_facts`は4-5以降）、
  `seen_episodes`は重複なし。`request_honored`・`choices`はシステム整理C2で`visits`の任意キーとして実装。好感度のような
  数値は持たない。**対象は名前あり客だけ**（モブのインスタンスidは記録しない。
  `CustomerMemory.is_recordable()`）。
- **書き手**（`scripts/customer_memory.gd`・状態を持たない静的クラス）：`arrive()`＝客が来店した時点で
  その日の来店を`served=0`で1件作る（`DebugPanel`が客を読み込むときに呼ぶ。同じ日に何度呼んでも増えない）。
  `record_serve()`＝提供のたびにその来店へ杯ごとに追記（`served`・`grades`・`ingredients`）。
  断り・提供できず退店・早仕舞いは`served=0`のまま「来た」事実が残る。到着前に閉店して来なかった客は
  記録しない（日の集計には従来どおり未提供で残る）。`last_visit(id)`・`visits_of(id)`が読み口。
- **評価と杯数の数え方**：`served`は提供した杯数の合計（持ち帰りのように評価しない杯も数える）。
  `grades`は杯ごとの評価（評価なしの杯は空文字）。`grade`は評価した杯の最悪値
  （`OpenController.RESULT_ORDER`の低い順）で、評価なしの杯は含めない（例：`["GOOD","BAD",""]`→`BAD`）。
  結果画面の集計が`judged`で分けるのと同じ扱い。`ingredients`は杯ごとの配列の配列（1杯の客も`[[…]]`）。
- **好物の既知状態**：`knows_favorite(id)`・`mark_favorite_known(id)`は関数名を維持し、
  `customer_memory[id].favorite_known`を読み書きする（呼び出し側は無改修）。開示のタイミングは従来と
  同一（単発の客は提供の瞬間、配達員は退店時、断った客は知らないまま）。`mark_favorite_known`は
  知った客のキーを辞書の末尾へ入れ直す＝`GameState.known_favorite_ids()`が旧`known_favorites`と
  同じ「知った順」（来店順ではない）を返す。この順序は保存・再挑戦の往復後も保たれる（テストで確認）。
  結果画面の物語欄の渡し元は`known_favorite_ids()`に置き換えたが、文言は変えていない。STATE VIEWERの行は
  `favorite_known(好物を知っている客)`。
- **保存**：`customer_memory`は`SAVED_FIELDS`に入り、`known_favorites`は外れた。封筒の版は3→4
  （4-4b-1①で1回だけ上げた。版3以前の保存は読めない＝新規ゲーム。4-4b-2で版5、4-7①で版6に上がった）。`MorningSave.is_valid()`が型検査
  （辞書／各客の`favorite_known`はbool／`visits`・`seen_episodes`は配列／各visitの`day`・`served`は整数、
  `slot`・`grade`・`episode_id`は文字列、`grades`・`ingredients`は配列）を行う。①時点の版4（旧
  `known_favorites`の余分なキー付き）も、余分なキーが無視されるので読める。再挑戦・続きからで戻した朝より
  後の来店記録は持ち越さない（`day_records`と同じ）。`reset_for_new_game()`で空にし、
  `reset_for_new_day()`では消さない。
- **未対応**：（場面の選び方・前回を読んだ2行・注文カード・今日の頼み・聞き直しは4-4b-2で済み。下の節）
  （`choices`・`sets_facts`・`request_honored`はシステム整理Cで済み。下の節）結果画面の物語欄の本文は4-8。

### 場面の選び方・今日の頼み・前回の2行・注文カード（F6・4-4b-2実装済み・2026-10-17・DESIGN.md 10.3.2・10.5.2・10.5.3・10.8.6）

場面を「前提を満たす未読のもの」から選ぶ仕組み、今日の頼み（実効注文）、前回の料理を読んだ2行、
注文カードと`[聞き直す]`を入れた。**現行の21場面は`requires`・`order`・`callback`を持たないので、
既存データでは動作が変わらない**（3シード×13方針の自動試遊は各コミットで4-3の結果と39/39周完全一致。
日別・現金・評判・インシデント・結果画面の集計まで差分0）。新しい仕組みはテスト内のデータ
（`tests/fixtures/episodes/`）で確認している。コミットは`0a5a0bb`（選び方と今日の頼み・版5）、
`53560b1`（実効注文を判定へ）、`1f3cb76`（前回の2行・注文カード・聞き直し）。テストは1388件成功
（4-4b-1の1272件に1339→1352→1388と追加。25スイートすべてが走り切る）。

- **場面データの読み口**（`ScheduleData`）：`episode_requires`（`facts`・`not_seen`だけ。orや式は持たない）、
  `episode_today_request`（`order.today_request`＝`{tags, label}`。`tags`が空・形が不正なら空）、
  `episode_callback`、`episode_candidates(客)`（その客の場面id。id順）。`sets_facts`・`choices`・`body`・
  `closing`・`must_info`は読まないが、入っていても壊れない。テストは`ScheduleData.episodes_dir`を差し替えて
  場面の置き場を切り替える（切り替えたら`clear_cache()`）。
- **場面の選び方**（`scripts/episode_selector.gd`・静的クラス・乱数なし）：`EpisodeSelector.select(客, 静的id)`。
  (1) 日程（`week7_regulars.json`）の静的`episode_id`を第一候補にし、`requires`を満たせばそれ。
  (2) 満たさなければ、その客の他の場面（id順）から最初に`requires`を満たすもの。
  (3) どれも満たさなければ第一候補へ戻す（10.8.6の「短い近況の場面」データは作っていない）。
  `not_seen`は`customer_memory[id].seen_episodes`（`CustomerMemory.has_seen`）、`facts`は
  `CustomerMemory.fact`（**無い事実はfalse扱い**）で判定。`min_visits`・`last_grade`は採っていない
  （前回の評価は`callback`が担い、他の条件はfactsで表せる）。`customer_schedule()`（WAKE）が枠ごとに選び、
  枠の`episode_id`と`today_request`（場面の`order.today_request`。無ければ`{}`）に入れる。杯数の先読み
  （`_customer_total_servings`）は選んだ場面で数える（`customer_events(客, mob_count, scene_id)`の省略可能な
  `scene_id`。DayPlanがまだ無い途中でも選んだ場面を引くため）。
- **実効注文**（10.3.2）：`_customer_flavor`が、基本注文（プロフィールの`wanted_tags`）を今日の頼みの`tags`で
  **上書き**する（足し算ではない）。好物・杯数は変えない。上書きしたときだけ、REACTに`base_wanted_tags`
  （基本注文）が付く（無い場面はキー自体が無い＝従来のREACTと同一）。判定（`judge_bowl`）・計器盤・試遊の
  `cook()`はREACTの`wanted_tags`を読むので自動で実効注文に追従する。**`SaleRule`は注文タグを使わない**
  （味・具・濃さ・杯数だけ）ので無改修。**朝の予報は基本注文のまま**（10.4「今日の頼みは会話で判明」）：
  `Forecast.orders_of`は`base_wanted_tags`があればそれを使う。今日の頼みの取得は
  `Day1Events.today_request_of(客, 場面id)`（DayPlanがその日のもので場面idが枠と同じなら枠の値＝WAKEで
  確定・再挑戦でも変わらない。そうでなければ場面データ）。
- **前回を読んだ2行**（`Day1Events._callback_lines`）：場面に`callback`があるときだけ、`GREET`の前に最大2行
  （`GREET`イベント）を足す。出し分けは**今日より前の最後の来店**（`CustomerMemory.previous_visit`。
  `last_visit()`は`arrive()`が作る今日の来店を拾うので使わない。`day < 今日`で見るので再挑戦で戻して
  やり直しても同じ）：来店なし→`first`／`served=0`→`last_unserved`／GREAT・GOOD→
  `last_grade_good_or_better`／OK・BAD→`last_grade_bad`（キー名は10.8.6のまま。OKもこちら）／提供したが
  評価なし→`last_ungraded`（任意）。**評価で料金・評判・関係は変えない**（どの行を読むかを選ぶだけ。
  好感度の数値は持たない。失敗した前回にも関係が続く台詞にするのはデータ側＝4-5の方針）。状態を
  読むだけで書かないので、`Forecast`・杯数の先読みが`customer_events`を何度呼んでもREACTの数・杯数・
  記録は変わらない。現行の21場面は`callback`が無いので何も出ない。
- **注文カードと`[聞き直す]`**（`DebugPanel`・仮表示。本番UIはフェーズ6）：ADJUST中の名前あり客にだけ、
  `_format_open()`に「── 注文カード ──／いつもの：HOT/POWER ／ 今日：MELLOW/GENTLE（ラベル）」を出す
  （今日の頼みが無い客は「いつもの：…」のみ。タグは既存どおり「/」区切り）。`[聞き直す]`ボタン
  （`_on_reask_pressed`）は、カードと場面の`order.reask`（無ければ客の`greet`）を再表示するだけ：
  画面側の`_reask_text`を書くだけで、所持金・評判・評価・来店記録・`facts`・`GameState`を一切変えない
  （何度押しても同じ。保存しない。客が替わる・再挑戦で消える）。**モブと、複数杯の場面（`cups`。Day1の配達員の3杯）には出さない**
  （`_adjust_customer_id()`が`Day1Events.is_multi_cup_scene`で判定）。確認操作は正解の印にしない。
- **保存**：封筒の版を4→5に上げた（版4以前の保存は読めない＝新規ゲーム）。各枠に`today_request`
  （辞書。今日の頼みが無ければ空）が必須で、`MorningSave.is_valid()`が型検査する。再挑戦は保存した
  DayPlanを戻すので同じ`today_request`になる。場面データを読むだけで保存する状態は増えていない。
- **書き換えた既存テスト**：`episode_flow_test.gd`・`customer_memory_test.gd`（版の数値）、
  `save_state_test.gd`・`save_file_test.gd`（枠の固定値に`today_request`を追加。版5の`is_valid`が要求）。
  ③では既存テストの書き換えなし。
- **未対応**：（`sets_facts`・`choices`・`body`・`closing`・`must_info`はシステム整理Cで、ニュースはDで済み）本文（4-5以降）、
  実データの今日の頼み・`callback`（現行の21場面には無い。試作は4-5）、`servings`を持つ今日の頼み
  （総需要の引き算に効くため見送り）、「短い近況の場面」。（レシピ保存と「いつもの」ボタンは手順4-7で済み。）
  （新人警官の市場会話とチンピラの場所代の日番号判定は、システム整理Aで済み。下の節）

### システム整理A（表示名・balance_logの区別・日番号の直書きの置き換え・実装済み・2026-10-17・DESIGN.md 10.9）

素材が要らないシステムの整理を5コミットで行った。**自動試遊（3シード×13方針）は各コミットで4-3の結果と
39/39周完全一致**（会話・要求・金額・乱数の消費順は変わっていない）。テストは1528件成功
（4-4b-2の1388件から。30スイートすべてが走り切る）。コミットは`2f375a4`（表示名）・`17c5b4f`
（balance_log）・`262c137`（market_talk）・`bb85c1d`（場所代・市場解禁日）・`5d1643d`（需要経路）。

- **客の表示名**（`2f375a4`）：`data/customers/<id>.json`に`"name"`（配達員・チンピラ・老婆・新人警官・
  夜の女・配信者。値は旧`Day1Events.CUSTOMER_NAMES`と同じ。定数は削除）。読み口は
  `ScheduleData.customer_display_name(id)`（プロフィールが無い・`name`が空ならid自体を返す）。
  結果画面の物語欄（`Result.format_story`の「好物を知った客」「店に来た常連」）と予告メモが表示名で出る。
  計器盤・STATE VIEWER・Ledgerは**IDのまま**（デバッグ用でID検索に使う）。場面データの文言（`greet`・
  `reactions`）は変えていない。モブは従来どおり`Day1Events.mob_display_name()`。
- **balance_logの区別**（`17c5b4f`）：書き出しを`BalanceLog`（`scripts/balance_log.gd`・静的クラス）へ移した。
  `user://balance_log.jsonl`の各行に`run_id`・`attempt`を**追加**（既存キーは変えない）。`run_id`＝周ごとの識別子
  （起動時刻ミリ秒・プロセスid・連番。`reset_for_new_game()`で`begin_run()`。ゲームの乱数は使わない）、
  `attempt`＝その周で朝から戻した回数＋1（再挑戦で`note_retry()`）。続きからで読み込んだ周は`run_id`が新しくなり
  `attempt`は1に戻る。集計側は同じ`run_id`・同じ`day`のうち最後（attemptが最大）の行を取る。行に足すのは書き出す
  複製だけで、`GameState.day_records`に入る辞書は変えない（保存の版は上げない。`day_records`は朝の辞書に入り
  再挑戦で戻るので二重にならない）。書き出し先は`BalanceLog.path`で差し替えられ、`tests/run_tests.gd`と
  試遊（`planning/playtest_*/playthroughs.gd`）は別ファイルに書く＝実ログを汚さない。
- **新人警官の市場会話**（`262c137`）：`day_count == 2`の直書きと定数`_OFFICER_MARKET`を削除し、
  場面データのキー`market_talk`（行の配列）に移した（現行は`officer_01.json`だけ）。`prep_after_tier_events()`が
  `Day1Events.market_talk_events()`でMARKETの前に差す：今日のDayPlanの枠（無ければ`regular_slots(day)`）の場面が
  `market_talk`を持つものだけ、枠の順に全部出す（同じ場面は1回）。**一度見た場面でも出す**（`seen_episodes`は
  見ない。今の割り当てでは影響が無く、同じ場面が複数日に来る設計になった時点で決める）。状態を読むだけで書かない。
  Day1〜8のPREPのイベント列は旧実装で記録した`tests/fixtures/prep_events_system_a.json`と完全一致。
  `ScheduleData.episode_market_talk`が読み口（文字列の行だけ拾う）。
- **場所代と市場の解禁日**（`bb85c1d`）：チンピラの`PAY`は、`Rules.bills_for_scene(客id, 日)`（`bills[]`の`scene`が
  その客で`days`に今日を含む請求）から作る。客idの直書きと`is_collection_day()`は使わない。`kind`は請求の`id`
  （`"rent"`）、金額は請求の`amount`、文言は`<表示名>（<label>）`＝「チンピラ（場所代）」（`week7.json`の`bills`に
  `"label"`を追加）。`Rules`に`bill(id)`・`bill_amount(id, fallback)`・`bills_for_scene`を追加。市場の店の
  `enabled`は`day_count >= Rules.market_open_from_day()`（値は2）。`is_collection_day()`を使う`DebugPanel`の3箇所
  （WAKEの確保額・水道代・家賃回収後の理由文）は請求全体の判定なので変えていない。
- **需要経路**（`5d1643d`）：`use_demand_system`の`day_count > 1`を削除。Day1は`day_overrides."1".mobs`
  （`use_fixed_mobs`）で既に除外されており、「固定モブ編成が宣言されていない日」が総需要システムを使う日になる。
- **書き換えた既存テスト**：`customer_memory_test`・`result_flow_test`（期待する文面をIDから表示名へ）、
  `balance_log_test`（専用の出力ファイルを読む）、`episode_data_test`（場面の任意キー`market_talk`を許し、
  型と「`officer_01`だけが持つ」を検査）。新規：`display_name_test`・`balance_log_retry_test`・
  `market_talk_test`・`bill_scene_test`・`demand_route_test`。
- **残る日番号の直書き**：（配達員の3杯列は、4-4aの場面id判定を経てシステム整理Eで場面データの`cups`になった。）`bills`の`days`・`day_overrides`・`final_day`・
  `market_open_from_day`はデータ側。`RENT_PRICE`は`bills`から引く。10.9の表の直書きは、この節で一通り置き換え済み。
- **未対応**：`_OFFICER_AFTER`・`_OFFICER_PAYMENT`（提供後の共通会話・会計）のデータ化は本文の移し替えなので
  脚本の段階（4-5以降）。（場面機能の残りはシステム整理Cで済み。下の節）。

### 提供後の場面（反応・本文・選択・締め・事実・システム整理C1／C2実装済み・2026-10-17・DESIGN.md 10.5.3・10.5.4・10.8.5・10.8.6）

場面に「提供後」の部分を足した。来店〜注文（4-4b-2まで）に続く、反応 → 本文 → 選択 → 締め → 事実の器。
**現行の21場面は新しいキーを持たないので、動作は変わっていない**（3シード×13方針の自動試遊は各コミットで
4-3の結果と39/39周完全一致）。新しい仕組みはテスト内のデータ（`tests/fixtures/episodes/`）で確認している。
コミットは`b7d3985`（読み口と検証・`pre_order`）・`4a1c98e`（提供後の列・断った客のUNSERVED）・`fc6b2a2`
（閉店で退店する客の未提供版）・`c14c034`（選択と締めの差分）・`a74d8c1`（`sets_facts`・`request_honored`・保存の検証）。
テストは1839件成功（システム整理Aの1528件から。35スイートすべてが走り切る）。

- **場面データの新しいキー**（すべて任意。`ScheduleData`の読み口は、無い・形が不正なら「無い」と同じに読む）：
  `pre_order`（前回の2行と注文＝`greet`の間の行）、`body`（食事中の話）、`body_unserved`（提供しなかったときの本文。
  `must_info`を持つ場面だけが使う）、`closing`（`{default, "<選択id>:<選択肢id>", "request_honored:true|false"}`）、
  `choices`（最大2つ。各`{id, options:[2つの{id, label, set}]}`）、`sets_facts`、`must_info`（印を読むだけ。
  9項目の管理は日別ニュース＝D）、`reactions`に`UNSERVED`。`ScheduleData.scene_problems(ep)`が形を検査する：
  選択の数・二択・id一意、**事実のキーは選択肢の`set`と`sets_facts`を合わせて重複を除き2個まで**
  （両方に同じキーは不可）、`closing`のキーが選択か`request_honored`に対応すること、`must_info`と`body`が
  あれば`body_unserved`が必須。実データ21場面は新キーを持たず問題なし（テストで固定）。
- **提供後の列の組み方**（`Day1Events.after_serve_events(客, 場面, {served, grade})`）：REACTの処理が済んだ後に
  `DebugPanel._insert_after_serve_events`が、現在位置の直後（常にindex 2以降。モブの2レシピ目と同じ差し込み方）へ
  差し込む。来店時に最後まで固定せず、実際の出来が出た後に組む。**状態を読むだけで書かず、乱数を使わない**
  （何度呼んでも同じ。`customer_events`には本文・締めを含めないので`Forecast`・杯数の先読みは不変）。
  `EventRunner`は変更なし（条件分岐は組み立て側）。順序は REACT → 本文 → 選択 → 締め → SCENE_END →
  既存の`_customer_extra_events`（警官の共通会話・場所代のPAY）。モブ・複数杯の場面（`cups`）・場面データに該当キーが
  無い客は何も差さない。反応は従来どおりREACTの状態表示（`reactions[出来]`の2パターンの抽選）のまま。
  **本文・締めは出来（grade）で分けない**（10.5.3「差分は冒頭2行・反応・締めだけ」。わざと失敗すると親密に
  なる経路を作らないため、締めの引き当てに`grade`を使わない）。読んでいる間に鍋・腐敗・客の待ちは進まない
  （ターン制。写しの一致をテストで確認）。
- **提供しない経路**：
  断る → REACT直後に`reactions.UNSERVED`（要素0。乱数を引かない。`_declined_now`で表示）、`must_info`を持つ場面だけ
  `body_unserved`。鍋不足の[閉店]・自動閉店（接客中でserved=0の名前あり客）→ `_queue_unserved_exit`が
  `Day1Events.unserved_exit_events`をCLOSEの先頭（理由テキストの次・閉店の語りの前）に積む（反応のGREETと
  `must_info`ありなら`body_unserved`）。**到着前に閉店して来なかった客の場面は再生しない**（来店していない客が
  話すことになり、来店記録を作らない設計＝4-4b-1とも矛盾する。必須情報の担保は日別ニュース＝Dが担う前提）。
  提供しなかった客では`facts`を立てない。断った場面も来店記録の`seen_episodes`に入る＝読んだ扱い。
- **選択（`CHOICE`）**：本文の後に選択ごとに入力待ちで出す（`{type:"CHOICE", choice_id, options:[{id,label}]}`）。
  仮ボタンは`_update_options_row`の分岐（`_on_story_choice_pressed`）。選択中は[次のEvent]・[入力完了]が効かず
  飛ばせない。合わないidは何もしない。`CustomerMemory.record_choice`が今日の来店の`choices`（選択id→選択肢id）へ
  残し、選択肢の`set`を`facts`へ即時に書く。**料金・評判・評価・鍋・在庫・腐敗・時間帯は変えない**（写しで確認）。
  断った客・閉店で退店する客には選択を出さない。最後の選択が済んでから`closing_events`を組んで差し込む。
- **締め**（`Day1Events.closing_events`）：`default`に、選んだ選択ごとの差分（場面の選択の順）と、
  `request_honored:true|false`の差分を**足す**（置き換えではない）。該当キーが無ければ`default`だけ。
- **事実（`SCENE_END`）**：`sets_facts`を持つ場面で、提供した客の列の最後に積み、締めを読み終えて来たとき
  1回だけ`facts`へ書く（`CustomerMemory.set_fact`）。断った客・閉店で退店した客・途中の閉店や再挑戦では書かない。
  翌朝の`EpisodeSelector`が`requires.facts`で読み、事実が立つ前は別の場面（`thug_01`）、立った後は`thug_02`を選ぶ
  ことをテストで確認。
- **`request_honored`**：`visits[]`の任意キー。**今日の頼みがある場面の判定した杯だけ**、実効注文のタグを
  すべて椀が満たしたら（`match_count` ≧ タグ数）true、そうでなければfalse（濃さ・傷みの減点は見ない＝頼まれた
  中身に応えたかであって出来の評価ではない）。複数の杯があればすべて応えたときだけtrue。頼みの無い場面・
  断った客にはキー自体を入れない。
- **保存**：封筒の版は5のまま。`visits`の`choices`（辞書。選択id・選択肢idは文字列）・`request_honored`（bool）は
  任意キーで、**あるときだけ**`MorningSave.is_valid()`が型を検査する。旧形式（キー無し）の保存も読める。
  往復（`to_dict`／`from_dict`・ファイル）で型ごと戻り、朝へ戻す（再挑戦）と来店記録と`facts`が朝の状態に戻る
  （`tests/scene_facts_test.gd`）。
- **試遊のハーネス**：`planning/playtest_2026_10_11/playthroughs.gd`に、CHOICEなら先頭の選択肢を押す分岐を
  足した（現行データでは通らない）。
- **書き換えた既存テスト**：`episode_data_test.gd`の1件だけ（新キーを持たないことと`scene_problems`が空であることの検査）。
  新規：`scene_keys_test`・`after_serve_test`・`choice_test`・`scene_facts_test`。
- **未対応**：（複数杯の場面はシステム整理Eで済み。次の節。複数杯の場面での本文・選択・締めは未対応）
  `_OFFICER_AFTER`・`_OFFICER_PAYMENT`のデータ化・本文・選択肢・締めの文面（脚本＝4-5・4-8）。日別ニュースと必須情報の管理はシステム整理Dで済み（次の節）。

### 日別ニュースと必須情報・共通イベント（システム整理D実装済み・2026-10-17・DESIGN.md 10.5.5・10.10の4-6）

本筋の**必須情報9項目**（SEVEN_DAY_OUTLINE §11）を、**客の会話に頼らず**プレイヤーへ届ける仕組み。朝のニュース・DM・
スマホのニュースタブ・営業中の共通イベント（客の抽選に依存しない出来事）の4つ。**表示だけで数値には触れない**
（所持金・評判・在庫・鍋・DayPlan・帳簿・需要・客の構成は不変。写しで確認）。保存の版は5のまま
（再生済みの記録は保存しない実行時の値）。**現行データでは自動試遊（3シード×13方針）が4-3の結果と39/39周完全一致**
（`steps`・`clicks`・`actions`・`rows`を含む全キー差分0。ハーネスの読み飛ばしは下記）。コミットは`61a80a0`
（データ・カタログ・検証）・`2c843b6`（朝のニュースとニュースタブ）・`763ca9c`（共通イベント）。
テストは2013件成功（システム整理Cの1839件から。38スイートすべてが走り切る）。

- **データ**：`data/news/week7.json`（`Rules.news()`＝`week7.json`の`"news"`が指すid。**宣言済み・未使用だった項目が
  使われ始めた**）。`must_info`＝カタログ`[{id, day, label}]`（9項目: strike_started D1・checkpoints D2・
  nightlife_spillover D3・video_spread D4・night_removal D5・rights_shift D5・clash_fire D6・
  official_arson_claim D7・truth_unresolved D7）、`days.<日>`＝`{news:[{id, headline, body[], must_info[], provisional}],
  dm:[{from, text, provisional}], events:[{id, at, lines[], must_info[], provisional}]}`。日番号はデータが指す
  （コードに書かない）。**文面はすべて仮案**（`provisional: true`。SEVEN_DAY_OUTLINEの仮案。概要表に文面の無い
  `night_removal`（Day5）と`truth_unresolved`（Day7）は実装側が仮の1項目を補った）。脚本で差し替えるときは
  文面を直して`provisional`を外すだけでよい。
- **`News`（`scripts/news.gd`・静的クラス・乱数なし・状態なし）**：`catalog`／`day_entry`／`delivered_days`／`problems`／
  `scene_problems`／`morning_events`／`event_lines`／`pending_events`／`event_by_id`／`tab_text`。
- **担保の検証**（`News.problems`と`tests/news_data_test.gd`）：9項目すべてが**ニュースまたは共通イベント**の
  `must_info`に、概要表（§11）の日に現れる（**客の場面は根拠に数えない**）。落とす条件：項目の欠落・日の食い違い・
  未知のid・`at`が`wake`／`close`／時間帯名でない・idの重複・`lines`／`headline`が空・日のキーが最終日を超える・
  カタログ無し。場面データの`must_info`は補強の印で、`News.scene_problems(ep)`がカタログに無いidを弾く
  （実データ21場面は`must_info`を持たない）。
- **朝のニュースとDM**：`Day1Events.wake_events()`の「スマホを見る。」の直後に`News.morning_events(day)`を差す
  （TEXT・`part:"news"`。`ニュース：<見出し>`→本文の各行→`DM（<送り手>）：<本文>`）。ニュースもDMも無い日は
  従来の4イベントと同一。WAKEは従来どおり[次のPhase]で飛ばせる（デバッグ。ニュースタブには今日の分が常に載る）。
- **ニュースタブ**（`News.tab_text(today, played_ids)`）：今日と、その周で過ぎた日の分だけ（**未来の日は見せない**。
  再挑戦で戻した朝より後の日も見えない）。新しい日が上（`◆今日（DayN）◆`／`◆DayN◆`）、ニュースとDMは別の行、仮データには
  `【仮】`。共通イベントは過ぎた日の分は`出来事：`として載り、今日の分は再生済みのものだけ。既読は持たない。
  何も無ければ「ニュース：まだ届いていません」。
- **共通イベント**（`at`で出す場所を決める。TEXT・`part:"common_event"`・`event_id`付き）：`wake`＝朝のニュースの後／
  時間帯名（宵の口・夜半・明け方）＝その時間帯の**最初の客の接客の前**（`DebugPanel._slot_start_events`。
  客の列の前に前置）／`close`＝閉店の語りの前。現行データはDay6だけ：衝突（`d6_clash`）が宵の口の始め、
  火災（`d6_fire`、`clash_fire`）が夜半の始め。
- **二重再生の防止**：`_played_events`（再生済みのid）と`_slot_event_ids`（時間帯の位置`slot_index:index`→前置したid）は
  **保存しない実行時の値**で、WAKE・再挑戦・[新しい周]でリセット。`_load_current_customer`が同じ客で何度呼ばれても
  同じ列を組み直すだけで二重にならない。
- **取り戻し（早仕舞い・客0人の日）**：CLOSEの先頭で、未再生の共通イベントをデータの並び順（＝時系列）で積む。
  CLOSEの並びは「閉店理由 → 未提供版の退店（C1）→ 共通イベント → 閉店の語り」。必須情報が営業の長さや
  客の有無に依存しない。
- **試遊のハーネス**：`planning/playtest_2026_10_11/playthroughs.gd`の`is_display_only`が、`type`がTEXTで`part`が
  `news`または`common_event`のものだけを、操作回数（clicks・actions・steps）に数えずに読み飛ばす
  （TEXT以外・他のpart・partの無いTEXTは対象外＝その差は見逃さない）。読み飛ばしを無効にすると144件の不一致が出る
  （Day6の共通イベントが実際に流れている確認）。
- **書き換えた既存テスト**：なし。新規：`news_data_test`・`news_morning_test`・`common_event_test`。
- **既知の制約・未対応**：
  ・時間帯の共通イベントは「その時間帯の最初の客の前」に出るため、**客のいない時間帯は飛ばされ**（`OpenController`の
    `_skip_finished_slots`）、そのイベントはCLOSEでの取り戻しになる。宵の口が0人で夜半に客がいると、火災が先に出て
    衝突が閉店時になり**時系列が逆**になりうる（`clash_fire`の担保は崩れない）。現行の固定日程では起きにくい。
    直すなら「時間帯の頭に、データ順でそれより前の未再生イベントも一緒に出す」。
  ・ゲームオーバーでCLOSEに来ない周には取り戻しが届かない（Day6には営業中の支払いが無く、現行ルールでは起きない）。
  ・文面・見出し・DMの差出人は仮案。日別の市場の変化（Day7の海鮮の閉鎖・傷みなど）は別タスク。
  ・**フェーズ6（本番UI）への申し送り**：朝のWAKEを最後まで流す設計にする（デバッグの[次のPhase]での飛ばしを残さない）。

### 複数杯の場面（配達員の3杯・システム整理E実装済み・2026-10-18・DESIGN.md 10.8.6・10.9）

Day1の配達員の「同じ客へ3杯を1杯ずつ出す」専用のEvent列を、場面データの形（`cups`）で表せるようにした。
**動作を変えないデータ化**：Event列・杯ごとの要求タグ・好物・反応・売上・乱数の消費順は従来と同一
（記録`tests/fixtures/customer_events_4_3.json`と、キー集合まで含めて完全一致をテストで固定。3シード×13方針の
自動試遊は各コミットで4-3の結果と39/39周完全一致）。これで10.9の日番号・客idの直書きの置き換えは一通り済んだ。
コミットは`a8eeae1`（データの形・読み口・検証・組み立て）・`01519e4`（配達員の3杯列を場面データへ移す）。
テストは2101件成功（システム整理Dの2013件から。39スイートすべてが走り切る）。保存の版は5のまま。

- **データの形**：場面データの任意キー`cups`（杯の配列。**2杯以上**。1杯の`cups`は複数杯の場面とは扱わない）。
  杯のキー（すべて任意）：`tags`（その杯の要求タグ。省略＝客プロフィールの`wanted_tags`）、`favorite`（`false`で好物なし。
  省略＝プロフィールの好物）、`adjust`／`serve`（ADJUST・SERVEのtext。省略＝通常の既定文）、`reactions`（結果→文字列配列。
  省略または空＝反応を出さない）、`after_talk`（その杯のREACTの後の会話。最後の杯の分が退店の会話）。
  場面の`greet`が来店〜1杯目の注文。杯数は`cups`の数（各杯`servings:1`）で、場面直下の`servings`は書かない
  （書いてあれば`cups`の数と一致を検査）。`delivery_man_01`だけが持つ（3杯：1・2杯目は阿強本人の分＝`HOT/POWER`・
  好物`tofu`・反応あり、3杯目は持ち帰り＝`MELLOW/GENTLE`・好物なし・反応なし）。仮台詞は一字も変えずに移した。
- **読み口と組み立て**：`ScheduleData.episode_cups(客, 場面)`（形の整った杯だけを読む。不正は「無い」と同じ）、
  `Day1Events.is_multi_cup_scene(客, 場面)`、`Day1Events._cups_events(客, 場面)`。`customer_events`は場面に
  `cups`があれば`_cups_events`を返す（客や場面idの直書きは無い）。`_cups_events`は 来店会話（`greet`）→ 各杯
  （ADJUST → SERVE → REACT → `after_talk`）で、2杯目以降のADJUSTに`new_bowl:true`、全REACTに`aggregate:true`
  （鍋の消費と売上はその場で、評判と提供記録は退店時に客1人分として1回だけ。受け側`DebugPanel`は変えていない）。
  `favorite:false`の杯はREACTに`favorite`のキー自体を付けない。状態を読むだけで乱数を使わない。
  `Forecast`・`_customer_total_servings`は`customer_events`のREACTを走査するので、Day1の9杯・配達員3杯は不変。
- **検証**（`ScheduleData.scene_problems`）：`cups`が2杯以上、各杯の型と未知のキー、`servings`と杯数の一致。
  **複数杯の場面で使えないキー**：`reactions`（場面直下）・`order`・`callback`・`pre_order`・`body`・
  `body_unserved`・`choices`・`closing`・`sets_facts`は「複数杯の場面（cups）では使えない」と返す
  （黙って無視される書き間違いを作らないため）。`requires`・`not_seen`・`market_talk`・`must_info`・`greet`は使える。
- **1杯の場面だけの機能は出さない**：提供後の列（`after_serve_events`）・閉店で退店する客の未提供版
  （`unserved_exit_events`）・締め（`closing_events`）・注文カードと[聞き直す]（`_adjust_customer_id`）は、
  `is_multi_cup_scene`で空／対象外に統一した。
- **書き換えた既存テスト**：`episode_data_test.gd`（複数杯の場面の必須キーは`id`・`customer`・`greet`。`cups`を持つのは
  `delivery_man_01`だけという検査を追加）、`after_serve_test.gd`（`THREE_CUPS_EPISODE`の1行を場面idに）、
  `regular_schedule_test.gd`（場面の杯数を数えるとき、複数杯の場面は`cups`の数で数える）。新規：`multi_cup_test`。
- **未対応（将来）**：複数杯の場面での本文・選択・締め・`sets_facts`・`callback`・`pre_order`・今日の頼み。
  最後の杯のREACTの後に`after_serve_events`を差す形で足せる見通し（順序は「最後のREACT → 本文・選択・締め →
  その杯の`after_talk`」が自然）。`callback`は、`previous_visit`の`grade`が複数杯でどうなるか
  （最悪値か最後の杯か）を決めてから許可する。台詞は仮のまま（脚本＝4-5・4-8）。

### レシピ保存・「いつもの」・会話ログ・既読スキップ（手順4-7実装済み・2026-10-18・DESIGN.md 10.4・10.4.1）

システム側の最後の大きな塊。画面は`DebugPanel`の**仮UI**（本番UIはフェーズ6）。**ゲームの動作は変えていない**
（会話・要求・金額・乱数の消費順は同一。3シード×13方針の自動試遊は各コミットで4-3の結果と39/39周完全一致。
新しい機能は試遊が操作しない限り状態に現れない）。コミットは`a0431ed`（①レシピ保存と「いつもの」）・`24d59e6`
（②会話ログと注文の要約）・`2100e40`（③既読の記録とスキップ）。テストは2255件成功（システム整理Eの2101件から。
42スイートすべてが走り切る）。**保存の版は5→6（①の1回だけ）**。

- **保存レシピ**（`GameState.saved_recipes`）：`[{ name, ingredients:[具材id…（1〜3）] }, …]`、最大`Rules.recipe_slots()`枠
  （`week7.json`の`"recipe_slots": 3`）。`SAVED_FIELDS`に入り**朝の保存に含む**＝再挑戦・続きからで、戻した朝より
  後の保存は消える（周回の中の状態）。`reset_for_new_game`で空。書き手は`RecipeBook.save(枠, 名前, 具材)`だけ
  （空き枠なら追加、保存済みの枠なら上書き。範囲外・飛ばした番号・不正は保存せずfalse）。`MorningSave.VERSION`＝6、
  `is_valid()`が「枠数以内・各要素が`name`文字列と`ingredients`1〜3個の文字列」を検査。**版5以前は読めない**
  （新規ゲーム。移行処理なし）。
- **名前の候補**（`data/recipes/names.json`・`RecipeBook.names()`）：10.4.1の6つ（`{id, name, tags}`）。**名前は表示だけで
  性能は変えない**。`tags`は説明用で判定に使わない。`names_ordered(椀の味のタグ)`は、候補のタグを椀が**すべて含む**ものを
  先頭に並べるだけ（どれでも選べる）。
- **「いつもの」**（`RecipeBook.usual_for(客)`）：新しい保存状態は無く、来店記録から引く。**今日より前**の来店のうち、
  評価した杯（`grades[i] != ""`）の最後の具材の並び。断った・未提供・評価なしの杯は飛ばす（今日の来店は含めない）。
  名前あり客のみ。
- **適用**（`DebugPanel._on_recipe_apply_pressed`）：**具材ボタンを順に押したのと同じ処理**（`_on_ingredient_selected(id, false)`）
  を1つずつ呼ぶ＝在庫・鮮度の確認と消費は省略しない。有効な条件：ADJUST中の名前あり客（モブの団体注文は対象外）・
  **椀が空**・**新鮮な在庫が`使う回数×servings`以上**（`RecipeBook.shortage`／`can_apply`）・具材1〜3個。全部出せると
  確かめてから適用（途中で止まって一部だけ入らない）。**傷んだ側は自動では使わない**。足りない具材はラベルに
  「足りない：…」と出して無効にする。適用後の`additions`・在庫・腐敗・来店記録・帳簿・判定は手で押した場合と
  同一（2つのパネルで比べて確認）。**ボタンには具材の並びだけを出し、前回の評価も、今回の注文に合うかの予測も出さない**
  （注文カードが唯一の手がかり。評価は注文の要約で見られる）。
- **保存の操作**（仮UI）：`_can_save_recipe_now()`＝OPENで、名前あり客の判定済みの椀（追加1つ以上）が残っている間
  （**その客の最後の行まで**押せる。複数杯の場面は各杯が対象で、次の杯のADJUSTで消える。モブ・断った客は対象外）。
  `[レシピを保存]` → 枠（空き／上書き）→ 名前（候補。やめるあり）の段階ボタン。ボタンは`SeasoningRow`の下にコードで足した
  `_recipe_row`（`.tscn`は変えていない）。
- **30%短縮**（具材ボタン＋レシピボタン＋`[入力完了]`で数える）：追加2つ＝手3回→レシピ2回（33%）、追加3つ＝4回→2回
  （50%）。売れる椀は追加が最低2つ（味と具）なので最小でも33%。テストでレシピ経路が2回の操作で提供まで進むことも確認。
- **会話ログ**（`TalkLog`・静的クラス）：**実行時のみで保存しない**。今日の分だけ（WAKEと再挑戦・
  `_reset_transient_panel_state`でクリア）、上限`MAX_LINES`＝300行（超えたら古い行から捨てる）。1行＝
  `{day, kind, speaker, text}`（`kind`：narration／talk／serve／reaction／news／choice。話し手は表示名、モブは種類の名前）。
  記録は`DebugPanel._record_visible_event()`で、**`_refresh()`の末尾**から呼ぶ（どのハンドラ直呼びでも、新しく
  current になった行が index 0 を含めて漏れない）。位置（日・フェーズ・時間帯・客のindex・イベントのindex・本文）で
  二重を防ぐ（`_load_current_customer`の再呼び出し・再描画で増えない）。REACTは`_current_reaction_text()`の文を
  1回だけ（`reaction_variant`は判定時に固定済みの値で、記録は**乱数を引かない**。再描画20回でも乱数列が進まない
  ことをテスト）。選択（CHOICE）は`_on_story_choice_pressed`で選んだラベルを記録。状態を読むだけでゲームの数値には触れない。
- **注文の要約**（`TalkLog.order_summary_lines()`）：来店記録の**全日分**（新しい日が上）。
  `DayN 時間帯　客名：いつもの <基本注文> ／ 今日 <今日の頼み>（<label>） → 出した：<具材> → <評価>`。複数杯の来店は
  杯ごとに「具材（評価）」を並べ、出さなかった来店は「出さなかった」（今日の分は「まだ出していない」）。来店記録と
  場面の注文から組むので新しい保存状態は無い。スマホの4つ目のタブ「ログ」（`TalkLog.tab_text()`）に出る。
- **既読**（`ReadState`・静的クラス）：「プレイヤーが見たことがあるか」＝**再挑戦・新しい周でも消えない**ので
  **朝の保存には入れない**（`CustomerMemory.seen_episodes`＝場面の選び方に使い再挑戦で戻る、とは別物）。保存先
  `user://read_state.json`（`{version:1, lines:[キー…]}`。`path`で差し替え可）。行のキー＝`kind|speaker|part|本文のsha1`
  （本文が差し替わった行は未読に戻る。数値入りの行は数値が変わると未読になる）。行が見えたとき（`_record_visible_event`と
  同じ箇所）に`mark`し、それまで未読だったかを`_last_shown_unread`に覚える。書き出し（変更があるときだけ）は
  日の終わり（`_on_day_ending`）・結果画面・パネルの終了（`_exit_tree`）の3点。`enabled=false`で読み書きしない。
  `reset(パス, 有効)`で開始時にメモリ上の集合とパスを初期化する。**試遊（`playthroughs.gd`）は`ReadState.enabled = false`**、
  **`tests/run_tests.gd`は`user://test_read_state.json`へ差し替え**（単体実行でも実際の既読を読まず・書かない）。
- **既読スキップ**（`[既読スキップ]`仮ボタン。`[次のEvent]`の隣にコードで足した）：`[次のEvent]`
  （`_on_next_event_pressed`）を止まる条件に達するまで繰り返す。**効果の適用は`[次のEvent]`と同一の経路を1イベントにつき
  1回だけ**通す（別経路は無い）＝会計・来店記録・事実・評判は1回だけ適用される（手動で最後まで押した場合と、
  `GameState`・提供記録・帳簿・来店記録・椀・位置まで完全に一致することをテスト。SERVE→REACT→本文→締め→SCENE_END→
  場所代のPAYを含む列で、会計1回・事実1回）。止まる条件：入力待ち（ADJUST・CHOICE・MARKET・PREP_TIERなど。**選択は決して
  飛ばさない**）／新しく見えた行が未読（その行で止まる）／runnerやフェーズの入れ替わり（ゲームオーバーを含む）／
  `[次のEvent]`が押せない状態（鍋不足の保留など）／`SKIP_READ_LIMIT`＝200回。`_can_skip_step()`は最後のイベントには
  進まない（客・フェーズの切り替わりをまたがない）。
- **書き換えた既存テスト**：`episode_flow_test`・`episode_select_test`（版の期待を6に）、`news_morning_test`・
  `scene_facts_test`（「版は5のまま」の検査を6に）。新規：`recipe_test`・`talk_log_test`・`read_state_test`。
- **未対応・制約**：
  ・会話ログは今日の分だけで保存しない（過去の日の本文を残す・検索するのは本番UI＝フェーズ6で決める）。
  ・モブの団体注文はレシピ保存・「いつもの」の対象外（分割提供との整合が重いため）。入れるなら人数確定後に1人前の
    椀として切り出す条件が要る。
  ・既読を消す操作は無い（`user://read_state.json`を消す）。既読スキップは行単位で、客や場面が替わるたびに押し直す。
  ・フェーズ6：朝のWAKEを最後まで流す設計にする申し送り（Dの節）は変わらない。画面は仮UIで、見た目は作り込んでいない。

### 修繕基金（手順4-9実装済み・2026-10-18・DESIGN.md 10.7・10.10。MVP版）

システム側の最後の塊。画面は`DebugPanel`の**仮UI**（本番UIと本番の文面はフェーズ6／素材待ち）。**積まない限りゲームの動作は変わらない**
（会話・金額・乱数・文面は同一。3シード×13方針の自動試遊は各コミットで4-3の結果と39/39周完全一致＝既定の方針は基金を操作しない）。
**保存の版は6のまま**（基金は帳簿`fund`の1行で、`MorningSave`の帳簿の検証は`day`と`amount`の型しか見ず`category`・`ref`を限定しない
ため、往復できる）。テストは2414件成功（4-7の2255件から。44スイートすべてが走り切る）。

- **経緯**（コミット）：
  ①`1327ac7`・②`573032b`＝最初の版（累計の境目150／300／600で段階が上がる方式）。
  ③`fbdd59f`＝基金の自動試遊（別枠方針）。**毎晩上限まで積む方針は30周すべてがゲームオーバー**（Day4が29周・Day5が1周。Day1の夜に
  350を積み、Day2の仕入れが87〔基準は229〕に落ちて戻れない）。原因は、安全上限が翌朝の運営費＋最小の仕込み80しか見ておらず椀の
  材料費を見ていなかったことと、最終日は上限が所持金そのもので基金が必ず満額になること（最終日に積む方針は全周600を積めた）。
  ④`0663ac2`・`bec0c3a`・`d1ba848`＝**現行の仕様**（MVP版。下記）に見直し、③と同じ試遊を再実行。
- **現行の仕様**（MVP版）：任意の積み立て。**修繕の対象（看板・棚・雨よけ・名義）ごとに値段を持ち、プレイヤーが積む先を選ぶ**。
  値段に達した対象が「修繕済み」になる。**売上・需要・評判・料金などゲームの数値を変える効果は無い**（変わるのは表示だけ）。返金不可
  （取り消し・引き出しの操作は無い）。目標判定は「現金＋支払済み修繕額」のまま（積んでも現金目標が不利にならない。`Result.repair_paid`の
  計算は変えていない）。仕入れと同じ現金（所持金）から払う＝「今日入れるか、明日の仕入れに回すか」。
- **設定**（`data/campaigns/week7.json`の`repair_fund`。`Rules.repair_fund()`が読む。数値・並び順・`requires`はすべてデータ）：
  `steps`＝積む額の刻み（10／30）、`nightly_max`＝1晩に積める額の合計の上限（30）、`targets`＝`[{ id, label, price, note, requires }]`
  （看板`sign`150／棚`shelf`200／雨よけ`awning`200／屋台を自分の名義に`owner`600。`owner`の`requires`は他の3つ）、任意の
  `cup_material_cost`（1杯の材料費の目安の定数。あれば優先）。`label`・`note`は**仮の文面**（脚本で差し替える）。不正値（正の整数でない
  刻み・上限・値段、`id`が空・重複、`label`が空）は無視して整え、`requires`は存在する他の対象だけ残す。刻み・1晩の上限・対象のどれかが
  1つも残らない・`repair_fund`が無い設定は**機能オフ**（積み立て行・サマリー・結果・状態表示は従来のまま）。
  `Rules.bills_total_on(day)`を追加（指定日の請求`amount`の合計。`is_collection_day`は変えていない）。
- **MVPの狙い**：7夜すべてに30を積んで最大210＝看板（150）は5夜、棚か雨よけ（200）は7夜すべてで届くが、**3つ同時には届かない**
  （「7日で、どれか1つが直せる」）。名義（600）は届かない。最終日にも1晩の上限が掛かるので、最終日の一括払いはできない。
- **累計は帳簿から導く**（専用の保存状態は持たない）：記帳は`Ledger.record("fund", -額, "repair_fund", 0, 0, 対象id)`＝**`ref`に対象id**。
  対象ごとの累計＝その`ref`の`fund`の合計。全体の合計＝`Result.repair_paid`（`RepairFund.paid()`）。`ref`が空・未知の`fund`（開発中の記帳）は
  合計には数えるが、どの対象にも割り当てない（`unassigned_paid()`）。再挑戦で戻した朝より後に積んだ分は帳簿ごと消える。
- **`RepairFund`**（`scripts/repair_fund.gd`・静的クラス）：設定の読み出し（`steps`／`nightly_max`／`targets`／`enabled`）、状態（`paid`／
  `target_paid`／`remaining`／`is_repaired`／`repaired_ids`／`unlocked`／`target_state`／`first_open_target`／`complete`／`repaired_labels`／
  `progress_text`／`repaired_message`）、1晩の上限（`paid_tonight`／`nightly_remaining`）、安全上限（`cup_material_cost`／`demand_center`／
  `expected_cups_tomorrow`／`prep_price_for`／`next_day_reserve`／`safe_limit`）、積む処理（`max_contribution`／`can_contribute`／`contribute`）。
- **積める条件**（`can_contribute(対象id, 額)`）：機能オン・**フェーズがCLOSE**・額が刻みのどれか・対象が未修繕で解放済み（`requires`の
  対象がすべて修繕済み）・額が**対象の残り・今夜の1晩の上限の残り・安全上限のすべて以内**。満たすときだけ`GameState.try_pay`のあと記帳して
  true。満たさなければ所持金も帳簿も変えずfalse。**`_pay_or_game_over`は使わない＝基金の操作でゲームオーバーにならない**。乱数は使わない。
- **安全上限**（`safe_limit`）＝`使える現金（Ledger.usable_cash()）− 翌日の確保額`（0未満は0）。**翌日の確保額**（`next_day_reserve`）＝
  運営費＋翌日が徴収日なら請求の合計＋**翌日の仕込み**（見込み杯数に足りる最小の段階の価格。届く段階が無ければ最大の段階）＋**翌日の
  材料費**（見込み杯数×1杯の材料費の目安）。「毎日、翌日に全客へ味1＋具2の椀を出せるだけを残す」。
  ・見込み杯数＝現在の評判で引く総需要の中心（`Rules.demand_table()`。日の固定需要があればそれ。乱数を引かない）と、今日の計画の
  需要の中心（`today_plan.demand_center`）の大きいほう。今日の計画の中心が無いとき（計画が空・`-1`・日が違う・再挑戦直後など）は評判から
  引く値だけを使う（安全側）。
  ・1杯の材料費の目安＝市場の品目（`*_goods()`。濃縮だしは除く）の単価（`price/count`）の、味の素材・具の素材それぞれの**中央値**で
  味1＋具2を合算（今は5＋10×2＝**25**。価格を変えれば追従する）。`cup_material_cost`があればそれを優先。
  ・**今日が最終日**なら翌日が無いので確保額は0（上限は使える現金そのもの。1晩の上限は別に掛かる）。
- **積む時点と画面**（仮UI）：**CLOSEのrunnerを読み終えた後（DONE）だけ**、`_options_row`に**積む先の切り替えボタン**（対象ごとの進捗つき。選んだ
  対象に「▶」。修繕済み・未解放は押せない）と、**額のボタン**（「修繕基金に積む +10／+30」。積めない額は無効）を出す。積む先の選択は実行時のみ
  （保存しない。フェーズが替わると既定＝最初の未修繕で解放済みの対象に戻る）。全対象が修繕済みなら「完了」でボタン無し。PREP・OPEN中、スマホを
  開いている間は出ない。**`[次のPhase]`のゲートと`close_events()`のTEXT列は変えていない**（押さなければ「積まない」。既読・会話ログ・試遊の
  TEXT数に影響しない）。自動閉店でCLOSEへ来た日も同じ。ゲームオーバーの日はCLOSEを経ないので積めない。
  runnerラベルの末尾の状態の文：各対象の進捗（`progress_text`。例「手書きの看板 150/150 修繕済み／棚 40/200／雨よけ 0/200／屋台を自分の名義に
  0/600（未解放）」）、今夜積んだ額／1晩の上限、積む先、今日積める上限、「（明日の仕入れ分を残す：運営費N＋請求N＋仕込みN＋材料費N＝N。見込みN杯）」
  （仮文面）。**修繕できた瞬間**は「修繕できた：〇〇」（`label`を使った固定の言い回し）を状態の文に出す（`_fund_notice`。CLOSEの間だけ。runnerの
  イベントではないので会話ログには入らない）。
- **表示への反映**（いずれも**基金を積んだ日／累計が1以上のときだけ**。積まなければ従来と同一の文面）：
  ・翌朝の成績サマリー（`_format_day_summary`）：基金を積んだ日だけ「屋台: 〈各対象の進捗〉」の行を足し、支出内訳（`_format_spend_by_category`）に
  「修繕基金N」を末尾に足す。`log_entry`に新キーは足していない（`spend_by_category`の`fund`と帳簿から導く）。日別の`closing_money`・
  `cash_by_day`は基金を引いた後の所持金。
  ・結果画面1枚目（`Result.format_report`）：累計が1以上のときだけ、現金の行の次に「屋台: 〈各対象の進捗〉」を足す。2枚目（目標）・3枚目（物語欄）は触らない。
  ・STATE VIEWER（`_format_game_state`）：累計が1以上のときだけ、budgetの次に`fund(修繕基金): 累計N／修繕済み: 〈対象名〉`の行。
- **自動試遊の別枠方針**（`planning/playtest_2026_10_11/playthroughs.gd`の`POLICIES_FUND`。**既定の一覧には入れず**、引数`[3]`で名前を指定したときだけ
  走る。基準方針`forecast_good`の振る舞いに、CLOSEでの基金の操作だけを足したもの。`DebugPanel`の積む先の切り替え・額のボタンのハンドラ経由）：
  `fund_final_only`（最終日の夜だけ、1晩の上限いっぱい）／`fund_steady`（毎晩、1晩の上限ぶんを一度に積めるときだけ）／`fund_max_safe`
  （毎晩、積めるだけ＝1晩の上限と安全上限の小さいほう）。基金の方針の結果にだけ追加キー（日ごとの積んだ額・修繕済みの対象と日など）が付く。
  結果：③（見直し前）`PLAYTHROUGH_RESULTS_FUND.md`・`playthrough_results_fund.json`・`playthrough_summary_fund.json`・`summarize_fund.mjs`、④-③
  （見直し後）`PLAYTHROUGH_RESULTS_FUND_V2.md`・`playthrough_results_fund_v2.json`・`playthrough_summary_fund_v2.json`・`summarize_fund_v2.mjs`
  （③の結果は上書きしていない。V2の最後の節に見直し前との比較がある）。
- **見直し後の測定結果**（各30シード、基準方針と同じシード）：
  ・基金の全方針（90周）で**ゲームオーバー0・停止0・未完走0**。見直し前に全30周がゲームオーバーだった`fund_max_safe`も**30周とも完走**。
  ・**現金＋修繕額は全方針で基準方針と全周同じ**（平均1622）。標準目標（1500）に届く割合も全方針で基準と同じ93.3%（最終日の現金は`fund_steady`が
  1412＋修繕210）。基金は成績を損なわなかった。
  ・修繕できた対象：`fund_steady`・`fund_max_safe`は全30周で**看板が5夜目に修繕済み**、最終日の時点で棚が60/200・雨よけ0。`fund_final_only`は最終日に
  30だけ積み、修繕済みの対象は無い。名義には全方針で届かない。`fund_final_only`は基準方針と30組すべて一致（現金＋修繕額と1〜6日目の日別の行）。
  ・**安全上限が1晩の上限（30）より小さくなった夜は90周のどこにも無い**（積む前の安全上限は、各夜で最小でもDay2の94。Day1=110・Day4=198・
  Day5=372・Day6=547）。基準方針に近いプレイでは1晩の上限が先に効く。したがって`fund_steady`と`fund_max_safe`の結果は同一。安全上限は現金が
  苦しい周のための保険で、テスト（所持金575なら上限20で30は拒否・10は積める、など）で確認済み。**現金が苦しい周での基金の試遊は未実施**。
- **書き換えた既存テスト**：4-9①②の`repair_fund_test`・`repair_fund_ui_test`を新仕様へ全面更新（他のテストは`RepairFund`を使っていない）。内容：
  対象ごとの累計と修繕済み・`owner`の未解放・1晩の上限・安全上限（翌日の確保額の各項目、安全上限が1晩の上限より小さい夜、最終日、見込み杯数の
  フォールバック）・拒否・目標判定の不変・効果が無いこと・`ref`が空の記帳・保存の往復と版6・機能オフ・積めるだけ積んだ後にWAKEへ進めること／
  積み立て行・積む先の選択・状態の文・「修繕できた」・サマリー・結果・STATE VIEWER。
- **未対応・制約**：
  ・対象の名前・文面（`label`・`note`）は仮。段階ごとの見た目（看板・棚・雨よけ・名義の絵）は本番UI＝フェーズ6／素材待ち。
  ・名義（`owner`・600）はMVPの7日では届かない（長い周のための枠）。長い周で使う値は`week7.json`とは別に持つ（`DESIGN.md`10.7）。
  ・積む時点はCLOSEのみ（仕入れ前のPREPでは積めない）。
  ・見込み杯数・材料費は目安で、実際の需要・仕入れ額とずれることがある（余裕は足していない。材料費の中央値25は③の測定の約19より高く、その分が安全側）。
  ・現金が苦しい周での基金の試遊は未実施。

### 四つの支払いのトーン（金額処理は共通、text だけで差別化。2026-09-26改訂）
- 市場（仕込みベース） -80: 淡々「いつもの。80だ」
- 日々の運営費 -75（80→3-8で65→2026-10-18に75。文面の金額は定数から埋め込むので自動で追従）: WAKEで前振り「共同水道と炭屋への払い（¥75）は、もう済ませた。」
  （2026-10-18に「市場を出るときにまとめて渡す分として先に取っておく」から変更）→ 市場を出た瞬間に「共同水道と
  炭屋に寄り、市場を出た。」（両方とも表示専用。実際の天引きはWAKEで完了済み。
  毎日発生）
- 水道 -50: 徴収日のみ`[市場を出る]`で自動精算（2026-09-26改訂：専用の訪問セリフは
  廃止し、無言で精算される）
- 場所代 -90（2026-09-26改訂：150→90）: 理不尽「あ、そうだ。今月分。」（徴収日のみ）

### 本番UI（UI準備A・B・実装済み・2026-10-24〜25）

**UI準備A（処理の切り出し）**：DebugPanelが兼任していた「操作と問い」を `PlaySession`
（`scripts/play_session.gd`。Node。`FlowController`を子に持つ）へ移した。画面は`PlaySession`の問い
（`day_info`・`current_line`・`pot_view`・`bowl_view`・`ingredient_options`・`fund_view`・`phone_news`…）を読み、
操作（`next_event`・`select_ingredient`・`buy_item`・`choose_prep_tier`・`contribute_fund`…）を送るだけ。
状態が変わるたびに`changed`が出る。使い方は`planning/PLAY_SESSION_API_2026_10_24.md`。DebugPanelは表示専用になった。
ゲームの結果は1つも変えていない（自動試遊30シード×13方針が全キー一致）。

**UI準備B（本番UIの骨組み）**：
- **メインシーン `scenes/game_root.tscn`**（1280×720）。`PlaySession`を子に持ち、`changed`で全体を描き直し、
  描き直しの最後に`record_visible_event()`（会話ログ・既読）。`phase_entering`で、スマホ・ログの開閉・鍋タブの手動切り替え・
  会話枠のページなど、表示だけの状態を捨てる。
- 左側（`scenes/ui/left_side.tscn`）：Day・時間帯ゲージ（宵／夜半／明。開店中）または画面名（朝／市場／閉店）、所持金・評判（・客足）、
  立ち絵の枠、名前の札、会話枠（1行30字×3行。入りきらない文は枠内でページ送り）、選択肢、スマホ・ログのアイコン、既読スキップ。
  会話を進めるのは左の列のクリック・Enter・Space（**UI準備Dで「会話枠のクリック」から「左の列のどこでも」に広げた**。下の「画面の使い勝手（UI準備D）」）。
  **【2026-10-25・クリックの修正】**画面に出す文が無い進行だけのEvent（初日セットの受け取り＝`ADD_ITEM` 7件）は、会話を進めたとき続けて進める
  （`UiLeftSide.SILENT_TYPES`。Day1の仕込みで、会話枠が空のままクリックを12回求められていた→5回）。押せない「既読スキップ」は
  クリックを受けず、下の会話枠に通す（押せるときだけ、右下のそのボタンが受ける）。クリックのテストは本物のマウスイベント
  （`Viewport.push_input`で座標つき。当たり判定を通る）で行う：`tests/ui_click_test.gd`、台本`tests/ui_autoplay.gd`の`click`も同じ。
- 右の枠（同じ位置 (836,24) 420×672 に重ね、状態に合う1つだけを出す）：朝（昨夜の成績）・市場・購入（食肉仲卸／ほかの店）・
  開店の操作エリア（鍋／トッピングのタブ）・閉店（今夜の結果と修繕基金）・スマホ（**会話ログは右の枠ではなく、UI準備Dで会話枠が上へ伸びる形にした**）。全面（左側と右の枠を隠す）：仕込み・結果・ゲームオーバー。
- 共通：`resources/ui_theme.tres`（配色12色＝`UiPalette`・型の変種）、Noto Sans JP（`assets/fonts/`。OFL）。
  寸法は`planning/KAITEN_UI_LAYOUT_2026_10_24.md`・`SCREENS_UI_LAYOUT_2026_10_24.md`の表どおり。
  シーンは`tools/build_ui_scenes.gd`が最初に作ったもの（**再実行すると手の調整が消える**。既存のファイルは引数`--overwrite`が無ければ上書きしない）。
  UI準備Cでの変更（`pane_phone.tscn`のSNSの未読ラベルなど）は`.tscn`を直接編集しており、生成スクリプトには反映していない。
- 開店の鍋・トッピング：傷んだ在庫は具材ボタンを2つに分ける（本体＝新鮮、右端「傷N」＝傷んだ側）。椀の枠は傷んだ具材を注意色の枠で「豆腐(傷)」。
  具材の名前は短縮名（`data/ui/ui_labels.json`の`short_names`。開店の操作エリアだけで使う）。
  `bowl_view()`は、品目ごとの傷んだ印`additions_damaged`を返す（表示だけ）。
- 市場：「この店で買った」「¥24 使った」は、UIだけの集計（`scripts/ui/shop_tally.gd`。保存しない）。
- ゲームオーバー：`PlaySession.game_over_info()`が、詰んだ支払いの種類・必要額・所持金・日・フェーズを返す（表示だけ）。
  「Day N の朝からやり直す」のNは、`retry()`が戻る先の朝（運営費が払えなかった朝は記録されないので、前日の朝）。
- テスト：`tests/ui_left_side_test.gd`・`ui_panes_test.gd`・`ui_kaiten_test.gd`・`ui_close_full_test.gd`・`ui_e2e_test.gd`
  （UIのボタンと会話枠のクリックだけで、Day1の朝から最終日の結果画面まで進める。台本は`tests/ui_autoplay.gd`）。
  スクリーンショットは`tools/ui_screens_B.gd`（`planning/ui_screens_B/`に13枚）・`tools/ui_screens_C.gd`（`planning/ui_screens_C/`）。
- 動作確認の環境：Godot 4.4.1 と 4.7.2 の両方で、全テストと、試遊の30シード×13方針の照合を行った（差なし）。

### ルールと情報の変更（UI準備C・実装済み・2026-10-25・DESIGN.md 10.4）

客足予報をやめ、客の多い少ないの手がかりを別の形で出す。DESIGN.mdの書き換えは`892dc9f`。
`planning/UI_C_RULES_INFO_REQUEST_2026_10_25.md`が依頼書、`planning/DESIGN_10_4_REWRITE_2026_10_24.md`が書き換え案の記録（反映済み）。

- **C-1 予報の表示をやめた**：本番UIは予報を出さない。DebugPanelの予報メモは「検証用」。`Forecast`は残す。
- **C-2 客足**：評判の横に「評判 33・客足 ふつう」。言葉は`data/ui/ui_labels.json`の`demand_words`、区切りは
  `Rules.demand_table()`の閾値（評判0〜19＝少ない／20〜44＝ふつう／45〜59＝多め／60〜70＝多い／71〜＝とても多い）。
  日の固定需要（Day1）やその日の事情は反映しない。
- **C-3 足りなかった杯数の内訳**：日次ログ`log_entry`に`unserved_ingredients`（素材が足りない）・`unserved_pot`（鍋が足りない）・
  `unserved_declined`（断った）・`unserved_not_arrived`（閉店のあと来られなかった客）を追加（4つの合計は`unserved_cups`。既存のキーは変えない。
  保存の形式の版は上げない）。判断の瞬間に`PlaySession.log_unserved`へ積む：名前あり客を断る＝鍋（残量・濃さ0で出せない）／素材（椀が成立せず在庫に味か具の素材が
  1つも無い）／それ以外は断った。モブの団体＝出し切れなかった分を、出せる人数を決めた制約（濃さ0＝鍋、椀が成立しない＝素材、鍋の残量と
  具材の在庫の小さい方。同じなら鍋）で分ける。閉店（手動・自動）＝今の客の残りは鍋。画面（朝の前日成績・閉店の今夜の結果）は
  「足りなかった 4杯（素材 1・鍋 2・断った 1）」で、来られなかった客の分は「鍋」に含める（`PlaySession.unserved_display`）。
- **C-4 DM（SNSタブ）**：データは`data/dm/week7.json`（`Rules.dm()`）、読み口は`scripts/dm.gd`（`Dm`）。1通は日・差出人・条件（`requires`）・
  匂わせの向き（`hint`：many／few／none）・時刻・本文（仮）。届く条件は、その日の朝の状態で決まる関数：名前あり客は初めて提供した翌日から
  （`customer_memory`）、モブは同じ種類に2夜提供した翌日から（日次ログの`mob_types_served`＝新設）、客でない差出人（市場の顔なじみ）は条件なし。
  匂わせ：many＝その日の需要の中心が「多め」の行の中心以上、few＝「少ない」の行の中心以下（数値は需要表と客足の言葉から読む）。
  必須情報はDMに置かない。ニュースのデータの`dm`欄は、ここへ移した（朝の語りにDMは出さない）。Day3のニュース`d3_spillover`の見出しは
  「…歓楽街でも仕入れと支払いが滞っている」に差し替えた。データのテスト：ニュースと共通イベントの本文に「客足」を含めない、DMの向きと中心が矛盾しない
  （`tests/dm_test.gd`）。SNSタブは`phone_dm()`（新しい順。丸い顔・名前・日付と時刻（「Day3 05:40」。届いた日の日付・時刻は2桁。形は`Calendar`の1か所。UI準備G0）・本文）、未読は左に注意色の線とSNSタブの●と数、
  「スマホ」ボタンにも●と数。SNSタブを表示した時点で既読（`ReadState`。idで持つ。保存とは別）。
- **来店予告DM（UI準備E）**：その夜に来る予定の客・モブの種類を、朝のDMで知らせる（`Dm.preview_items`。データは`data/dm/week7.json`の`previews`＝
  `max_per_morning`（3）・`mob_max`（2）・`first_day`（2）・`pools`（客・モブの種類ごとの`from`・`from_kind`・`time`・`texts[]`・`tag_hint`。文面・差出人は仮））。
  本当のことだけ：Day2以降、計画（`today_plan`）の名前あり客と、`mob_instances`の種類。選び方は乱数なし：モブの種類を先に最大2件（計画の並びから
  `(日番号＋件目) % 候補数`）、次に名前あり客（今日より前に来たことがある客を先に、同じ条件の中は日付で回す）で上限3まで。モブが2種類に満たない日は空いた分を名前あり客で埋める。
  同じ朝に届く既存DMの差出人（`requires`の客・モブ、同じ`from`）は出さない。本文は日番号と主語idのハッシュで複数の言い回しから選ぶ。`{hint}`は`tag_hint`
  （モブの好み2つのうち1つ。名前あり客は空）の言葉（`TagWords`）に置き換わる。本文に数字・「客足」を入れない（`Dm.problems`が検査）。
  過去の日は日次ログ（`day_records`）の`planned_regulars`・`planned_mob_types`（新設・追加のみ。保存版は上げない。日の終わりに`today_plan`から書く）から同じ内容で出す
  （計画は翌朝に作り直されて残らないため）。旧セーブ（キーが無い日）は、名前あり客は日程データから、モブは出さない。DMの`inbox`に入るので、未読の数・既読（idは`preview_d<日>_<主語>`）はそのまま。
  確認：`tests/dm_preview_test.gd`。
- **客ノート（スマホの「客」タブ。UI準備G）**：出会った客の好みを見返す（表示だけ。判定・乱数・保存版は変えない）。タブはSNS／ニュース／持ち物／客の4つ（各104幅。UI準備I2でレシピタブを廃止し、I3で持ち物に置き換えた）。
  `PlaySession.phone_notes()`：名前あり客（先。出会った順）＝名前・「いつもの」の札2枚・来た日（「Day1・Day2・Day4」。来店記録の日を全部）・好物の材料名（好物を知った客だけ）、
  モブ（後。出会った順）＝種類名・好みの札2枚（その種類の注文のタグ）。載る条件：名前あり客は今日より前の来店がある客、または今日の「いつもの」が分かった客（注文を言う行を見たあと）／
  モブはその種類の注文を受けた夜から（断った団体も含む）。新しい保存項目なし：名前あり客は来店記録、モブは日次ログの`mob_types_met`（新設・追加のみ。日の終わりに`GameState.served`から書く。
  旧セーブは`mob_types_served`で代用）と今夜の分。札は`UiTagChips`（客側・材料側と同じ見た目）。市場でスマホを開いて閉じても、かごは消えない。
  あわせて、DMの「常連」の印は名前あり客の差出人（`from_kind`が`customer`）だけにした（モブの組・客でない差出人には付けない）。確認：`tests/customer_notes_test.gd`。
- **収支の表示・最終日の注意・DMの見た目（UI準備I。表示だけ。判定・乱数・評判の式・チップは変えない）**：
  日次ログ（`day_records`・BALANCE_LOG）に`purchases`（追加のみ。保存版は上げない）＝その日の仕入れ（`PlaySession.purchases_from`：帳簿の`market`・`prep`・`dashi`・`kit`。
  運営費・場所代・水道代は含めない）。朝の「昨夜の成績」に「昨日の仕入れ ¥xxx」「昨日の収支 ±¥xx（売上−仕入れ−運営費。売上はチップ込み）」（Day1は場所代・水道代を見出しに添える。
  `purchases`が無い古い記録は`spend_by_category`から出す）。結果画面の成績に「仕入れ合計」（7日間）。最終日（Day7）の市場・各店・張記に「今夜が最後の営業。残った材料は持ち越せない」を1行
  （`UiParts.FINAL_DAY_NOTE`）。DMの「常連」の印をやめ、差出人（名前あり客・モブの組・市場の顔なじみ）によらず同じ見た目にした（差出人の名前と本文は変えない）。
  自動試遊の`result_summary`には`purchases`を出さない（v2の形を保つ。各日の仕入れは`rows`の`spend`にある）。確認：`tests/purchases_test.gd`。
- **持ち物（スマホの「持ち物」タブ）・レシピタブの廃止・在庫のログ（UI準備I2・I3。表示とログだけ。判定・乱数・評判の式・チップは変えない）**：
  スマホのタブは SNS／ニュース／持ち物／客 の4つ（各104幅。レシピタブは廃止して持ち物に置き換えた。`phone_recipes()`と夜の「いつもの」「保存」のデータ・動作は変えない）。
  持ち物タブ（`UiInventoryList`・`PlaySession.inventory_view()`）：上から、性質チェック（10の札。新鮮が1つ以上＝点灯・傷んだ分だけ＝半点灯・無い＝暗く）、味（調味料）と具に分けた材料
  （在庫が1つ以上のもの。名前・札・個数・新鮮／傷の内訳。鍋の素など椀に入れないものは出さない。かごに入れた分は含めない）。最終日は先頭に「残った分は持ち越せない」。
  市場でもスマホを開いて見られる（閉じると店選びに戻る。かごは別に持っているので消えない）。一覧は縦に送れる。左側の常時表示のパネルは置かない（I2で一度作ったが、I3でスマホへ移した）。
  客ノートの名前あり客の行に「前回　材料」を1行（`RecipeBook.usual_for`。前回の記録がある客だけ）。日次ログに`purchase_items`（品目ごとの個数と額。初日セット・市場・追加のだし・鍋の素`prep:<段階>`）と
  `closing_stock`（閉店時の在庫：品目ごとの新鮮・傷・評価額＝単価×個数。単価は市場でいちばん大きい袋の 値段÷個数。追加のみ）。BALANCE_LOG の表示行に在庫評価額の合計。
  結果画面の成績に「余り在庫 ¥xxx（評価額。目標には含めない）」。自動試遊の`result_summary`には出さない。確認：`tests/inventory_panel_test.gd`。
- **張記の店主との会話**（鍋の素を選ぶ直前。`part:"prep_talk"`の表示だけのTEXT）：Day1は主人公が目安の杯数を一度だけ言う
  （`fixed_demand`から読む）。Day2以降は前日の注文の杯数（日次ログの`planned_cups`。前日成績の「注文◯杯」と同じ値）と足りなかった杯数だけ。
  今夜の見込みの数は言わない。クズ野菜ベースの日は入れない。`PREP_TIER`の台詞は「（仕込む量を決める。）」。
- **C-5 鍋の条件**：前出（「鍋を触る操作」）。
- **C-7 小さな直し**：列を読み終えた画面（閉店など）でも、会話枠に最後に出した行を残す。`coconut_milk`の短縮名を「ココナツ」に。
- **C-6 予報を使わない自動試遊（新しい基準・v3）**：ハーネス（`planning/playtest_2026_10_11/playthroughs.gd`）の引数`[6]`（info）：
  `forecast`（既定。予報を読む＝v2と同じ。v2と390/390周で全キー一致）／`visible`（予報を読まず、前日の注文杯数・客足の言葉・DMの匂わせ・
  自分が受けた注文・在庫と所持金だけで決める＝v3。**言葉と数の対応を覚えた熟練プレイヤー相当**）／`visible_improvise`（visibleに加えて、
  注文のタグの素材が手元に無いとき、足りない軸〔味・具〕をほかの在庫で補う）。v3の見込み杯数＝（前日の注文杯数＋客足の言葉の帯の中心）÷2を
  四捨五入し、DMの匂わせで±1（Day1は張記の会話の9杯）。仕入れの必要数＝自分が受けた直近2夜の注文のタグの割合×見込み杯数。
  下限版（別枠）は見込み＝前日の注文杯数だけ。結果は`playthrough_results_regulars_v3.json`（visible）・`..._v3_improvise.json`・
  `PLAYTHROUGH_RESULTS_V3.md`（`summarize_v3.mjs`）。**v2（`playthrough_results_regulars_v2.json`）は上書きしていない。**

  | （運営費75・`reach_true`・各30シード） | 平均最終現金 | 1500達成 | GOOD以上率 | ゲームオーバー |
  |---|---:|---:|---:|---:|
  | v2 基本GOOD（予報あり） | 1636 | 93.3% | 98.5% | 0 |
  | **v3 基本GOOD（既定版）** | **418** | 0.0% | 64.9% | 3 |
  | v3 基本GOOD・下限版（既定版） | 422 | 0.0% | 64.5% | — |
  | **v3 基本GOOD（補う版）** | **1316** | 0.0% | 64.9% | 0 |
  | v3 基本GOOD・下限版（補う版） | 1328 | 0.0% | 63.5% | 0 |

  10.13の判定：既定版は項目1・1b・2・3・4が不合格（D1のみ合格）。補う版は項目2・3・4・D1が合格、項目1・1bが不合格。
  既定版の出せなかった杯数のほとんど（1周あたり22.8杯のうち22.7杯）は「断った」で、注文のタグの素材が無い夜に他の在庫で補わず売れない椀を
  断る方針の動き方による（プレイヤーの動きとは違う）。**運営費75は予報ありの基準で確定した暫定値で、予報を使わない前提では結論が変わる
  可能性がある。合格ラインの判断（ラインを変えるか、数値を調整するか）は、人の試遊のあとに決める（まだ決めていない）。**

### 画面の使い勝手（UI準備D・D-1・実装済み・2026-10-25）

しまさんの7日分の試遊（Godot 4.7.2）の要望。ゲームのルール・数値・日次ログは変えていない（3シード×13方針が v2 と全キー一致）。
- **会話ログ**：「ログ」で右の枠を置き換えるのをやめ、**会話枠が上へ伸びて今日の行を並べる**（`UiLogBox`＝`LeftSide`の`LogBox`。
  会話枠の下端はそのまま、上端は y232。下の会話枠と名前の札は隠す）。「ログ」をもう一度押す、または枠の外（左の列）のクリックで閉じる。
  開いているあいだのクリックは会話を進めず閉じる（枠の中のクリックは何もしない）。Enter・Space は今のまま。右の枠は触らない
  （購入などを続けて操作できる）。右の枠の `pane_log` は削除した。
- **クリックで進める**：左の列（820×720。キャラ表示エリアと会話枠）のどこをクリックしても次へ進む（背面の`ClickArea`）。
  スマホ・ログ・既読スキップのボタン、右の枠のボタンと空き部分では進まない。選択肢やボタンを待っているあいだは進まない（今と同じ）。
- **仕込み（全面）の点**：「仕込み中」の3つの点は、クリックなしで約0.7秒ごとに1つずつ点く（`UiFullPrep.STEP_SECONDS`。次のEventへ進めて点く）。
  全部点いたら「開店する」。画面をクリックするとすぐ全部点く。既読スキップは1回の操作でその場で最後まで進める（フェーズの切り替わりで止まる）ので、
  この画面を出している時点でスキップ進行中の状態は無く、待たせない。
- **朝**：「スマホを見る」ボタンを無くし、昨夜の成績の枠の主ボタンは「市場へ」だけ（朝の語りを読み終えるまで押せない）。朝の会話枠には
  ニュース（`part:"news"`）の行もスマホの入力待ち（`WAIT_INPUT`）も出さない（`LeftSide`が続けて進める。Eventの列は変えていない＝試遊のsteps・clicksも不変）。
  会話ログにも載せない。ニュースはスマホで読む。Day1の朝は従来どおりスマホ（ニュース）から始まる。
- **未読**：スマホボタンの●は**DMとニュースの未読の合計**（`PlaySession.phone_unread_count()`）。SNSタブ・ニュースタブにも●と数。
  そのタブを表示した時点で既読（`mark_dms_read`・`mark_news_read`。ReadStateにidで持つ。保存とは別）。開いた時点で未読だったニュースの見出しには
  スマホを閉じるまで●が付く。`phone_news()`の各ニュースに`id`・`must_info`・`unread`を足した。
  **事実**：朝の会話枠にニュースを出さなくなったので、必須情報（`must_info`）を持つニュースが未読のまま「市場へ」に進める（ゲートは付けていない。
  `PlaySession.unread_must_info_news()`で数えられる。テスト：`tests/phone_unread_test.gd`）。
- **店の画面**：「店選びへ」「店選びへ戻る」を「店を出る」に（動きは同じ）。
- 画面は`planning/ui_screens_D/`（`tools/ui_screens_D.gd`。変えた画面だけ9枚）。テスト：`tests/ui_click_test.gd`（本物のマウスで当たり判定を通す）・
  `tests/phone_unread_test.gd`・`tests/ui_close_full_test.gd`（点の自動進行）ほか。

#### D-2 購入確定（かご）・使える現金を超える購入の拒否（2026-10-25）

- 商品の「かごに入れる」を押しても買わない（1回で1セット。`UiShopCart`・`UiCartBox`。UIだけの状態で保存しない。店ごとに持ち、買う順番は入れた順）。
  「購入確定」（店に残る）。「1つ戻す」「全部戻す」。かごが空でなければ出口は「買わずに店を出る」。（UI準備F3：「購入して店を出る」のボタンは無くした。下段は「購入確定」「店を出る」の2つを横に並べる）
  上部の「使える」はかごの分を引いて見せる（残金・支払い予定はそのまま）。購入確定は入れた順に`buy_item`を呼ぶ（帳簿・在庫の束の並びは1つずつ買ったときと同じ）。
- 張記の鍋の素は、カードを押すと「選択中」（選び直し可。まだ買わない）。「購入確定」で`choose_prep_tier`を1回呼ぶ。続けて「店を出る」＝会話を1つ進める（UI準備F3：旧「購入して店を出る」は「購入確定」→「店を出る」の2回）。
- **使える現金（残金−支払い予定）を超える購入は`PlaySession`が拒否する**（`buy_item`・`choose_prep_tier`。`purchase_limit()`・`purchase_block_reason(price, pending)`）。
  `shop_view`・`prep_tiers`の`affordable`も使える現金で決める。画面は超える商品・鍋の素のボタンを押せなくして理由を出し、かごの合計が使える額を超えると「購入確定」を押せない。
  確認：徴収日の確保分に手を付けられる抜け道は、コード上は以前からあった（`buy_item`・`choose_prep_tier`は残金だけを見ていた）が、通常の流れでは到達しなかった（Day1は鍋の素が最大¥140で、初日セットのあとの使える¥175以内）。
  自動試遊は使える現金を超える購入をしていない（照合で不変を確認）。
- **買い物画面の配置（UI準備F3）**：表示だけ。下段は「購入確定」（左）・「店を出る」（右。かごがあれば「買わずに店を出る」）の2つ（各190幅）。「かご」は小さくして下（ボタンの上）に寄せ、
  空は1行・品が入ると最大3行まで伸び（上へ。下端は固定）、それ以上はかごの中で縦に送る。あいた高さは商品の一覧に回る（一覧の下端＝かごの上−6）。張記の鍋の素のカードは高さ119→98。
  全6店（張記を含む）で同じ配置。「鍋の素を買うまで、ほかの店へは行けない」は1行でボタン段の上。確認：`tests/market_layout_test.gd`。画面は`planning/ui_screens_F3/`（before・after）。

#### D-3 椀の追加のキャンセル（2026-10-25・DESIGN.md 10.3.1）

- 具材ボタンを同じ品目で2回押すと取り消し（椀から外し、引いた在庫を元の束へ戻す）。傷んだ側・新鮮な側のどちらのボタンでも取り消すので、同じ具材は2個入らない。
  `PlaySession.toggle_ingredient`（UIの具材ボタン）・`cancel_ingredient(index)`。`select_ingredient`（レシピ・「いつもの」・自動試遊）は入れるだけで従来どおり（重複も許す）。
- 足したときに引いた束（日・単価・個数）を`bowl_takes`に覚え（椀が替われば捨てる。保存しない）、`GameState.take_inventory`／`restore_inventory`で戻す。`additions_damaged`は同じ位置を外し、
  `used_spoiled`は残りの具材から作り直す（傷んだ具材を外せば傷みの減点も消える。`OpenController.remove_from_bowl`）。団体客（モブ）は確定まで在庫を引かないので`mob_picks`だけ外す。廃棄（椀ごと作り直す）は今のまま。
- 画面：入れた具材のボタンに「✓」。在庫が0になっても押せる（取り消せる）。`ingredient_options`に`in_bowl`を足した。
- 同じ具材を2個入れる遊び方は、ルール・レシピ・データに無い（判定は同じtagを1回しか数えない）。

#### D-4 運営費のタイミングと表示（2026-10-25・DESIGN.md 10.3.5）

- 日々の運営費75は、朝は払えるかだけを見て支払い予定として確保し、**市場を出るときに引く**（「水を汲み、炭を買った（−¥75）」）。画面の名前は「水と炭（運営費）」の1行（75は2行に割らない）。
  「水道代」は徴収日の50円の項目の名前のまま。ゲームオーバーの判定は今までどおり朝（残金＜運営費）。ゲームオーバー画面の支払いの名前は「水と炭（運営費）」。
- 実装：`check_or_game_over`（払えるかだけ）・`operating_cost_pending()`・`pay_operating_cost()`（帳簿の`ref:"operating"`の確保を読む・払ったら解く）。`exit_market`が水道代（徴収日）→運営費の順に引き、開店に入るときも未払いなら引く。
  `budget()`に`operating`を足した。クズ野菜ベースの判定（`scraps_base`）は、まだ引いていない運営費を除いた現金で決める（運営費を朝に引いていた頃と同じ判定）。
- 自動試遊のハーネス（`playthroughs.gd`）は、判断と`day1_cash`の記録を「残金−まだ引いていない運営費」（`cash()`）に切り替えた＝運営費を朝に引いていた頃の所持金と同じ値。これでv2と全キー一致を保つ。
- 「使える」の上限まで買っても、市場を出るときの運営費の支払いは必ず通る（`tests/operating_cost_test.gd`）。

#### D-5 「いつもの」「今日」の欄を常に出す（2026-10-25・表示のみ）

- トッピングのタブの「いつもの」「今日」の欄は、開店中は常に出す（客がいなくても・注文を言う前でも）。分かるまでは「？」を薄い色で出し、空白の隙間を作らない。
  以前は、注文カード（`order_card_view`）が「名前あり客・1杯の場面・ADJUST中」のときしか出ず（`adjust_customer_id`の条件）、Day1の配達員（3杯の場面）やモブの団体では欄ごと隠れていた。
- `PlaySession.order_card_view()`は開店中の今の客について、`{ customer, base（いつもの）, today（今日の頼み。無い＝いつもどおりは空）, label, usual_known, today_known, can_reask }`を返す（客がいなければ空）。
  いつもの・今日の中身は、その杯の`REACT`の`wanted_tags`（実効注文）から読む：名前あり客の基本注文はプロフィールの`wanted_tags`、モブの団体は注文のタグ。複数杯の場面は杯ごと。
- 「分かった」時点は、客が注文を言う会話の最後の行（その杯の`ADJUST`の直前の`GREET`。無ければ`ADJUST`）を表示した時点（提供のあとではない）。その行で「いつもの」「今日」（頼みが無ければ「いつもどおり」）が入る。
  前の日に来たことがある名前あり客は、「いつもの」が最初から入っている（今日より前の来店記録`CustomerMemory.previous_visit`から読む。**保存する状態は増やさない**。好物を知った状態`favorite_known`は使わず、変えない）。
  複数杯の場面の持ち帰りの頼みは、2杯目のあとの会話の最後の行で入る。モブの団体は同じ形（いつもの＝団体の注文のタグ・今日はいつもどおり。[聞き直す]は出ない）。
- [聞き直す]は、聞き直せる会話があるとき（名前あり客・1杯の場面のADJUST中）だけ出す（`can_reask`）。タグの表示（SAVORY・FILLINGなど）は今のまま。
- テスト：`tests/order_card_test.gd`。

---

## 7. 条件別Event列生成（Day2テスト・確認済み）

`GameState.is_collection_day()`（3-5で`Rules.bills()`参照に変更。値は現状
`day_count == 1`と同じ）をデータ関数が読み、
EventRunnerへ渡す前に含めるEventを出し分ける。EventRunner自体は分岐せず、
生成済みの平坦なEvent列を同じ方法で再生する。

- 場所代（`_customer_extra_events`）: thug かつ徴収日のときだけ PAY を差す
- 水道代（`_visit_water_stall()`）: 徴収日のときだけ実際に支払う（2026-09-26改訂：
  データ側のEventではなく`[市場を出る]`が直接呼ぶ処理。専用の訪問セリフは廃止し、
  代わりに市場を出た旨の表示専用TEXTを日によらず毎回`prep_after_tier_events`が出す）
- 日々の運営費（`debug_panel.gd._set_runner_for_phase(WAKE)`）: 徴収日に関わらず
  毎日直接支払う（新設・2026-09-26改訂。唯一「条件分岐しない」固定費）
- 徴収日を将来 `[1, 7, 14]` 等に広げるときは is_collection_day() の1箇所を変えるだけ
- プレイヤーの選択フラグによって後の物語Eventを変える分岐は、まだ未検証。

---

## 8. 実装済みファイル

| ファイル | 役割 |
|---------|------|
| `scripts/game_state.gd` | GameState（autoload）。事実と状態変更の入口 |
| `scripts/flow_controller.gd` | フェーズ遷移・ゲート判定 |
| `scripts/event_runner.gd` | Event 列の再生（index / status） |
| `scripts/open_controller.gd` | OPEN の客キュー管理・椀・判定（judge_bowl） |
| `scripts/ingredients.gd` | 具材マスタ（id → tags、腐るか、id → 日本語名） |
| `scripts/day1_events.gd` | Day1 の Event データ（wake/prep/customer/close）+ 分岐 |
| `scripts/debug_panel.gd` | State Viewer 表示 ＋ 受け側（_apply_event） |
| `scenes/debug_panel.tscn` | DebugPanel のシーン（デバッグ用の`[所持金 -50/+50]`含む） |
| `scripts/rules.gd` | F1・キャンペーン設定（`data/campaigns/week7.json`）の読み取り口（2026-09-28追記）。システム整理Aで`bill`／`bill_amount`／`bills_for_scene`を追加。4-9で`repair_fund`／`bills_total_on`を追加 |
| `scripts/day_planner.gd` | F2・`GameState.today_plan`の構築（2026-09-28追記） |
| `scripts/sale_rule.gd` | F3・提供前チェック（味/トッピング/濃さ0/杯数不足。2026-09-28追記） |
| `scripts/judge.gd` | F3・判定v2（一致数・favorite・減点。2026-09-28追記） |
| `scripts/ledger.gd` | F4・支出・売上の記録と集計（2026-09-28追記）。3-7で`usable_cash()`追加 |
| `scripts/forecast.gd` | 朝の一画面（SNSタブの客足予報）の集計。3-7実装・2026-10-11追記 |
| `scripts/morning_save.gd` | F7・朝の封筒（capture／is_valid／apply）と1枠セーブのファイル入出力。4-1実装・2026-10-11追記。4-2で版2・`day_records`の型検査。4-4aで版3・枠の`regular_id`／`episode_id`の型検査。4-4b-1で版4。4-4b-2で版5・枠の`today_request`の型検査。4-7①で版6・`saved_recipes`の型検査 |
| `scripts/result.gd` | 結果の集計と目標判定（`regular_stats`／`summarize`／`judge_goals`／`format_*`）。4-2実装・2026-10-11追記 |
| `tests/result_test.gd`・`tests/result_flow_test.gd` | 集計・目標判定・累計の保存（4-2コミット①）／最終日の流れ・結果画面の選択肢（50件。4-2コミット②）。2026-10-11追記 |
| `tests/save_state_test.gd`・`tests/save_file_test.gd` | 朝の保存・再挑戦（66件）／1枠セーブのファイル入出力（50件）。4-1実装・2026-10-11追記 |
| `tests/shop_row_split_test.gd` | 市場の店の商品の行分け（34件）。2026-10-11追記 |
| `data/schedules/week7_regulars.json` | 常連の固定日程（21枠）。4-3実装・2026-10-12追記 |
| `data/schedules/mob_rules.json` | モブの抽選ルール（既定＋日別の上書き）。4-3実装・2026-10-12追記 |
| `tests/regular_schedule_test.gd` | 固定日程の21枠・互換層・`customer_schedule`の確認。4-3実装・2026-10-12追記 |
| `data/episodes/<客>/<客>_<連番>.json` | 来店場面（21ファイル）。4-4a実装・2026-10-17追記 |
| `tests/episode_data_test.gd`・`tests/episode_flow_test.gd` | 場面データ・fixture照合（`tests/fixtures/customer_events_4_3.json`）／DayPlanの枠・場面の引き方・版3。4-4a実装・2026-10-17追記 |
| `scripts/customer_memory.gd` | 来店記録（F5）の書き手（`arrive`／`record_serve`／`last_visit`／`set_fact`など）。4-4b-1実装・2026-10-17追記 |
| `tests/customer_memory_test.gd` | 来店記録・好物の既知状態・保存の往復・知った順。4-4b-1実装・2026-10-17追記 |
| `scripts/episode_selector.gd` | 場面の選び方（`select`／`satisfies`。`requires`の`facts`・`not_seen`）。4-4b-2実装・2026-10-17追記 |
| `tests/episode_select_test.gd`・`tests/effective_order_test.gd`・`tests/order_card_callback_test.gd` | 選び方・今日の頼みの保存／実効注文（判定・予報は基本注文）／前回の2行・注文カード・聞き直し。4-4b-2実装・2026-10-17追記 |
| `scripts/balance_log.gd` | 日次ログ（`user://balance_log.jsonl`）の書き出しと`run_id`・`attempt`。システム整理A・2026-10-17追記 |
| `tests/display_name_test.gd`・`tests/balance_log_retry_test.gd`・`tests/market_talk_test.gd`・`tests/bill_scene_test.gd`・`tests/demand_route_test.gd` | 表示名／再挑戦の`run_id`・`attempt`／`market_talk`（`tests/fixtures/prep_events_system_a.json`と照合）／`bills[].scene`の場所代／需要経路。システム整理A・2026-10-17追記 |
| `tests/scene_keys_test.gd`・`tests/after_serve_test.gd`・`tests/choice_test.gd`・`tests/scene_facts_test.gd` | 場面の新キーの読み口と検査／提供後の列・UNSERVED・閉店退店／選択・締めの差分／`sets_facts`・`request_honored`・保存の往復と旧形式。システム整理C・2026-10-17追記 |
| `scripts/news.gd` | 日別ニュース・共通イベントと必須情報9項目のカタログ（読み口・検証・朝のTEXT・ニュースタブ本文）。システム整理D・2026-10-17追記。**UI準備C③でDMを`scripts/dm.gd`へ移した**（`News.day_entry`はニュースとイベントだけ返す） |
| `data/news/week7.json` | 日別ニュース・共通イベントと必須情報のカタログ（文面は仮案。`provisional`）。システム整理D・2026-10-17追記。UI準備Cで`dm`欄を削除し、Day3の見出しを差し替え |
| `tests/news_data_test.gd`・`tests/news_morning_test.gd`・`tests/common_event_test.gd` | 担保の検証・未知idの弾き／朝のニュースとニュースタブ／共通イベント・取り戻し・二重再生なし・数値不変・ハーネスの読み飛ばし。システム整理D・2026-10-17追記 |
| `tests/multi_cup_test.gd` | 複数杯の場面（`cups`）の読み口・検証・Event列・記録（`customer_events_4_3.json`）との厳密な一致・1杯の場面だけの機能が出ないこと。システム整理E・2026-10-18追記 |
| `scripts/recipe_book.gd`・`data/recipes/names.json` | 保存レシピの検証・保存・「いつもの」の引き当て・適用前の在庫検査・名前の候補（データ）。4-7①・2026-10-18追記 |
| `scripts/talk_log.gd` | 会話ログ（実行時のみ・今日の分・300行）と注文の要約（全日分）。4-7②・2026-10-18追記 |
| `scripts/read_state.gd` | 既読の記録（`user://read_state.json`。朝の保存の外）。4-7③・2026-10-18追記 |
| `tests/recipe_test.gd`・`tests/talk_log_test.gd`・`tests/read_state_test.gd` | レシピ保存・「いつもの」・適用の同一性・30%短縮・版6／ログの二重記録なし・乱数不変・注文の要約／既読の永続・スキップの同一性と停止条件。4-7・2026-10-18追記 |
| `scripts/repair_fund.gd` | 修繕基金（対象ごとの累計・1晩の上限・安全上限・積む処理）。設定は`week7.json`の`repair_fund`。4-9①、4-9④で対象方式に見直し・2026-10-18追記 |
| `tests/repair_fund_test.gd`・`tests/repair_fund_ui_test.gd` | 対象ごとの累計・1晩の上限・安全上限・拒否・目標判定の不変・保存・機能オフ・ゲームオーバーにならないこと／積み立て行・積む先の選択・状態の文・サマリー・結果・STATE VIEWER。4-9・4-9④で更新・2026-10-18追記 |
| `planning/playtest_2026_10_11/summarize_fund.mjs`・`summarize_fund_v2.mjs`・`PLAYTHROUGH_RESULTS_FUND.md`・`PLAYTHROUGH_RESULTS_FUND_V2.md`・`playthrough_*_fund*.json` | 基金の自動試遊の集計・結果（見直し前／見直し後）。4-9③④・2026-10-18追記 |
| `tests/fixtures/episodes/<客>/*.json` | 4-4b-2のテスト用の場面データ（`requires`・`order`・`callback`入り。`ScheduleData.episodes_dir`で差し替えて読む） |
| `data/campaigns/week7.json` | F1・7日版の経済数値・徴収・Day1上書き等の設定（2026-09-28追記） |
| `data/kits/day1_kit.json` | 初日セットの内訳（合計¥210。3-5実装・2026-10-01追記） |
| `scripts/play_session.gd` | `PlaySession`（Node）。画面の操作と問いの入口。`FlowController`を子に持つ。UI準備A・2026-10-24追記。UI準備Cで`log_unserved`／`unserved_display`／`phone_dm`／`dm_unread_count`／`mark_dms_read`を追加。使い方は`planning/PLAY_SESSION_API_2026_10_24.md` |
| `scenes/game_root.tscn`・`scenes/ui/*.tscn`・`scripts/ui/*.gd` | 本番UIの骨組み（メインシーン・左側・右の枠・全面の画面）。UI準備B・2026-10-24追記。`scripts/ui/ui_labels.gd`は表示名・短縮名・客足の言葉など（`data/ui/ui_labels.json`を読む）、`ui_parts.gd`は共通の部品（足りなかった杯数の文など）、`shop_tally.gd`は市場の「この店で買った」の集計 |
| `resources/ui_theme.tres`・`scripts/ui/ui_palette.gd`・`assets/fonts/` | Theme・配色12色・Noto Sans JP（OFL）。UI準備B |
| `tools/build_ui_scenes.gd`・`tools/ui_screens_B.gd`・`tools/ui_screens_C.gd` | 画面シーンの初回生成（再実行すると手の調整が消える）／スクリーンショットの撮影（`planning/ui_screens_B/`13枚・`planning/ui_screens_C/`20枚）。UI準備B・C |
| `scripts/dm.gd`・`data/dm/week7.json` | DM（SNSタブ）の読み口と条件の評価・データ（文面は仮）。`Rules.dm()`が読む。UI準備C③・2026-10-25追記。来店予告（`previews`）はUI準備E |
| `data/ui/ui_labels.json` | 画面の表示名・短縮名・店の品揃え・客足の言葉（`demand_words`）。UI準備B・C |
| `tests/ui_left_side_test.gd`・`ui_panes_test.gd`・`ui_kaiten_test.gd`・`ui_close_full_test.gd`・`ui_e2e_test.gd`・`ui_autoplay.gd` | 左側／右の枠／開店の操作エリア／閉店と全面の画面／UIだけでDay1の朝から最終日まで通す試験（台本は`ui_autoplay.gd`）。UI準備B・C |
| `tests/play_session_*_test.gd` | `PlaySession`の問いと操作（開店・市場・閉店・鍋・スマホ・朝・見え方）。UI準備A〜C |
| `tests/unserved_breakdown_test.gd`・`tests/dm_test.gd`・`tests/pot_adjust_test.gd` | 足りなかった杯数の内訳（素材・鍋・断った）／DMのデータ・条件・向き／ADJUST中も鍋を触れること（SERVE中は触れない）。UI準備C・2026-10-25追記 |
| `planning/playtest_2026_10_11/playthroughs.gd`（引数`[6]`info）・`summarize_v3.mjs`・`PLAYTHROUGH_RESULTS_V3.md`・`playthrough_results_regulars_v3*.json` | 予報を使わない自動試遊（v3）のハーネス・集計・結果。`playthrough_results_regulars_v2.json`は予報あり（v2）の基準で、上書きしていない。UI準備C⑤・2026-10-25追記 |

※ Graybox（graybox_open）は STEP 17.5 の検証後に削除した。
具材が増えて計器盤で操作しきれなくなった段階で作り直す。

---

## 9. まだ無いもの（今後のテーマ）

### A. 夜の核の残り
- **修繕基金は手順4-9で実装済み**（MVP版。CLOSEの任意の積み立てで、看板・棚・雨よけ・名義の対象ごとに値段があり、修繕済みの対象が表示に出る。
  1晩の上限30・安全上限あり。仮UI。§6「修繕基金」参照）
- **メニュー・レシピ**（見られるようにする。指針であって縛りではない）：
  **スマホUIのシェル（レシピ・ニュース・SNS・ログの4タブ・開閉・常時アクセス）は実装済み**
  （§5「スマホUI（シェルのみ・実装済み）」参照）。**レシピの保存と「いつもの」は手順4-7で実装済み**
  （レシピタブは保存レシピと客ごとの「いつもの」を出す。仮UI。本番UIはフェーズ6）
- **廃棄は実装済み**（ADJUST中に`[廃棄する]`で椀を引っ込める。鍋・具材が
  無駄になり同じ客に作り直す。§5「廃棄」参照）
- **在庫の消費は実装済み**（具材を使うと減る／市場6店で買い足せる。§6参照）。
  favorite をレア食材にする、は未実装（今のfavoriteは初期在庫の中から仮割当）
- **具材の腐敗は実装済み**（生鮮6品目が2日で新鮮→3日目で傷む（-1段階）→
  4日目で自動破棄。§5「具材の腐敗」参照）。品目ごとの速度差・傷みからの
  回復は未実装
- 味を2つ重ねるときの成立表（**7日版では保留と決定**。§11参照）

### B. 鍋（7.6 の管理要素）
- **残量・濃さ・水/だしを足す操作・時間帯（宵の口・夜半・明け方）・
  尽きたときの対応（自動閉店／プレイヤーの選択）はすべて実装済み**（§5参照。
  2026-09-26改訂：ベース→濃縮だしへ置き換え）
- **濃縮だしを市場で買い足す操作は実装済み**（食肉仲卸・¥16・1周1回の制限や期限は
  無く毎日何度でも購入可。§5「濃縮だしの購入」参照）
- **評判 → 翌日のモブ人数、は実装済み**（§5「評判→モブ人数」参照）。
  「モブが増える→鍋の配分が厳しくなる」という連鎖自体は、鍋・具材の在庫が
  既に実装済みなので自然に機能する（追加の配線は不要）

### C. データの外部化（Day1〜7の骨格まで実装済み・2026-09-22／会話本文は未着手）
日程・客・モブのデータをコードからJSONへ切り出し、**Day1〜7すべてで
枠組みが動く状態**になっている（`.gd`ファイルの役割分担・本数は変えていない。
`day1_events.gd`は「JSONを読んでEvent列に組み立てる処理」のままで、中身の
データ部分だけを外に出した）。**ただし客・モブの会話本文は意図的にすべて
プレースホルダーのまま**（下記「会話本文について」参照。鍋・水・具材の
入手量や価格、客の嗜好といった経営数値の調整を先に優先する方針のため）。

```
data/
  day_schedule.json          ← 【4-3で削除】日ごとの枠構成（旧モデル。現行は下の schedules/）
  schedules/
    week7_regulars.json      ← 常連の固定日程（21枠。4-3）
    mob_rules.json           ← モブの抽選ルール（既定＋日別の上書き。4-3）
  customers/
    granny.json / thug.json / officer.json / hooker.json / streamer.json
      ← 客ごとの会話・要求タグ・favorite（登場日ぶんはプレースホルダーで埋め済み）
    delivery_man.json         ← 最小限（favorite/wanted_tags/is_mobのみ。
                                 Day1の3杯の会話は場面データ delivery_man_01.json の cups。システム整理E）
  mobs/
    dock_workers.json / security_guard.json / inn_clerk.json /
    street_cleaners.json / general_store_clerk.json / market_porter.json /
    long_haul_driver.json     ← モブ7種すべて実装済み（中身はプレースホルダー）
scripts/schedule_data.gd       ← 上記JSONの読み込み＋キャッシュ専用（class_name ScheduleData）
```

**【4-3で廃止。以下は4-3以前の記述。現行は「常連の固定日程とモブ規則（4-3）」節】day_schedule.jsonのモデル（Day1〜7すべて実装済み）**：各日は「宵の口・夜半・
明け方」のうち客がいる枠だけを持つ配列。各枠は「メイン客1人（＋モブ、あれば）」
の並び。メインは次のどちらかだけを持つ（特別な"debut"/"forced_tail"フィールド
は無い。固定／抽選の2値だけで初登場日の客もDay7明け方の老婆も同じ形で表現
できる）：
- **`main`（固定）**：客idを直接指定
- **`main_pool`（抽選プール）**：候補idの配列から`_pick_main()`が毎回1人を抽選。
  **その日まだ選ばれていない客だけを対象にする**（同日内の重複を禁止）。
  候補が尽きた場合（プール全員が選ばれ済み）は除外を無視して選び直す
  （クラッシュしない安全策）

実際の並び（SEVEN_DAY_OUTLINE.md §10・§13-8の設計どおり）：
| 日 | 宵の口 | 夜半 | 明け方 |
|---|---|---|---|
| 1 | 配達員固定＋モブ固定(dock_workers) | チンピラ固定＋モブ抽選 | 老婆固定・モブなし |
| 2 | 新人警官固定＋モブ抽選 | 抽選(老婆/チンピラ/配達員)＋モブ抽選 | 同上 |
| 3 | 娼婦固定＋モブ抽選 | 抽選(+新人警官)＋モブ抽選 | 同上 |
| 4 | 配信者固定＋モブ抽選 | 抽選(+娼婦)＋モブ抽選 | 同上 |
| 5・6 | 抽選(6人プール)＋モブ抽選 | 同上 | 同上 |
| 7 | 抽選(老婆を除く5人)＋モブ抽選 | 同上 | 老婆固定・モブなし |

**モブは`mob: true`（型固定・`dock_workers`。Day1宵の口のみ）と
`mob: {"pool": [...]}`（型は枠ごとに独立抽選）の2種類**。
`{"pool":[...]}`の枠は今はどの日も7種全部を対象にしている（どの日にどの種類が
ふさわしいかは今後の調整項目。SEVEN_DAY_OUTLINE.md §13-8参照）。

**人数の決め方は2026-09-25改訂でDay1とDay2以降が分岐した**（詳細は上記「客数の決め方」参照）：
- **Day1、またはデバッグの`[モブ人数]`ボタンで0以上に上書きした場合**：旧来どおり枠ごとに
  独立して`_pick_mob(slot, debug_count)`を呼ぶ。型はプールから`_pick_mob_type()`が抽選
  （同日内の重複除外なし）。人数は上書き値、無指定なら`GameState.DAY1_MOB_COUNT`（=4）固定
  （Day1はこの経路のみを通るため、結果的に今までと変わらない）。上書き時はその日の全モブ枠の
  人数が一律その値になる（型は引き続きばらつく）。
- **Day2以降・自動（デバッグ上書きなし）の場合**：枠ごとの独立抽選はしない。まず
  `GameState.total_demand_today()`でその夜の総需要杯数を決め、各枠の名前あり客の杯数
  （`_customer_total_servings()`が`customer_events()`のREACT杯数を実測）を差し引いた残り
  （`mob_cups`）を`_plan_mob_groups()`が4人以下の組へ分割し、固定優先順位
  （`_GROUP_SLOT_PRIORITY = ["夜半","宵の口","明け方","宵の口"]`、対象枠がモブ非対応
  またはslotが存在しなければ`_GROUP_SLOT_FALLBACK`="夜半"）で各枠へ配る。1組＝1体の
  モブインスタンスとして扱い、型は組ごとに`_pick_mob_type(slot)`で個別抽選する
  （＝1つの枠に複数組＝複数の顧客IDが立つこともある）。

枠ごとに抽選で決まった（モブの型・人数）は、その日だけ有効なインスタンスID
（`Day1Events._mob_instances`）で保持し、後から`customer_events()`が
呼ばれた時点で引く。`OpenController`・`event_runner.gd`・`flow_controller.gd`
は無改修（客リストが相変わらず文字列の配列であるため影響しない）。

**【4-4aで廃止。以下は4-4a以前の記述。現行は「客データの分割と場面ID（4-4a）」節】customers/\*.jsonのモデル**：`favorite`/`is_mob`はトップレベル（日をまたいで
不変）、`greet`/`wanted_tags`/`reactions`/`servings`は`days.<day番号>`の下に
置く。**該当日のデータが無い場合は客データ自身も独立して`days["1"]`へ
フォールバックする**（day_schedule.json側のフォールバックとは別の、客データ
側だけの仕組み）。

**会話本文について（2026-09-22時点の方針）**：娘婦・動画配信者・新人警官の
Day3以降ぶん・モブ7種の中身は、いずれも「客名＋要求タグ」程度の最小限の
プレースホルダー文字列（例：`"娼婦（HOT/POWER）"`）で、本番の会話は**まだ
1行も書いていない**。**鍋・水・具材の入手量や価格、客ごとの嗜好といった
経営ゲーム部分の数値調整を先に優先する方針**のため、会話本文の執筆は
いったん保留にしている。骨組み（日程・抽選・フォールバック）は7日間フルで
検証済みなので、経営数値が固まった後にプレースホルダー部分を本番の会話へ
差し替えるだけで進められる。

**headlessテスト基盤（実装済み）**：`tests/`ディレクトリをリポジトリに
コミットし、`godot --headless --path . --script res://tests/run_tests.gd`で
再実行できる（`tests/test_check.gd`が共通の`check()`ヘルパー、
`tests/schedule_test.gd`がスケジュール・モブ抽選周りを検証。今までの
「Godot実機での確認」に加えて、コミット済みの自動検証が持てるようになった
最初の機能）。

詳しい経緯・客/モブの中身は SEVEN_DAY_OUTLINE.md §13-8・§10 を参照。

### D. 本番UI（見た目・一番最後）
- **骨組みは UI準備B で実装済み**（§6「本番UI（UI準備A・B）」）。残りは本番の絵・音・開始／設定／終了（フェーズ6）
- 絵・セリフ表示・屋台画面
- 選択肢は調味料と具材で表示を分ける（種類が増えると1列では探しにくい）
- 客と鍋を常時表示し、注文時に鍋の領域が椀の画面に切り替わる（DESIGN.md 7.6）

### その他
- rumors は状態として予約済み・未使用
- **市場での買い物は6店（永順青果・食肉仲卸の追加購入・乾物調味料・豆腐麺・
  海鮮・端材半端物）すべて実装済み**（day_count>=2で解禁。§6「市場での購入」
  各節参照）。水場はボタンとしては廃止し（2026-09-26改訂）、水道代の自動精算
  だけが残っている（§6「PREP」参照）
- 7日分のシナリオ（現状は Day1 の3人＋モブ1組、Day2は新人警官＋モブ1組が
  実装済み・仮文言。Day3以降はまだDay1のスケジュールを再利用しているだけで
  中身は無い）
- 提供後の会話（現状は一口目の感想で終わり、一日が短く感じる）
- セーブ（**朝から再開する1枠セーブをフェーズ4で作ると決定**。§11参照）→【4-1で実装済み・2026-10-11。§6「朝の保存と1枠セーブ（4-1）」参照。調理中・会話途中は保存しない】
- Day1 の閉店時所持金は現状 **705**（2026-09-26改訂：差分表最後の3項目
  〈売価50→45・初期現金300→600〉により450→705）。PRICING_SPEC.md記載の430は、
  売価50・初期現金340・場所代150（週払い）という`BALANCE_REDESIGN_PLAN.md`
  移行前の旧い経済モデルの数値であり、現行の45/600/90/50/80の体系とは
  前提から異なるため、単純比較はできない（PRICING_SPEC.md自体は今回更新
  対象外）。
- **お金が無い日のベース代用（クズ野菜）は実装済み**（§6「クズ野菜ベース」参照）。
- **ゲームオーバーは実装済み**（§6「ゲームオーバー」参照）：水道代・場所代が
  払えないと`GameState.try_pay()`が`false`を返し、`Phase.GAME_OVER`へ遷移する。
  `[次のPhase]`が効かなくなり、Godot再起動まで復帰しない（セーブ未実装のため。【4-1で仮ボタンによる再挑戦を追加】）。
  **徴収日は`day_count == 1`のみで変更しないと決定した**ため、7日版に戻しても
  通常プレイでゲームオーバーが発生しうるのはDay1のみ（意図した割り切り。§11参照）
- **終了日は実装済み**（§6「終了日」参照）：`FINAL_DAY`=7日（本番版。体験版の
  3日から変更済み・Godot実機で7日通しプレイを確認済み。§11参照）で終了、
  CLOSE後に「（終了）」テキストが出て、`GameState.reset_for_new_game()`が
  状態変数12個すべてを初期化して1日目に戻す

---

## 10. 設計上の確定事項（変更しない）

- 状態は GameState（日またぎの事実）と EventRunner（使い捨て）の二層。status は EventRunner 側
- 上位フェーズは一方向。戻らない
- OPEN は別階層。客ループは下位に隔離
- 全イベントは共通の Event 型。Day1 と通常日で別コードを書かない
- Event はデータ、処理は受け側。処理をデータに埋め込まない
- 状態変更は GameState の入口（apply_money 等）を必ず通す
- 全客で共有するのは鍋（soup）のbase_id / base_tags。客ごとの味付けは
  接客中のBowl.additionsに持たせ、鍋へ混ぜない。soupはNEXT_DAYでリセット
- 本番UIより先に開発用 State Viewer。作りながら確認する

---

## 11. 次の開発方針

DESIGN.md 9.5「ビルド順・第2フェーズ」の縦切りは **STEP 17.6 まで完了**。
その後、DESIGN.md 7.6（鍋とモブ客）の実装に着手している。

```
[済] 最小データ形を決める（Soup / Bowl / Ingredient / Customer）
[済] PREPで共有鍋を作る（SET_SOUP）
[済] 辛味を入れる一操作 → 二択 → 5つの味から1つ
[済] 3枠で味と具を選ぶ（選ぶと進むを分離・上限3・重複可）
[済] 一致数による段階評価（BAD / OK / GOOD）
[済] favorite でクリティカル（GREAT）
[済] モブ客（dock_workers）と servings（1回の接客で複数杯）
[済] 配達員を1杯ずつ3回接客する形に変更（同じ客のまま会話の合間に提供。
     ADJUSTのnew_bowl・REACTのjudge/aggregate・退店時に評判と提供記録を1回だけ反映。
     §5「1杯ずつ接客する客」）
[済] Day2に新人警官（officer）を初登場させる（昼の市場の会話＋夜の通常接客。
     customer_schedule/prep_eventsをday_count==2で分岐。Day1・Day3以降の出力は
     不変であることを確認済み。§5「Day2の客：新人警官」）
[済] 予備ベース購入（食肉仲卸・¥80で+10単位・1周1回・購入分だけ経過日数で期限あり。
     add_base()は元の分を先に消費し購入分を最後に残す。§5「予備ベースの購入」）
[済] 腐る具材の鮮度選択（stocked_dayの品目1つ=経過日数1つを、購入日ごとの
     ロット（perishable_batches）に置き換え。ADJUSTは「傷んでいない/傷んだ」の
     最大2ボタンに分かれ、傷んでいない側は古いロットから自動消費、不足分は
     もう一方のバケツで自動的に補う。判定は押したボタンの種類だけで決まる。
     下の「具材の腐敗」の項にあった「個別ロット追跡はしない」は本項で置き換え
     済み。§5「具材の腐敗」）
[済] スマホUI（シェルのみ）：常時表示の[スマホ]ボタンで、鍋モード・市場・ADJUSTの
     どこからでも開ける3つ目の入れ子モード（_phone_mode）。_pot_mode/_market_shopより
     最優先で判定するので鍋・市場側は無改修のまま、閉じれば自動的に元の状態へ戻る。
     開いている間は会話・調理・フェーズ進行を完全に止める。レシピ／ニュース／SNSの
     3タブは今回すべてプレースホルダー（実データは別タスク）。§5「スマホUI
     （シェルのみ・実装済み）」）
[済] 評判の仮実装（判定に応じて増減）
[済] 鍋の残量（提供で減る）
[済] 時間帯（宵の口・夜半・明け方）
[済] 濃さと鍋の操作（水・ベース。[鍋を見る]で会話を止めて触る）
[済] 濃さが評価に影響する（favoriteの後に適用、取り返せない）
[済] 鍋が尽きたときの自動閉店（名前あり客が全員済み かつ 水も無い）
[済] 鍋が尽きたときのプレイヤーの選択（片方だけ成立のとき、作り直すか閉店か）
[済] 在庫を数量辞書に変更（{ id: 個数 }。市場での複数購入に対応）
[済] 市場の骨格（Day1）：MARKET Event、7店舗の選択肢、食肉仲卸は自動、
     水場だけ押せる、[市場を出る]専用ボタン、未訪問なら自動で水場に寄る
[済] 市場の日ごとの解禁（day_count >= 2 で食肉仲卸・水場以外の5店を一斉解禁。
     Day2の中身は作らず仕組みのみ確認）
[済] 永順青果（青果）での実購入：冬瓜/苦瓜、¥20/¥13、1回5杯分、
     所持金不足でボタン無効化、規格外野菜は対象外（ベース代用品のため除外）
[済] ADJUSTを在庫から動的生成（GameState.inventoryを毎回読む。
     ハードコード7種固定リストを廃止。在庫切れでもボタンが無効化される）
[済] initial_inventory()：調味料10個・具材4個で確定（具材は当初2個の
     合意から4個へ意図的に変更）。pickled_lime/bitter_melonは初期在庫から除外
[済] 廃棄（ADJUST中に[廃棄する]。鍋残量servings分＋消費済み具材が無駄になり、
     同じ客のADJUSTに戻って作り直せる。discarded(廃棄数)を計器盤に表示）
[済] 具材消費のservings連動（1個選ぶとservings分まとめて減る）＋
     端数での無効化（残数がservings未満ならボタングレーアウト）
[済] 評判→モブ人数（Day1は4人固定、Day2以降は評判のしきい値テーブルで
     0〜8人をランダム抽選。0人の日はdock_workers自体が出ない）
[済] 具材の腐敗（生鮮6品目が2日で新鮮→3日目で傷む(-1段階)→4日目で自動破棄。
     在庫は品目単位の簡易管理・個別ロット追跡はしない）
[済] クズ野菜ベース（所持金がBASE_PRICE未満の日は食肉仲卸の代わりに端材屋へ。
     代金なし・濃さ1スタート。デバッグ用の[所持金 -50/+50]ボタンも追加）
[済]【4-2で流れ変更】終了日（最終日CLOSEに「（終了）」テキスト、NEXT_DAYでreset_for_new_game()
     により状態変数14個すべてを初期化して1日目に戻る）
[済] 7日版に戻す（FINAL_DAY を3→7に変更。徴収日はday_count==1のまま据え置き
     ＝意図した割り切り。Godot実機で7日通しプレイを確認済み）
[済] ゲームオーバー（水道代・場所代が払えないとtry_pay()がfalseを返し
     Phase.GAME_OVERへ。[次のPhase]が効かなくなりGodot再起動まで復帰しない。
     ベース代はクズ野菜が必ず賄うので通常プレイでは対象外。Godot実機で確認済み）
[済] 市場の残り5店（食肉仲卸の追加購入・乾物調味料・豆腐麺・海鮮・端材半端物）
     での実購入。永順青果と完全共通のパターンで横展開（purchase処理・描画は
     無改修）。新規具材7品目を追加（うち5品目が腐る）。初期在庫の腐る5品目の
     補充手段が全て揃った。Godot実機で確認済み）
```

**DESIGN.md 7.6（鍋とモブ客）は一通り実装が完了**。
**DESIGN.md 7.7（市場）は「買って使う」経路が市場6店（永順青果・食肉仲卸の
追加購入・乾物調味料・豆腐麺・海鮮・端材半端物）すべてで端から端まで通った**
（購入 → 在庫反映 → ADJUSTで使用 → 消費で在庫が減る、を確認済み）。
水場の追加購入のみ未実装。数値は仮のまま（触って調整する前提）。

**ゲームを閉じるための仕様も実装が完了**（体験版として3日版でリリースする方針から
逆算）。クズ野菜ベース・終了日・ゲームオーバーの3つとも実装済み（§6参照）。
ただし3日版で通しプレイした結果、下記3点の見直しを決め、すべて実装・確認済み。

### 今回決めた3点（実装・確認済み）

3日版を通しで動かして分かった課題を検討し、以下の方針に決めた。

1. **7日版に戻す → 実装済み・Godot実機で7日通しプレイ確認済み**：
   `FINAL_DAY` を3→7に変更した（§2参照）。
   - **徴収日は増やさないことも確定**：`is_collection_day()` は
     `day_count == 1` のまま変更しない。7日に伸ばしても水道代・場所代による
     ゲームオーバーはDay1以外では発生しない。
   - 検討過程：最終日（当初案ではDay8）にも徴収日を足す案（`[1, 8]`）も
     検討したが、①元々`FINAL_DAY`のコメントが「本番=7日版」としていたのに
     日数を増やす動機が薄いこと、②最終日に徴収を重ねると「（終了）」の
     演出に辿り着く前にゲームオーバーで終わる可能性があり、有終の美を
     損ねること、の2点から見送った。ゲームオーバー自体はデバッグ用
     `[所持金]`ボタンで動作確認済みのため、通常プレイで実際に踏むかどうかは
     問わないことにした（意図した割り切り）。
2. **残り4店＋張記肉類加工（食肉仲卸）追加購入の実購入を実装する
   （スコープを拡大・決定）→ 実装済み・Godot実機確認済み**：
   永順青果以外でも生鮮具材を補充できるようになった。
   - 当初「残り4店」（乾物調味料・豆腐麺・海鮮・端材半端物）としていたが、
     モツ（`offal`）の唯一の資源経路である張記肉類加工（食肉仲卸）が対象外だと
     老婆（granny）のfavoriteが恒久的に出せなくなるため、食肉仲卸での追加購入も
     スコープに含めた。
   - 海鮮（TREAT・新軸）と乾燥きくらげ・軟骨・すじ肉（BITE・新軸）も、
     現状どの客も欲しがらないがフルで実装した（将来のシナリオ待ち）。
   - 商品ラインナップ・価格・腐敗区分・実装の詳細と既知の食い違い
     （PRICING_SPEC.mdとの価格差など）は**§6「市場での購入 — 残り5店」参照**。
3. **終わり方の結果表示は不要と判断**：所持金・評判の総括表示やエンディング
   分岐は、システム仕様には含めない。必要になれば演出側の検討として
   別途扱う（§9「本番UI」領域）。

### 7日版完成までのロードマップ（採用・2026-09-20）

他AIによる静的診断（main / 2e3dc47）と、その推奨ロードマップ
（`night_broth_7day_roadmap.md`）を検討し、フェーズ0〜6の順で進めることに決めた。
大規模なリファクタリングはせず、既存の GameState／FlowController／EventRunner／
OpenController を維持する。

**7日版の完成条件**：デバッグ操作（次のPhase・Day+1・所持金操作）を使わずに、
日ごとに内容が異なる7日間を最後まで遊べる。朝から再開でき、7日目の終了後・
ゲームオーバー後に最初から遊び直せる。対象OSを1つに絞った配布用ビルドで確認する。

**フェーズ0で決めたルール**（実装中に判断が割れないよう固定する）：

| 項目 | 決定 | 実装時期 |
|---|---|---|
| 鍋の残量が注文杯数に足りないとき | 水を実際に足して必要杯数を満たしてから提供。足せなければ閉店（ベースは残量を増やせないと決定し直したため「水を」に限定。§5参照） | フェーズ1（**実装済み**） |
| 具なしの椀 | 常にBAD（調味料だけ・何も入れないの両方）。苦瓜は具に数えない | フェーズ1（**実装済み**） |
| 味を2つ重ねたときの成立表 | 7日版では保留。今のタグ一致式＋具なし判定で固定（DESIGN.mdの将来像との差として残す） | ― |
| セーブ | 朝から再開する1枠セーブ。調理中・会話途中は保存しない | フェーズ4 |
| 会話と調理の操作方式 | 今の「会話→調理→提供→会話」で進める。調理中も会話を進めたくなったらフェーズ3で1客だけ検証 | フェーズ3 |

維持する既存の決定：徴収日はDay1のみ／最終日は7日／価格・容量の見直しは全体ができてから
（フェーズ5）。

**【2026-09-26更新】** 上記から「結果総括・エンディング分岐は作らない」を外す。7日版MVPで**結果画面は作る**（`planning/DESIGN_MVP7_2026_09_26.md` 10.6）。エンディング分岐（本筋の真相を分岐させる仕組み）は引き続き作らない（Day7の締めの台詞差分のみ・10.5.7）。

**フェーズ一覧**：

| フェーズ | 内容 | 次へ進む条件 |
|---|---|---|
| 0 | ルールの明記・仕様書の古い記述の整理 | **済**（上の表と本書の整理） |
| 1 | 鍋・調理の不具合修正 | DebugPanelでDay1が通り、失敗操作でも詰まらない |
| 2 | 7日間の概要表・1客分の本番会話・レシピ閲覧・予備ベース購入 | 1客分の「聞く→考える→作る→反応→雑談」が成立 |
| 3 | 仮UIでDay1〜Day2を遊べるようにする（共用処理だけController化） | デバッグ操作なしでDay2閉店まで遊べる |
| 4 | 1枠セーブ・日別データの入口・7日分の会話 | 仮素材で内容の異なる7日間を完走できる |
| 5 | 7日通しでの数値・会話の調整 | 通常・失敗・再開の代表経路で終了まで進める |
| 6 | 本番素材・開始/設定/終了・書き出し | 配布用ビルドで開始・再開・完走・再挑戦ができる |

**フェーズ1の実装順**（1ステップ＝1回の依頼）：
1. **[済]** 空の鍋から抜け出せない問題を直す（§5の既知の不具合）
2. **[済]** 鍋不足を「補充してから提供」に統一する（ADJUST側で一次判定する形で実装。
   あわせてベースの効果を「濃さのみ＋1」に直した。REACT側の分岐は使われなくなったが
   安全網として残した＝簡略化はしていない。§5参照）
3. **[済]** 具なし判定を入れ、椀への追加が成功したときだけ在庫を減らす（§5参照。
   `Ingredients.is_topping()`／`OpenController.judge_bowl()`／
   `OpenController.add_to_bowl()` の戻り値化）
4. **[済]** SERVE〜REACTの間の鍋操作を止め、提供した椀の判定が後から変わらないように
   する（§5参照。`DebugPanel._is_awaiting_react()`を追加し、`[鍋を見る]`の無効化条件
   に足した）

**フェーズ1はこれで完了**（DebugPanelでDay1が通り、失敗操作でも詰まらない。フェーズ2へ）。

**フェーズ2の進捗**：
1. **[済]** 7日間の概要表（`SEVEN_DAY_OUTLINE.md`。構造4点を決定済み）
2. **[済]** 1客分の本番会話：Day1の配達員（阿強）。会話稿を1行1Eventで組み込み、
   同じ客へ3杯を1杯ずつ会話の合間に出す形にした（§5「1杯ずつ接客する客」。
   Godot実機で動作確認済み）
3. **[済]** 新人警官のDay2初登場：日別の客構成（`customer_schedule`/`prep_events`の
   `day_count`分岐）を最小実装し、昼の市場の会話＋夜の通常接客を組み込んだ
   （§5「Day2の客：新人警官」。Godot実機で動作確認済み）
4. **[済]** 予備ベース購入：食肉仲卸に「予備ベース(1袋)」（¥80・+10単位）を追加。
   1周1回・購入分だけ経過日数で期限あり（3日目に傷み表示・4日目に未使用分を
   自動破棄）・`add_base()`は元の分を先に消費（§5「予備ベースの購入」。
   headless検証・Godot実機で動作確認済み）
5. **[済]** スマホUI（シェルのみ）：常時表示の`[スマホ]`ボタンで、鍋モード・市場・
   ADJUSTのどこからでも開ける3つ目の入れ子モードを追加。開いている間は会話・調理・
   フェーズ進行を完全に止め、閉じると元の状態に自動復帰する。レシピ／ニュース／SNSの
   3タブは今回すべてプレースホルダー（§5「スマホUI（シェルのみ・実装済み）」。
   headless検証・Godot実機で動作確認済み）
6. 未着手：レシピ・ニュース・SNSの実データ（Day3以降の日別コンテンツ制作と
   合わせて実装予定。§9「A. 夜の核の残り」参照）
7. **[済]** 日別スケジュールの汎用化（データのJSON外部化・第1弾）：日程・客・モブの
   データを`data/day_schedule.json`・`data/customers/*.json`・
   `data/mobs/dock_workers.json`へ外部化し、`scripts/schedule_data.gd`
   （新規）経由で読む形にした。`customer_schedule()`/`_customer_flavor()`を
   固定客／抽選プール（同日内重複禁止）の汎用ロジックに書き換え、Day1・Day2の
   ハードコード分岐をこの仕組みに一本化。`tests/`（headlessテスト基盤・新規）を
   リポジトリにコミットし、既存の文言スナップショット比較で無変化を確認した上で
   Godot実機でも確認済み。
8. **[済]** Day2〜7の骨格をダミーデータで通しプレイ可能にし、モブ抽選を枠ごとに
   完全独立化（第2弾）：`data/day_schedule.json`にDay2〜7の全エントリを追加し、
   Day1フォールバックに頼らない実データへ切り替えた。新規客（娼婦・動画配信者）と
   モブ残り6種（夜勤警備員・安宿の夜勤受付・夜間清掃員・市場横の雑貨屋の夜番・
   市場の荷捌き人夫・長距離運転手）の`data/customers/*.json`・`data/mobs/*.json`を
   追加（会話本文はすべてプレースホルダー）。モブ抽選は「枠ごとに種類・人数を
   完全に独立して抽選する」方式（ユーザーの明示指定）に変更し、Day1夜半の
   モブ枠も含めて`Day1Events._mob_instances`（インスタンスID方式）で解決する形に
   統一した。`OpenController`/`event_runner.gd`/`flow_controller.gd`は無改修。
   デバッグ用の人数固定オーバーライドは全モブ枠の人数にのみ一律適用され、種類は
   引き続き毎回抽選される。Godot実機で7日間の通しプレイを確認済み。詳細は
   §9「C. データの外部化」参照。**会話本文の実データ化（新規客・モブ・警官の
   残り日数分）は、経営数値（鍋・水・具材の入手量や価格、客ごとの嗜好バランス）の
   調整を優先するため意図的に後回しにしている（2026-09-22時点の方針）**
9. **[済]** 日次ログの導入（`BALANCE_REDESIGN_PLAN.md`§8「①消費と鮮度の明確化・
   日次ログ」・経済数値/計算式は無変更）：`BALANCE_REDESIGN_PLAN.md`
   （しまさんのGodotプロジェクト直下・git管理外。経営バランス再設計プラン。
   現行実装との13項目の差分を含む。7日MVP用の
   正本）を独立監査した上で、その実装第一歩として、1日の終わりの状態をログに
   残す仕組みだけを追加した。既存の定数・計算式・評判テーブル・鍋の仕様は
   すべて現状のまま。
   - `FlowController`に`day_ending`シグナルを新設し、NEXT_DAY→WAKEへ折り返す
     瞬間、`reset_for_new_day()`/`reset_for_new_game()`（`served`等を消す）より
     **前**に発火する（最終日側の分岐でも発火する。既存の`phase_changed`は
     リセット後に発火するため今回の用途には使えないと判明し、新設した）。
   - `GameState.discard_spoiled_inventory()`の戻り値をidの配列から
     `{id: 破棄個数}`のDictionaryへ拡張（上記「状態変更の入口」参照）。
   - `day1_events.gd`に`ingredient_prices()`を新設。既存の`*_goods()`
     （6関数）から価格を集約するだけで数値は書き写さない
     （`reserve_base`は腐敗対象外のため除外）。廃棄額の概算
     （`price / INGREDIENT_SERVINGS_PER_PURCHASE × 破棄個数`）に使う。
   - `DebugPanel`が日次カウンタ（開店時の所持金/評判、計画杯数の先読み、
     水/ベース使用回数、早期閉店フラグ、判定結果ごとの杯数、廃棄品目）を
     保持し、`day_ending`受信時に`day / opening・closing_money / opening・
     closing_reputation / planned_cups / served_cups / unserved_cups /
     sale_total / quality_counts / spoiled_items / spoiled_value_approx /
     water_used / base_used / closed_early`を1日1行、コンソール
     （`BALANCE_LOG: `プレフィックス）と`user://balance_log.jsonl`
     （JSON Lines）へ出力する。
   - `tests/balance_log_test.gd`（新規）で配線を検証（廃棄個数の記録、価格表の
     網羅性、計画杯数の先読み、`quality_counts`と`served_cups`の整合、
     `day_ending`が日次リセットより前に発火することなど14項目）。headless
     テストに加え、Godot実機で1日分プレイしてログ出力を目視確認済み。
   - コミット：`13dfc89`。次回以降、この仕組みを使って
     `BALANCE_REDESIGN_PLAN.md`の残りの項目（②拒否と部分提供、③商品・
     固定日程・初回好物の開示、④仕込みと評判・予告、⑤7日通し確認）を
     1項目ずつ移行していく。
10. **[済]** 拒否と部分提供（`BALANCE_REDESIGN_PLAN.md`§8「②拒否と部分提供」・
    §6「団体を全員断らずに済むようにする」）：対象はモブ客（`is_mob:true`の団体
    オーダー）だけ。詳細は§5「団体客の人数調整（拒否と部分提供・実装済み）」を参照。
    要点は次の3つ。
    - 材料投入前（`[入力完了]`を押した時点）に、達成可能人数
      （`min(注文人数, 鍋残量, 選んだ具材のバケツ別在庫数)`）を「N人分を提供／
      注文を断る」の2択で提示し、確定するまで在庫・鍋・売上・評判は一切動かさない。
    - 全員分そろっている場合でも「断る」の選択肢は必ず残す（自動で全員提供にしない）。
      新鮮・傷みの2バケツは合算しない。別レシピでの追加提供はしない。
    - `GameState.discard_spoiled_inventory()`と同じ方針で、`record_served()`に
      `ordered_servings`/`unserved_servings`/`declined`を追加（既存の`servings`は
      実際に提供した人数のまま。①の日次ログは無改修で正しく動く）。名前あり客・
      配達員（servings常に1）のコードパスは数学的に無変化。
    - モブ客は「鍋が尽きたときの対応」（既存の保留・自動閉店フロー）の対象外になった
      （名前あり客・配達員には無変更のまま適用）。
    - `tests/group_partial_serve_test.gd`（新規24項目）＋Godot実機で確認済み。
      コミット：`c19ed80`。
    - **将来検討（今回は対象外・`BALANCE_REDESIGN_PLAN.md`§6にメモのみ）**：
      1つの団体を複数レシピ・複数の椀に分けて全員へ届ける（4人→3+1等）は、
      実プレイで気になるようなら③〜⑤の実装後か21日版検討時に再検討する。
      **→2026-09-26に実装した（最大2レシピに限定。下記の項目18を参照）。**
11. **[済]** 初回好物の開示（`BALANCE_REDESIGN_PLAN.md`§8「③商品・固定日程・初回
    好物の開示」のうち初回好物の開示だけ）：対象は名前あり客だけ。商品の購入単位・
    客数の決め方（評判式含む）は今回対象外（③は3つの異なる変更を束ねており、値の
    移行は1項目ずつという§8の方針に合わせて分割した）。詳細は§4「初回好物の開示
    （実装済み）」を参照。要点は次の3つ。
    - 名前あり客と初めて会う来店では、好物を入れてもGREATにならない（基本要求の
      一致数どおりの評価に留まる）。退店時に「知った」扱いになり、2回目以降の
      来店からは好物でGREATになる。
    - 配達員（1杯ずつ3回接客）は1杯目の判定直後ではなく、3杯すべて終えて退店する
      瞬間（`_flush_visit_tally()`）に1回だけ確定する（1杯目の直後に確定させると
      同じ来店の2杯目から好物が効いてしまうため。実装レビューで見つかった論点）。
    - 【4-4b-1で`customer_memory[id].favorite_known`に置き換え】`GameState.known_favorites`は日をまたいで持ち越し、新しい周回
      （`reset_for_new_game()`）でリセットする。
    - `tests/first_favorite_test.gd`（新規15項目）＋Godot実機のDay1本編で確認済み。
      コミット：`8867c84`。2回目以降の来店で実際にGREATになる確認は、Day2以降の
      再来店タイミングで引き続きGodot実機で確認予定。
12. **[済]** 具材の購入単位（差分表13項目め。`BALANCE_REDESIGN_PLAN.md`§3「食材価格」）：
    項目11で対象外にした「商品」の部分に着手した回。次の②評判の更新＋③客数の決め方
    （差分表4・5項目め）とは完全に別ラウンドで、評判・客数・仕込み量・鍋容量・水/だしの
    効果・場所代/日費用・初期現金/評判など他の差分表項目は無変更。詳細は§6「市場での
    購入 — 永順青果／残り5店」を参照。要点は次の4つ。
    - 購入単位を一律5杯分パックから品目ごとの3個／5個パックへ組み替え、モツ・海老に
      小口1個購入（`offal_single`/`shrimp_single`）を新設した。`*_goods()`の各要素が
      `id`（ボタン識別）・`item`（在庫対象。パックと小口で共通）・`count`（1回の購入で
      増える個数）を持つ形に変わり、`GameState.INGREDIENT_SERVINGS_PER_PURCHASE`
      （一律5杯分固定）は削除した。
    - `perishable_batches`の各ロットに実際に払った`unit_price`を持たせ、同日でも
      単価が違えば別ロットのまま保持する。`discard_spoiled_inventory()`の返り値が
      `{item: {"count","value"}}`へ拡張され、廃棄額は市場価格からの概算ではなく
      ロットの実額の積算になった（日次ログのキーも`spoiled_value_approx`→
      `spoiled_value`に改名）。
    - すじ肉のタグにPOWERを追加（POWER＋BITEの兼用在庫に）、乾燥浮き袋を腐る側から
      腐らない側へ変更、肉団子の表示名を「くず肉団子」から統一した（市場ラベル・
      調理画面のADJUSTラベル・廃棄通知の3箇所）。私が作成した指示文は乾燥浮き袋の
      腐敗フラグを「変更不要」と誤って記載しており、Claude Codeの実装レビューで
      見つかった食い違い（§3の目標表と現状の食い違い）。
    - `tests/ingredient_pricing_test.gd`（新規。19ボタン全件の価格/個数/単価、モツの
      パック+小口の別ロット、廃棄額の実額一致、すじ肉のタグ回帰などを検証）＋既存
      `tests/balance_log_test.gd`の更新（5スイート計177項目、失敗0）＋Godot実機の
      Day1本編（各店の購入ボタン表示・小口購入2件・肉団子のラベル変更・具材を
      放置して腐らせたときのPREP通知とBALANCE_LOGの`廃棄額=`表記）で確認済み。
      コミット：`e6fbc27`。
13. **[済]** 評判の更新＋客数の決め方（差分表4・5項目め。`BALANCE_REDESIGN_PLAN.md`§8
    「④仕込みと評判・予告」のうち評判・客数の部分、および§5「評判→客数」）：項目11で
    2ラウンドに分けた②評判の更新／③客数の決め方を、互いに結合が強いため1回にまとめて
    着手した。仕込みの3段階化（④の残り）・予告UI（同）・Day2-7の固定日程（day_schedule.json
    は引き続きダミーデータ）・`judge_bowl`本体・②拒否と部分提供の達成可能人数計算は今回
    対象外（値の移行は1項目ずつ、という§8方針の例外として評判・客数のみ同時に変更）。
    詳細は§4「評判（実装済み・2026-09-25改訂）」「客数の決め方（実装済み・2026-09-25
    改訂）」を参照。要点は次の4つ。
    - 杯ごとの即時評判加算（`apply_reputation(delta)`、`REPUTATION_NAMED`/`REPUTATION_MOB`
      の名前あり客/モブ別テーブル）を廃止し、閉店時1回だけの当夜品質式に統一した。
      `REPUTATION_SCORE`（GREAT100/GOOD75/OK35/BAD0、客種別の区別なし）で判定結果を
      `_log_quality_counts`へ積み、`_quality_score()`が`judge:false`の杯（配達員の持ち帰り等）
      を除いた分母で加重平均Qを計算し、`GameState.settle_reputation(quality)`
      （`reputation = round(reputation*0.7 + quality*0.3)`）を閉店時に1回だけ呼ぶ。
      分母0のときはQ=0として扱う0除算ガードを追加した。
    - 評判しきい値でモブ人数を直接抽選する方式（`MOB_COUNT_TABLE`/
      `mob_count_for_reputation()`/`mob_count_today()`）を廃止し、その夜の総需要
      （`GameState.total_demand_today()`。評判帯ごとの中心値`DEMAND_TABLE`を軸に
      ±1を25/50/25%で抽選、Day1は`DAY1_DEMAND`固定）を決めてから、名前あり客の実際の
      注文杯数（`_customer_total_servings()`。配達員のDay1限定3杯構造とDay2以降の
      1杯フォールバックの両方を正しく数える）を差し引いた残りを、`_plan_mob_groups()`が
      4人以下の組へ分割し固定優先順位（`_GROUP_SLOT_PRIORITY`、対象枠が無ければ
      "夜半"へフォールバック）で各時間帯へ配分する方式に置き換えた。Day1・デバッグの
      `[モブ人数]`上書き時は従来どおり枠ごとの独立抽選のまま。
    - `_visit_tally`から評判関連フィールド（`rep_sum`/`rep_count`）を削除し、
      `customer`/`sale`/`servings`/`results`/`pending_favorite`のみに簡素化した。
      計器盤のOPEN表示も「評価%d件 評判増減の合計%d」から「判定内訳%s」に変更。
    - `tests/reputation_demand_test.gd`（新規。Q計算・settle式・0除算ガードなどを検証）＋
      既存`tests/schedule_test.gd`（モブ0人テストを、評判に依存しないDAY1_MOB_COUNT固定の
      検証へ置き換え）・`tests/group_partial_serve_test.gd`（提供直後の評判即時変化テストを、
      「評判は提供直後には動かない」検証へ置き換え）の更新＋Godot実機で確認済み。
      コミット：`da42bcf`。
14. **[済]** 仕込み3段階化＋鍋容量拡大（差分表6・7項目め。`BALANCE_REDESIGN_PLAN.md`
    §1・§2）：食肉仲卸で固定¥80・10杯だった仕込みを、小8杯/80・中11杯/110・
    大14杯/140の3段階から毎朝選ぶ形に変えた回。鍋容量拡大（差分表7）は
    `remaining_servings`に上限コードがもともと無いため、仕込み杯数を増やすだけで
    水込み12/15/18杯が自動的に成立し、**この時点では**追加実装は不要だった
    （【2026-10-04追記】この前提はのちに3-6で変わった。自動試遊で容量超過の不整合が
    見つかり、`can_add_water()`/`water_reachable()`に容量条件を追加。水込みの上限は
    小12（変化なし）・中15→13・大18→14へ変更された。詳細は§6「鍋の同時容量14」参照。
    【2026-10-18訂正】この「中13・大14」は**夜の始まりに入れられる量**で、一晩の総杯数は
    実測で12／15／18のまま）。濃さ三点セット
    （8・9・10項目め）・場所代/運営費（11・12項目め）・売価/初期現金/初期評判
    （1・2・3項目め）・固定日程・予告UIは今回対象外。詳細は§6「仕込みの3段階化」
    「クズ野菜ベース」を参照。要点は次の3つ。
    - 食肉仲卸での固定PAYを、`PREP_TIER`という新しいEvent型（MARKETと同じ
      `options`方式）に置き換えた。選ぶと即座に支払い、残りのPREP Event列
      （`Day1Events.prep_after_tier_events()`）を選んだ段階の杯数で組み立て直し、
      `flow.set_runner()`でrunnerごと差し替える。差し替え後の列の先頭は
      「index 0の効果は適用されない」という既存仕様（`_load_current_customer()`と
      同じ制約）に合わせ、必ず効果の無いTEXTにしている。`GameState.SERVINGS_PER_BASE`
      は削除、`GameState.BASE_PRICE`は予備ベース購入専用に意味を分離した
      （小仕込みの価格とたまたま同じ80だが、次ラウンドで予備ベースが濃縮だしへ
      置き換わっても巻き添えで壊れないようにする分離）。
    - クズ野菜ベース（端材屋）フォールバックの閾値を`GameState.BASE_PRICE`から
      `Day1Events.PREP_TIERS[0].price`参照へ変更（値は同じ80のまま、意味の紐付けを
      分離）。この場合の杯数は3段階のうち最小と揃え、小仕込みと同じ8杯に固定した
      （旧`SERVINGS_PER_BASE`は10だった）。
    - `tests/prep_tier_test.gd`（新規33項目）＋既存の全7スイート404項目（回帰なし）＋
      Godot実機（3段階の表示・価格・杯数、端材屋フォールバック、Day2の立ち話挿入を
      確認）で確認済み。コミット：`9a49e90`。

15. **[済]** 濃さメカニクス三点セット（差分表8・9・10項目め。`BALANCE_REDESIGN_PLAN.md`
    §1・§2）：水の効果（濃さ-1→-2）・濃さを上げる手段（予備ベース→濃縮だし）・
    濃さの上下限（`clampi`での切り捨て→ボタン側での無効化）をまとめて実装した回。
    実装中に差分表には無い論点を2つ発見し、対応した：鍋が煮詰まる自動+1を
    「時間帯が変わるたび（1晩最大2回）」から「明け方（最後の時間帯）に入った瞬間だけ
    （1晩1回）」に変更したこと、および濃さ0を新設の「提供不可」（評価1段階低下とは
    別の、提供そのものを止める状態）として扱ったこと。場所代/運営費（11・12項目め）・
    売価/初期現金/初期評判（1・2・3項目め）・固定日程・予告UIは今回対象外。詳細は
    §5「濃さの上限・下限」「濃縮だしの購入」「鍋が尽きたときの対応」を参照。要点は
    次の4つ。
    - `STRENGTH_MIN`/`STRENGTH_MAX`（評価が1段階下がる境界。値は1・5のまま）と、
      新設`STRENGTH_HARD_FLOOR`（水を足せるかどうかの下限。0＝提供不可）を分離した。
      `judge_bowl()`の`bad_strength`判定はこの2つの定数を直接見ているため、
      `STRENGTH_MIN`自体を変えると「濃さ1で評価-1段階」が壊れる（0と1を取り違える）
      ——これを避けるための意図的な分離。`judge_bowl()`は無改修。
    - 予備ベース（`reserve_base_units`ほか4フィールド・`buy_reserve_base()`・
      `add_base()`等）を丸ごと削除し、濃縮だし（`dashi_units`・`buy_dashi()`・
      `add_dashi()`）へ置き換えた。予備ベースと違い1周1回の制限・期限・傷みは無く、
      市場で毎日何度でも¥16で買える単純なカウンタ。`GameState.BASE_PRICE`（予備ベース
      購入専用に前ラウンドで意味を分離済みだった）も呼び出し元が消えたため削除した。
    - 水・だしとも「実行後の濃さが範囲を超えない場合だけ操作できる」よう
      `can_add_water()`/`can_add_dashi()`が事前にガードし、`add_water()`/`add_dashi()`
      側は`clampi`しない。濃さ0は名前あり客・配達員のADJUST中`[入力完了]`を無効化し
      （残量不足の`_is_short_in_adjust()`と対になる`_is_strength_zero_in_adjust()`）、
      REACT到達時にも保留へ落とす安全策を重ねた（自動閉店へは倒さない＝濃縮だしがあれば
      `[鍋を見る]`で救えるため）。モブ客は`_mob_achievable_servings()`が強制的に0を
      返し、既存の「達成可能0なら断るしか出せない」団体オーダーの仕組みにそのまま
      乗せた。鍋モードの`[戻る]`は水待ち・だし待ちの二重ロック（どちらも対応する資源が
      無ければ塞がない＝出口は必ずある）にした。
    - **新しい相互作用**：濃さ3スタートのまま水を連続2回使うことはできない（1回目で
      3→1、2回目は1-2<0でブロック）。明け方の自動+1を挟んで初めて2回使い切れる。
      目標仕様の「一晩の最大供給＝小12・中15・大18（水2回込み）」はこの「水を分散して
      使う」プレイが前提（【2026-10-04追記】この数字はのちに3-6（鍋の同時容量14）で
      小12・中13・大14へ変わった。詳細は§6「鍋の同時容量14」参照。【2026-10-18訂正】一晩の総杯数は12／15／18のまま）。
      `tests/soup_strength_test.gd`（新規、`[戻る]`の二重ロックを
      含む18項目）＋`tests/prep_tier_test.gd`（水連続2回のテストを明け方+1を挟む形に
      修正）＋既存の全スイート（回帰なし）＋Godot実機で確認済み。コミット：`5927470`。

16. **[済]** 場所代・水道代の再編＋日々の運営費（差分表11・12項目め。
    `BALANCE_REDESIGN_PLAN.md`§1・§2）：場所代・水道代の合計を200（150+50）→140
    （90+50）に、日々の運営費を無→80/日（7日間毎日）にした回。指示文の当初案
    （日々の運営費を`Day1Events.wake_events()`にPAY Eventとして追加するだけで
    済むはず、という提案）には抜け穴があり、実装前にClaude Codeが発見した：
    `FlowController._phase_can_skip[WAKE] = true`のため、`[次のPhase]`は
    WAKEのEvent列を1つも消化せずに先へ進めてしまえる（§3「フェーズゲート」参照）。
    Event列側に支払いを置く方式では、この経路で運営費を毎回回避できてしまう
    ところだった。売価/初期現金/初期評判（1・2・3項目め）・固定日程・予告UIは
    今回対象外。詳細は§6「WAKE」「支払い予定」「PREP」「ゲームオーバー」を参照。
    要点は次の4つ。
    - **日々の運営費は、Event列ではなく`debug_panel.gd._set_runner_for_phase(WAKE)`
      が直接支払う**よう設計を変更した（`_visit_water_stall()`と同じ「Eventを
      介さず直接コードで払う」方式に揃えた）。支払い失敗時は、`force_phase(GAME_OVER)`
      が同期的に`_set_runner_for_phase(GAME_OVER)`のrunnerを組んでしまう
      再入問題を避けるため、直後に`flow.set_runner(wake_events())`を呼ばず
      即`return`する（既存の`_visit_water_stall()`の`return false`パターンと同型）。
    - `GameState.RENT_PRICE`を150→90に変更（チンピラのPAY・
      `_reason_after_collecting_rent()`の特別請求は、どちらも定数をシンボル参照
      しているだけなので無改修で追従）。水道代は`debug_panel.gd`内のマジック
      ナンバーだったのを`GameState.WATER_PRICE`(50・値は変更なし)として定数化した。
      `GameState.DAILY_OPERATING_COST`(80)を新設。
    - 実際の天引きタイミング（WAKEで即時）と物語上の支払い先（「共同水道と
      炭屋」に市場を出るときまとめて渡す、という体裁）をあえて分離し、
      `GameState.pending_bills_today`という表示専用の「支払い予定」を新設した。
      STATE VIEWERのmoney行に`（支払い予定NN）`として出し、`[市場を出る]`・
      `mark_rent_paid()`（場所代を払った瞬間）のたびに減っていき、0になると
      注記自体が消える（moneyそのものには影響しない二次的な値）。
    - 水場は市場のボタン一覧・専用の訪問セリフを廃止し、`[市場を出る]`時に
      未訪問なら自動で1回精算する既存経路だけに一本化した（払い忘れは起こらない）。
    - 新規`tests/upkeep_test.gd`（30項目：新定数の値、WAKEでの運営費天引き、
      `[次のPhase]`即時スキップへの耐性＝§0で見つけた抜け穴の回帰テスト、
      PREPの端材屋判定が天引き後の所持金を見ること、支払い不能時のゲームオーバー、
      Day1限定の場所代・水道代、既存の特別請求の回帰、支払い予定の推移とSTATE
      VIEWER表示）＋既存の全スイート（回帰なし）＋Godot実機で確認済み。
      コミット：`d17e1d4`。
    - **実装中に見つかった副次的な発見（対象外・現状は無害）**：`_ready()`が
      `flow.phase_changed.connect(...)`より前に`_set_runner_for_phase(GameState.phase)`
      を呼ぶ初期化順のため、ゲーム開始直後の最初のWAKEで支払いに失敗すると
      ゲームオーバー画面のrunnerが組まれない潜在的な穴がある。`INITIAL_MONEY`(300)
      が`DAILY_OPERATING_COST`(80)を必ず上回るため現状は起こりえない。詳細は
      §6「ゲームオーバー」の「既知の注意点」参照。

17. **[済]** 差分表最後の3項目：売価・初期現金・初期評判（差分表1・2・3項目め。
    `BALANCE_REDESIGN_PLAN.md`§1・§2）：売価を50→45、初期現金を300→600に変更し、
    初期評判を0→30にした回。**これで`BALANCE_REDESIGN_PLAN.md`§1の差分表13項目が
    すべて完了した**（差分表に含まれない固定日程・予告UIのみ対象外として残る）。
    詳細は§2「ゲーム共通の定数」「状態変更の入口」・§6「OPEN」「所持金の推移」
    「1杯ずつ接客する客」を参照。要点は次の4つ。
    - `PRICE_PER_SERVING`・`INITIAL_MONEY`はどちらも既存コードがシンボル参照の
      みで、マジックナンバーの重複が無かったため、値を変えるだけで全ての売上・
      初期所持金計算に無改修で追従した。
    - 初期評判は`INITIAL_MONEY`と違って定数化されておらず、変数宣言側・
      `reset_for_new_game()`の2箇所に`0`が直書きされていたため、新設の
      `GameState.INITIAL_REPUTATION`（30）に統一し、`INITIAL_MONEY`と同じ
      二重管理防止のパターンに揃えた。
    - **実装時に見つかった追加のバグ**：`tests/group_partial_serve_test.gd`に、
      `PRICE_PER_SERVING`をシンボル参照せず団体客3人分の売上を`150`
      （3人×旧価格50）と直書きしていた箇所が1件あり、45への変更で
      実際にテストが落ちた（正しくは135）。`3 * GameState.PRICE_PER_SERVING`へ
      修正し、以後の価格変更にも追従するようにした。指示文の事前grep確認では
      見つかっていなかった箇所で、Plan段階ではなく実装（テスト実行）で初めて
      判明した。既存の全テストスイート・他のテストファイルには同様のマジック
      ナンバーは無いことを確認済み。
    - **§7「初日と目標」の資金例との整合性確認**：前ラウンド（16番目）で場所代
      （OPEN中のチンピラ接客時）と水道代（PREP中の市場退出時）の支払い
      タイミングを分離したため、§7が想定する「買い物より前に場所代・水道代
      140をまとめて引く」という前提と、現在の実装の支払い順序は一致しない。
      「PREP終了時点（開店前）」の所持金は、場所代90がまだ引かれていない分
      §7の目安より90多く出る（実測390。§7の想定78に対応する数字は、閉店時に
      場所代を払い終えた後で初めて現れる）。**閉店時の所持金（実測705。§6
      「所持金の推移」参照）は売上を含めれば§7の目安と整合する**。途中経過の
      数字だけを見て不具合と誤解しないよう、§6「所持金の推移」に注記した。
    - 既存の全9スイート（`group_partial_serve_test.gd`の1件を修正のうえ回帰なし）
      ＋Godot実機（新規ゲーム開始直後のmoney/reputation・Day1のPREP終了時点と
      閉店時の所持金・Day2の需要バンド）で確認済み。新規テストスイートは
      追加していない（3つとも単純な定数変更で、既存スイートの多くが`money`・
      `reputation`を明示的にセットする作りだったため）。コミット：`ec1b0a5`。
18. **[済]** 団体客の分割提供（最大2レシピ）＋ADJUST表示改善：項目10で
    `BALANCE_REDESIGN_PLAN.md`§6が「将来検討」としていた、団体を複数レシピに分けて
    届ける機能に着手した回。あわせて、ADJUST具材ボタンの所持数表示・調味料/具材の
    2行分割も同時に依頼された。詳細は§5「団体客の人数調整」「調理（ADJUST）」を
    参照。要点は次の4つ。
    - **分割提供**：達成可能人数が注文人数に満たない（0を含む）とき、レシピ1に限り
      「N人分を提供／注文を断る」に加えて「残り◯人に別の具材で挑戦する」を出す。
      選ぶとレシピ1分をその場で確定し、既存の「同じ客の2杯目以降」と同じ
      `new_bowl:true`の仕組みを使って新しいADJUST/SERVE/REACTを**現在のrunnerの
      直後へ動的に挿入**する（PREP_TIERのような runner 丸ごと差し替えではない）。
      2回目のADJUSTでは「挑戦する」を出さず、最大2レシピで打ち止めにする。
    - **記録の統合**：配達員の複数杯集計（`_visit_tally`）を団体客にも拡張し、
      1団体＝1件の`record_served()`にまとめた。`ordered_servings`/`unserved_servings`/
      `declined`は団体客由来のときだけ付き、配達員側の記録形式は変わらない。評判
      （`_log_quality_counts`）への加算は各レシピの`_add_to_visit_tally()`時点では
      行わず、グループ確定時の`_flush_visit_tally()`で`results`をまとめて1回だけ
      加算する（レシピごとに加算すると二重加算になるため。閉店時にしか読まない
      集計なのでタイミングの違いは結果に影響しない）。
    - **ADJUST表示改善**：具材ボタンに所持数を`(N)`で表示（既存の在庫チェック用の値を
      表示に使うだけ）。調味料・具材のボタンを`SeasoningRow`/`OptionsRow`の2行に分け、
      分類は新しい辞書を作らず既存の`Ingredients.is_topping()`（具の軸判定）を
      流用した。**苦瓜（bitter_melon）はタグがBITTERのみのため調味料側になる**
      （`ingredients.gd`に明記された既存仕様どおりで、指示文が出した独自の分類案とは
      この1点だけ食い違ったが、既存仕様を優先した）。
    - `tests/group_partial_serve_test.gd`（24→45項目。分割提供の成功／再挑戦後も
      不足するケースの2シナリオを追加）＋新規`tests/adjust_button_display_test.gd`
      （11項目。所持数表示・2行分割・苦瓜の分類を検証）＋既存の全スイート（回帰なし。
      合計497項目）＋Godot実機で確認済み。コミット：`9c9da7e`。

**【解消済み・フェーズ1の範囲外】閉店で場所代を避けられる**
- **現象**：徴収日（Day1）に、場所代（チンピラのPAY）より前で閉店すると、場所代を
  払わずに済んでいた。保留中の閉店と、ADJUST中の「鍋が足りず水も無い」ときの閉店の
  両方で起きる（閉店で現在の客の後ろのEventが飛ぶため）。
- **直し方（実装済み・確認済み）**：`GameState`に`RENT_PRICE`定数と
  `rent_paid_today`（日次リセット）・`mark_rent_paid()`を追加。チンピラのPAY Event
  に`"kind": "rent"`の印を付け、実際に払えたときだけ`mark_rent_paid()`を呼ぶ。
  `debug_panel.gd`の`_reason_after_collecting_rent()`が、`_on_close_pressed()`
  （手動閉店）と`_auto_close_kitchen()`（鍋が尽きての自動閉店）の両方で、CLOSEへ
  飛ばす直前に「徴収日でまだ払っていなければ`RENT_PRICE`を特別請求する」を行う。
  払えなければ通常の場所代と同じくゲームオーバー、払えれば理由テキストに一言添える。
  徴収済みなら素通りする（二重請求しない）。詳細・確認手順は§5「未解決」→
  「【解消済み】閉店で場所代を避けられる不具合」および「ゲームオーバー」参照。

**旧「次の候補」の行き先**：
- 提供後の会話を厚くする → フェーズ2（1客分）・フェーズ4（7日分）
- メニュー・レシピ → フェーズ2（最小5種を閲覧のみ）
- favorite をレア食材にする → フェーズ4（既存食材から本番用に決める。高価な食材で
  仕入れとの関係を作り、ランダム入荷の仕組みは作らない）
- スマホ機能 → フェーズ4（その日のニュース・メッセージ・レシピを読む最小画面）
- 7日分の会話を書く → フェーズ2で概要表、フェーズ4で本文
- 評判20以上の帯を確認する手段 → 必要になったら（フェーズ5で検討）

**今回の工程に入れないもの**：全面リファクタリング・GameStateの分割・汎用会話エンジン、
購入ロット別の腐敗、会話途中・調理途中の完全セーブ、結果総括・複数エンディング・
好感度システム。提供記録（ServedRecord）の詳細化は、後から参照する必要が出た
ときに追加する。
（**「全データの一括外部化」は2026-09-22にスコープを確定し対象化した**：
Day3〜7の日程・客・モブデータのJSON化は§9「C. データの外部化」の設計で進める。
それ以外＝画像・音声・本番UI関連データの外部化は引き続き対象外）

**進め方**：これまでと同じく、1ステップごとに「Claude Codeが最小変更のPlanを出す →
確認して実装 → Godotで動作確認 → CURRENT_SPEC.mdへ反映」の順で進める。
