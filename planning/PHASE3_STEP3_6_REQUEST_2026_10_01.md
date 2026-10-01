# フェーズ3-6（鍋の同時容量14）実装plan作成依頼

対象：Claude Code（実装担当）。本書は「何を・どこまで」の要件定義であり、実装その
ものの手順書ではない。まず本書の内容を読み、**実装plan（変更するファイル・関数・
テストの一覧）**を提示してから着手すること（3-5までと同じ粒度・1手順＝1コミット）。

## 0. 前提

`DESIGN.md`10.10「フェーズ3」のうち3-1〜3-5は完了している。

| 手順 | 内容 | コミット |
|---|---|---|
| 3-1 | F1：キャンペーン設定の器（`Rules`／`data/campaigns/week7.json`） | `2cb5ab1` |
| 3-2 | F2：DayPlan（`DayPlanner`／`GameState.today_plan`） | `6fb2e24` |
| 3-3 | F3：SaleRule＋判定v2＋減点の事前表示＋断る操作 | `bcea23d` |
| 3-4 | F4：帳簿（`Ledger`）＋予算表示＋市場の個数・単価＋前日成績v2 | `220d9a4` |
| 3-5 | Day1の9杯化・初日セット・朝の確保・持ち帰りの注文化 | `5d86444` |

本書が依頼する3-6は、この5部品の上に積む。`CURRENT_SPEC.md`も3-5時点の実装事実に
更新済み（コミット`3d9076e`）。

**環境制約**：本書の作成者（このチャットのAI）はGodotエンジンを実際に実行できる
環境を持たない。全ての確認は静的解析（コード読解・grep・diff）のみで行っている。
実装後は必ず実機（Godotエディタ／`--headless`）で`tests/run_tests.gd`を実行し、
静的解析では見えない実行時エラーが無いことを確認すること。

---

## 1. 対応箇所と終わりの条件

対応：`DESIGN.md`10.3.8。
終わりの条件（10.10）：**残量13以上で水を足せない**。

> #### 10.3.8 鍋の同時容量
> - 鍋の同時容量は14。水は残量12以下のときだけ足せる（`can_add_water()` と
>   `water_reachable()` に容量条件を足す）。
> - 一晩の総供給上限18（14＋水2回×2）は変えない。

## 2. 現状（静的解析で確認済み）

- `scripts/rules.gd`に`pot_capacity()`は既に実装済み（`_economy().get("pot_capacity", 14)`）。
  `data/campaigns/week7.json`にも`"pot_capacity": 14`が宣言済み。**ただし
  `scripts/game_state.gd`のどの関数からも参照されていない**（未消費のまま）。
- `can_add_water()`（`game_state.gd`）は現在、濃さの下限（`STRENGTH_HARD_FLOOR`）
  だけを見ており、残量（`remaining_servings`）の上限チェックが無い：
  ```gdscript
  func can_add_water() -> bool:
      return soup != null and int(soup.get("water_doses", 0)) > 0 \
          and int(soup.get("strength", 3)) - WATER_STRENGTH_DELTA >= STRENGTH_HARD_FLOOR
  ```
- `water_reachable()`（だし→水の回復パス）も同様に濃さだけを見ている。
  `can_add_water()`がfalseのとき、だしを先に入れれば水を出せるか（`boosted_strength`
  経由）を判定するが、ここにも容量条件が無い。
- `add_water()`は`WATER_SERVINGS`（＝2）を無条件で`remaining_servings`に加算する
  （`can_add_water()`がtrueであることが前提。容量ガードが無い今は際限なく積み上がる）。
- UI側（`scripts/debug_panel.gd`）は`can_add_water()`／`water_reachable()`／
  `can_add_dashi()`の戻り値でボタンの有効・無効を切り替えている（約1168〜1593行、
  `_update_options_row()`周辺）。ロジック側に容量条件を足せば、UI側は自動的に
  正しく反映される設計になっている（ボタン側の個別修正は不要なはず。念のため
  実装plan時点で確認すること）。

## 3. 既知の不整合（自動試遊レポートで指摘済み）

2026-09-26実施の自動試遊レポートで、「14杯・濃さ3・水2・だし1から水→だし→水で
同時残量18」という境界プローブの不整合が指摘されている。これは上記「容量条件が
無い」ことによる既知のバグで、3-6が直接解消する対象。

## 4. 変更が必要な箇所

- `can_add_water()`に「`remaining_servings`が`Rules.pot_capacity() - WATER_SERVINGS`
  （＝12）以下のときだけ足せる」条件を追加する（水を足すと残量が+2されるため、
  足した後に容量14を超えないための事前ガード。既存の「超える操作はボタン側で
  無効化できるよう、呼び出し側でclampiしない」方針を踏襲し、`add_water()`自体は
  変更しない）。
- `water_reachable()`（だし→水の回復パス）も同じ容量条件を通した上で判定する
  よう修正する（濃さのガードと容量のガードの両方を満たさないとtrueにしない）。
- 仕込み時点の`remaining_servings`初期値は最大14（大仕込み）であり、水を足す前に
  既に容量上限にあるケースが普通に起こる（＝大仕込み直後は`can_add_water()`が
  常にfalseになる、という新しい挙動）。意図どおりであることをコメントに明記する。
- 一晩の総供給上限18（14＋水2回×2）はこのままで変えない（10.3.8）。この数値は
  表示上の理論値であり、容量ガードを入れると大仕込み（14）からは実質水を1回も
  足せなくなる、という点に注意（下記5.参照）。

## 5. 既存テストへの影響（要修正・実装plan作成時に必ず確認すること）

`tests/prep_tier_test.gd`の「水を2回使い切った場合の残量上限」ブロック
（`water_cases := [["small", 12], ["medium", 15], ["large", 18]]`、約90〜108行）が、
**容量14の制約と矛盾する期待値を持っている**：

```gdscript
var water_cases := [["small", 12], ["medium", 15], ["large", 18]]
for wcase in water_cases:
    ...
    GameState.add_water()   # 濃さ3→1
    c.check("...連続で水は2回使えない(1回目後は濃さ1でブロック)", not GameState.can_add_water(), ...)
    GameState.deepen_soup()   # 明け方の自動+1相当。濃さ1→2
    GameState.add_water()   # 濃さ2→0
    c.check("...残量は%d杯" % expected_max, int(GameState.soup.get("remaining_servings", -1)) == expected_max, ...)
```

容量14を導入すると、各段階の挙動は次のように変わるはず（実装plan作成時に
実際のコードで再検証すること。以下は静的な机上計算）：

- **small（初期残量8）**：1回目の水で8→10（容量12以下なのでOK）。2回目の水で
  10→12（容量12以下なのでOK）。`expected_max`は12のまま変化なし。
- **medium（初期残量11）**：1回目の水で11→13。**この時点で容量14は超えていないが
  12を超えているため、2回目の`can_add_water()`はfalseになり、2回目の水は入らない**。
  結果、`expected_max`は15ではなく**13**になるはず。
- **large（初期残量14）**：**1回目の水の時点で残量14は既に12を超えているため、
  `can_add_water()`はfalseで、1回目から水が入らない**。濃さも3のまま変わらない
  （`add_water()`が無条件でno-opするため）。テスト中盤の
  「1回目後は濃さ1でブロック」というコメント・アサーションの前提自体が崩れる
  （濃さではなく容量でブロックされる）。結果、`expected_max`は18ではなく
  **14（水を1回も足せない）**になるはずで、テストの手順・コメント文言ごと
  書き直しが必要。

上記はこのチャット側の机上計算であり、実機での再検証が必須。実装plan作成時に、
この3ケース（small/medium/large）それぞれの新しい期待値とテスト文言を
確定させること。`tests/soup_strength_test.gd`（約47〜53行、濃さ2スタート・水1回・
残量12のケース）は容量12以下の範囲に収まるため影響なしと見込まれるが、こちらも
plan作成時に一応確認すること。

`tests/group_partial_serve_test.gd`・`tests/sale_rule_test.gd`は`remaining_servings`を
参照するが、水を足す操作自体はテストしていないため影響なしと見込まれる
（plan作成時に確認のみでよい）。

## 6. 依頼のまとめ

1. 上記を踏まえ、変更対象ファイル・関数・テスト（特に`prep_tier_test.gd`の
   water_casesの新しい期待値）を一覧にした実装planを提示してから着手する。
2. コミットメッセージはこれまでと同じ形式（「3-6: 内容」）に揃える。
3. 実装後、`tests/run_tests.gd`を実機で実行し、全項目が通ることを確認する。
4. 完了後、`CURRENT_SPEC.md`の該当箇所（`can_add_water()`／`water_reachable()`の
   説明、鍋容量に関する記述）を実装事実に合わせて更新する依頼を改めて出す
   （このチャット側で別途対応）。
