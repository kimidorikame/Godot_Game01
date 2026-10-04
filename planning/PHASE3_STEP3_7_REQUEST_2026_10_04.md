# フェーズ3-7（朝の一画面・予報の幅）実装plan作成依頼

対象：Claude Code（実装担当）。本書は「何を・どこまで」の要件定義であり、実装その
ものの手順書ではない。まず本書の内容を読み、**実装plan（変更するファイル・関数・
テストの一覧）**を提示してから着手すること（3-6までと同じ粒度・1手順＝1コミット）。

## 0. 前提

`DESIGN.md`10.10「フェーズ3」のうち3-1〜3-6は完了している。

| 手順 | 内容 | コミット |
|---|---|---|
| 3-1 | F1：キャンペーン設定の器（`Rules`／`data/campaigns/week7.json`） | `2cb5ab1` |
| 3-2 | F2：DayPlan（`DayPlanner`／`GameState.today_plan`） | `6fb2e24` |
| 3-3 | F3：SaleRule＋判定v2＋減点の事前表示＋断る操作 | `bcea23d` |
| 3-4 | F4：帳簿（`Ledger`）＋予算表示＋市場の個数・単価＋前日成績v2 | `220d9a4` |
| 3-5 | Day1の9杯化・初日セット・朝の確保・持ち帰りの注文化 | `5d86444` |
| 3-6 | 鍋の同時容量14 | `b4967db` |

本書が依頼する3-7は、この6部品の上に積む。`CURRENT_SPEC.md`も3-6時点の実装事実に
更新済み（コミット`4a11249`）。

**環境制約**：本書の作成者（このチャットのAI）はGodotエンジンを実際に実行できる
環境を持たない。全ての確認は静的解析（コード読解・grep・diff）のみで行っている。
実装後は必ず実機（Godotエディタ／`--headless`）で`tests/run_tests.gd`を実行し、
静的解析では見えない実行時エラーが無いことを確認すること。

---

## 1. 対応箇所と終わりの条件

対応：`DESIGN.md`10.4「情報・UI」の「朝の一画面」「予報の精度」の2行。
終わりの条件（10.10）：**Day2以降に総杯数が幅で出る**。

> | 項目 | 仕様 |
> |---|---|
> | 朝の一画面 | SNSの客足予報に「総杯数」「必要な味・具の数」「手持ち在庫との過不足」
> 「使える現金」を並べる。上限案・平均案の仕入れを見比べられるが、**自動購入はしない** |
> | 予報の精度 | Day1は完全公開（配達員の3杯の内訳も）。Day2以降は常連3人の基本注文・
> 既知の好物＋モブの客層（種類の一覧・重複除去）＋総杯数の幅（需要中心±1）。
> 「今日の頼み」は会話で判明 |
>
> 予報の幅の注意：幅は`demand_center`（需要の中心）を基準に出す。実際に引いた値を
> 中心に幅を出すと「真ん中＝実際」と読めてしまう。モブは組数を出さない（組数から
> 人数が逆算できるため）。

## 2. 現状（静的解析で確認済み）

- SNSタブの本文は`scripts/debug_panel.gd`の`_format_tonight_memo()`（約1843〜1871行）
  が作っている。`GameState.today_plan["slots"]`（`DayPlanner.build()`がWAKEで1回だけ
  確定）を時間帯ごとに回し、各客の`Day1Events._customer_flavor(cid)`から
  `wanted_tags`・`favorite`（開示済みのみ）・モブなら`greet[0]`を使って「誰が・何人・
  どんな味を求めているか」の一言メモを作るだけで、**総杯数・必要な味/具の数・在庫との
  過不足・使える現金のどれも出していない**（未実装、今回の対象そのもの）。
- `tests/`配下に`_format_tonight_memo`／`_format_phone`／SNSタブを直接検証する
  テストは**現状1件も無い**（新規追加のみで、既存テストへの影響は無い見込み）。
- `Rules.forecast()`（`scripts/rules.gd`115行付近）は`week7.json`の
  `"forecast": {"regulars": "base_order", "total": "range", "range_width": 1}`を
  返すだけの読み取り専用口として3-1で実装済みだが、**コード内のどこからも
  呼ばれていない**（宣言のみ・3-7で消費、という3-5/3-6の`day_overrides`と同じ
  位置づけ）。`week7.json`の`day_overrides."1".forecast`＝`"exact"`も同様に未消費。
- **`total_demand_today()`は「中心」を外から取れない**：`game_state.gd`の
  `total_demand_today()`は評判から`center`をローカル変数として計算した後、
  `center-1`/`center`/`center+1`を抽選して返すだけで、`center`自体を返す経路が
  無い。予報の幅（`demand_center`±1）を表示するには、**抽選をやり直さずに
  `center`だけを取得できる新しい関数**（例：`demand_center_today()`。`day_overrides`に
  `fixed_demand`がある日＝Day1はその値をそのまま返す）を追加する必要がある
  （`total_demand_today()`側もこの新関数を呼ぶ形にリファクタしてよい。評判→中心の
  対応テーブル`DEMAND_TABLE`の参照先を1箇所にまとめられる）。
- **配達員のDay1「3杯の内訳」は`_customer_flavor()`からは取れない**：
  `Day1Events._customer_flavor("delivery_man")`はDay1限定で
  `{is_mob, wanted_tags, favorite}`のみを返す（`data/customers/delivery_man.json`の
  トップレベル値＝HOT/POWER・favorite=tofu）。しかし実際の3杯目（持ち帰り）の
  `wanted_tags`（MELLOW/GENTLE）は`_delivery_man_events()`（`day1_events.gd`約639〜
  672行）の中に**直接ハードコード**されており、`_customer_flavor()`からは見えない。
  「配達員の3杯の内訳も完全公開」を予報画面に出すには、この3杯目のタグをどこからか
  参照できるようにする必要がある（`_delivery_man_events()`から定数として切り出す、
  または`_customer_flavor()`が返す辞書に「3杯目の注文」を追加する、等。具体的な
  やり方はplan作成時に決めてよいが、**ハードコードされた値を2箇所に重複させない**
  こと）。
- **必要な味・具の数の集計元**：`GameState.today_plan["slots"]`の各客の
  `wanted_tags`（モブは`ScheduleData.mob_data(type).wanted_tags`、名前あり客は
  `customer_data`経由）を集計すればよい。モブの人数は
  `today_plan["mob_instances"][id]["count"]`から分かるが、**10.4の注意どおり
  「何組か」は出さない**（タグ集計に人数分だけ加算し、組数自体は表示しない）。
- **手持ち在庫との過不足の集計元**：`Ingredients.tags_for(id) -> Array`
  （`scripts/ingredients.gd`103行）が具材id→タグ[]を返す。これと
  `GameState.inventory`（id→個数のDictionary）を組み合わせれば、「タグ別に今何個
  作れるか」を集計できる（具材1個＝1杯分、という前提は`SaleRule`/`Judge`と同じ）。
  ただし「タグ別に必要な個数」と「タグ別に用意できる個数」を直接数で比較する場合、
  1杯の注文はタグが2つ（味1＋具1）組み合わさってできる点に注意（例：HOT+POWERの
  注文1件は「HOTタグを持つ調味料」と「POWERタグを持つ具」を両方消費する）。
  過不足の判定粒度（タグ単位の個数比較でよいか、注文の組み合わせまで見るか）は
  plan作成時に決めてよいが、**判定ロジックをどこに置くか（`judge.gd`寄りの新規
  ヘルパーか、`debug_panel.gd`内のプライベート関数か）**は明記すること。
- **使える現金の集計元**：`Ledger.pending_bills_today()`（`scripts/ledger.gd`35行）
  と`GameState.money`を使い、`_format_game_state()`の`budget`行（約1751〜1753行、
  `GameState.money - Ledger.pending_bills_today()`）と同じ計算式を再利用する
  （表示ロジックを重複させたくない場合は、共通のフォーマット関数へ切り出してよい）。

## 3. 変更が必要な箇所（概要。詳細はplanで）

- `game_state.gd`：`total_demand_today()`から「中心」だけを取る新しい関数
  （`demand_center_today()`等）を追加する。
- `day1_events.gd`：配達員Day1の3杯目（持ち帰り）の`wanted_tags`
  （`["MELLOW", "GENTLE"]`）を、`_delivery_man_events()`とSNS予報の両方から
  参照できる形に切り出す。
- `debug_panel.gd`の`_format_tonight_memo()`（または新設の関数）を拡張し、
  既存の客ごとの一言メモに加えて次を足す：
  - **総杯数**：Day1（`Rules.day_overrides(day).forecast == "exact"`）は実際の
    合計杯数をそのまま。Day2以降（`Rules.forecast().total == "range"`）は
    `demand_center_today()`を`Rules.forecast().range_width`（＝1）で幅表示する
    （「中心＝実際」に読めないよう、実際に引いた値ではなく中心を基準に幅を出す）。
  - **必要な味・具の数**：`today_plan`の客ごとの`wanted_tags`をタグ別に集計（モブは
    組数を出さず人数分だけ加算。配達員Day1は3杯分＝本人2×HOT/POWER＋持ち帰り1×
    MELLOW/GENTLEとして加算）。
  - **手持ち在庫との過不足**：上記の必要数と`GameState.inventory`（`Ingredients.
    tags_for()`でタグ換算）を比較し、不足しているタグだけを出す。
  - **使える現金**：`Ledger.pending_bills_today()`を使い`budget`行と同じ式で1行足す。
  - Day2以降の予報精度：常連3人の基本注文・既知の好物＋モブの客層（種類の一覧・
    重複除去）＋総杯数の幅。「今日の頼み」（`wanted_tags`の実効値）は出さず、基本
    注文（`customer_data`のデフォルト値）を使う。
  - **自動購入はしない**：この画面は表示のみ。ボタンから直接仕入れる機能は追加しない。

## 4. 新規テスト

既存テストにSNSタブ・予報まわりを触るものは無いため、新規ファイル
（例：`tests/morning_forecast_test.gd`）を追加する形になる見込み。最低限、以下を
含めること：
- Day1の予報が実際の9杯・配達員の3杯内訳（本人2×HOT/POWER＋持ち帰り1×MELLOW/
  GENTLE）を含めて完全公開されること。
- Day2以降、`demand_center_today()`を基準に幅（中心±1）で総杯数が出ること（実際に
  引いた`total_demand_today()`の値ではなく中心を見ていることを、中心と実際の値が
  ずれるケースで確認する）。
- モブの表示が「組数」ではなく客層の種類一覧（重複除去）になっていること。
- 使える現金の表示が`budget`行と同じ値になること。

## 5. 依頼のまとめ

1. 上記を踏まえ、変更対象ファイル・関数・新規テストを一覧にした実装planを提示
   してから着手する。
2. コミットメッセージはこれまでと同じ形式（「3-7: 内容」）に揃える。
3. 実装後、`tests/run_tests.gd`を実機で実行し、全項目が通ることを確認する。
4. 完了後、`CURRENT_SPEC.md`の該当箇所（SNSタブ／`_format_tonight_memo()`の説明）を
   実装事実に合わせて更新する依頼を改めて出す（このチャット側で別途対応）。
