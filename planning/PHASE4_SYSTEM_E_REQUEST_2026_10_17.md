# システム整理E（複数杯の場面：配達員の3杯専用列を場面データで表す）実装plan作成依頼

対象：Claude Code（実装担当）。本書は「何を・どこまで」の要件定義であり、実装手順書ではない。まず本書を読み、**実装plan（変更するファイル・関数・データ形式・テストの一覧・コミットの分け方）**を提示してから着手すること。

## 0. 位置づけ

しまさんの方針：**システム部分を先に作り、会話（脚本）など素材が要るものは後に回す**。システム整理A（表示名・日番号の直書き）・C（提供後の場面）・D（日別ニュース・必須情報）が済み、本書はその続き。

**Eの性格：動作を変えないデータ化**。Day1の配達員（`delivery_man_01`）は、同じ客へ3杯を1杯ずつ会話の合間に出す専用のEvent列（`Day1Events._delivery_man_events()`）で動いている。これを、場面データの形（複数杯の場面）で表せるようにし、`THREE_CUPS_EPISODE`定数と客・場面idの直書きの分岐をなくす。`DESIGN.md`10.8.6（「Day1配達員の『1杯ずつ3回』は、この形式の複数杯の場面として表す」）・10.9（配達員の3杯専用列）の最後の宿題。

完了済み：3-1〜3-8、4-1〜4-4（4-4b-2まで）、システム整理A・C・D。`CURRENT_SPEC.md`はD時点（コミット`5b2c34c`）。テストは2013件（38スイート）。

**終わりの条件（共通）**：既存データ（`delivery_man_01`の3杯）で**動作が変わらない**（Event列・会話・杯ごとの要求タグ・好物・反応・売上・乱数の消費順が同一）。自動試遊（3シード×13方針）は4-3の結果（`playthrough_results_regulars.json`）と**完全一致**する（`steps`・`clicks`・`actions`・`rows`を含む全キー差分0）。テストスイートの最後は`return c.finish()`にする。

**環境制約**：本書の作成者（このチャットのAI）はGodotを実行できない。以下は静的解析（コード読解・grep）だけで書いている。実装後は必ず実機で`tests/run_tests.gd`を実行し、全件成功を確認すること。

---

## 1. コミットの分け方（提案。planで変えてよい）

1. **コミット①：データの形・読み口・検証**。`cups`の読み口（`ScheduleData`）と`scene_problems`の検査、テスト。**`delivery_man_01.json`はまだ書き換えない**（動作は変わらない。新しい形はテスト内のデータ`tests/fixtures/episodes/`で確認する）。
2. **コミット②：配達員の3杯列を場面データへ移す**。`_delivery_man_events()`と`_DELIVERY_*`定数を、`delivery_man_01.json`の`cups`へ移し、`THREE_CUPS_EPISODE`と関連の分岐を消す。`customer_events_4_3.json`（記録）と**同一**であることと、試遊39/39一致で締める。

---

## 2. 現状（現行コードで確認した事実）

**配達員の3杯列**（`day1_events.gd`の`_delivery_man_events()`）：来店会話（`_DELIVERY_ARRIVAL`）→ 1杯目（ADJUST → SERVE → REACT）→ 会話（`_DELIVERY_AFTER_FIRST`）→ 2杯目（ADJUST`new_bowl`→ SERVE → REACT）→ 会話（`_DELIVERY_AFTER_SECOND`）→ 3杯目（ADJUST`new_bowl`→ SERVE → REACT）→ 退店会話（`_DELIVERY_EXIT`）。

| 杯 | ADJUSTのtext | SERVEのtext | 要求タグ | 好物 | 反応 |
|---|---|---|---|---|---|
| 1杯目 | `（味を調える）` | `（湯気の立つ椀を置く）` | 客プロフィール（`HOT`/`POWER`） | `tofu`（プロフィール） | `_delivery_reactions_first()`（各結果1パターン） |
| 2杯目 | 同上 | 同上 | 同上 | 同上 | `_delivery_reactions_second()` |
| 3杯目（持ち帰り） | `（持ち帰り用。辛さ控えめ、豆腐多め）` | `（店主は蓋つきの容器を袋へ入れる）` | **直書き** `["MELLOW","GENTLE"]` | **なし** | **空辞書**（反応を出さない） |

3杯とも`REACT`は`servings:1`・`sale = PRICE_PER_SERVING`・`is_mob:false`・`aggregate:true`（鍋の消費と売上はその場で、評判と提供記録は退店時に1回だけ。`DebugPanel._visit_tally`・`_flush_visit_tally`）。

**客・場面idで分岐している箇所**（`THREE_CUPS_EPISODE := "delivery_man_01"`）：

| 場所 | 今の扱い |
|---|---|
| `Day1Events.customer_events`（約608行） | `scene == THREE_CUPS_EPISODE`なら`_delivery_man_events()`を返す |
| `Day1Events._customer_flavor`（約1068行） | その場面だけ`greet`・`reactions`・`servings`を返さない（プロフィールのみ） |
| `Day1Events.after_serve_events`（約711行）・`closing_events`（約745行） | その場面は空配列（本文・選択・締めを差さない） |
| `DebugPanel._adjust_customer_id`（約2370行） | その場面は注文カード・[聞き直す]の対象外 |
| `DebugPanel._insert_after_serve_events` | `aggregate`のREACTは何も差さない（`ev.get("aggregate")`で判定。客idではない） |
| `ScheduleData`のコメント・`episode_id_of`のコメント | 3杯列への言及 |

`delivery_man_01.json`は、使われていない仮の`greet`/`reactions`/`servings:1`が入っている（3杯列では読まない）。`delivery_man_02〜04`は通常の1杯の場面。**会話の文面は仮台詞**（`_DELIVERY_*`）で、脚本の段階（4-5・4-8）で差し替える。

---

## 3. 決めてほしいこと（推奨付きで）

### 3.1 データの形

**基本案**：場面データに任意キー`cups`（杯の配列）を足す。`cups`を持つ場面が複数杯の場面。

```json
{
  "id": "delivery_man_01",
  "customer": "delivery_man",
  "greet": ["配達員「注文（HOT/POWER）」1杯目"],
  "cups": [
    { "adjust": "（味を調える）", "serve": "（湯気の立つ椀を置く）",
      "reactions": { "GREAT": ["…"], "GOOD": ["…"], "OK": ["…"], "BAD": ["…"] },
      "after": ["配達員「1杯目の共通会話…」"] },
    { "adjust": "（味を調える）", "serve": "（湯気の立つ椀を置く）",
      "reactions": { … },
      "after": ["配達員「2杯目の共通会話…」"] },
    { "tags": ["MELLOW", "GENTLE"], "favorite": false,
      "adjust": "（持ち帰り用。辛さ控えめ、豆腐多め）", "serve": "（店主は蓋つきの容器を袋へ入れる）",
      "reactions": {},
      "after": ["配達員「退店…」"] }
  ]
}
```

- `greet`：来店〜1杯目の注文（今の`_DELIVERY_ARRIVAL`）。`cups[i].after`：その杯のREACTの後の会話（最後の杯の`after`が退店会話＝今の`_DELIVERY_EXIT`）。
- `tags`省略 ＝ 実効注文（客プロフィールの`wanted_tags`）。指定すればその杯だけの要求タグ。`favorite`省略 ＝ プロフィールの好物を使う、`false` ＝ 好物なし。杯数は各1（`servings`省略 ＝ 1）。
- `reactions`省略または空 ＝ 反応を出さない（今の3杯目）。
- `adjust`・`serve`省略 ＝ 通常の場面と同じ既定文（`（味を調える）`・`「はいよ、お待ち。」`）。
- `cups`が2杯以上なら各REACTに`aggregate:true`を付ける（現行どおり）。1杯の`cups`は許すか（通常の場面との重複）をplanで決める。推奨：許さない（2杯以上）。
- **名前**（`cups`／`after`／`tags`など）が既存のキー（`reactions`・`closing`・`order.today_request.tags`）と紛らわしくないか確認し、変える場合は理由を示す。
- 場面全体の`servings`は`cups`と二重にならないようにする。推奨：`cups`があれば杯数は`cups`の数から決め、`servings`は書かない（書いてあれば`scene_problems`で`cups`の数と一致を検査）。
- **既存の仕組みとの関係**：`Forecast`・`_customer_total_servings`は`customer_events()`のREACT（`servings`・`wanted_tags`）を走査して必要数を数えている。`cups`から組んだEvent列でも同じ数字（Day1：9杯／配達員3杯）が出ることをテストで固定する。

### 3.2 複数杯の場面で使えるキーの範囲

3杯列は現在、来店記録以外の場面機能（`requires`以外）を使っていない。次のとおり範囲を絞ることを推奨する。planで違う案があれば比較して示す。

| キー | 複数杯の場面での扱い（推奨） |
|---|---|
| `requires`・`not_seen`・`market_talk`・`must_info` | **使える**（場面の選択・昼の会話・印。杯の組み立てと独立） |
| `order.today_request`・`order.reask` | **使えない**（杯ごとの`tags`で表す。両方あると意味が二重になる）。`scene_problems`で弾く |
| `callback`・`pre_order` | 使えない（複数杯の場面の「前回の出来」の定義が未決。`previous_visit`の`grade`が複数杯でどうなるかも未決）。`scene_problems`で弾く。将来足すときの入り口はplanに書く |
| `body`・`body_unserved`・`choices`・`closing`・`sets_facts` | 使えない（提供後の場面＝Cは、最後の杯の後に挟む設計がまだ無い）。`scene_problems`で弾く。将来は最後の杯のREACTの後に`after_serve_events`を差す形が見通せるか、planに一言 |

**弾く理由**：黙って無視される書き間違いを作らないため。メッセージには「複数杯の場面では使えない」と分かる文言を入れる。

### 3.3 組み立てと分岐の消し方

- `Day1Events`に`_cups_events(customer, scene)`のような組み立てを置き、`customer_events`の先頭の分岐を「場面データに`cups`があるか」に置き換える（`THREE_CUPS_EPISODE`定数を消す）。
- `_customer_flavor`・`after_serve_events`・`closing_events`・`DebugPanel._adjust_customer_id`の場面id判定も、`cups`の有無（`ScheduleData.episode_cups(...)`が空でないか、`Day1Events.is_multi_cup_scene(...)`のような1つの問い合わせ）に統一する。**客idや場面idの直書きは残さない**。
- 受け側（`DebugPanel`）は変えない方針。`aggregate`・`new_bowl`・`_visit_tally`は現行のまま使い回す。変える必要が出たら理由を示す。
- 反応の選び方（`_current_reaction_text`）が**乱数をいくつ消費するか**は現行と同一にする（各結果が1パターンの配列でも、引く回数と順序を変えない）。`reactions`が空のREACTで何も引かないことも同じ。

### 3.4 会話の文面の移し替え

`_DELIVERY_ARRIVAL`・`_DELIVERY_AFTER_FIRST`・`_DELIVERY_AFTER_SECOND`・`_DELIVERY_EXIT`・`_delivery_reactions_first/second`の**中身（仮台詞）を一字も変えず**に`delivery_man_01.json`へ移す。`delivery_man_01.json`に残っている未使用の仮`greet`/`reactions`/`servings`は整理してよい（`cups`と矛盾しない形に）。脚本そのものを書くのは4-5・4-8で、本書の範囲外。

---

## 4. テスト（最低限）

- **同一性**：`tests/fixtures/customer_events_4_3.json`（4-3時点の記録）と、`cups`から組んだDay1配達員のEvent列が**完全に同一**（キーの順を問わず値が一致。`aggregate`・`new_bowl`・各REACTの`wanted_tags`・`favorite`・`reactions`・`sale`・`servings`を含む）。`tests/first_favorite_test.gd`・`tests/customer_memory_test.gd`の配達員の既存の確認も通る。
- **読み口・検証**：`cups`の型（配列・各要素が辞書・`tags`は文字列の配列・`favorite`は真偽・`reactions`は結果→文字列配列・`after`は文字列配列）、2杯未満の拒否、§3.2の使えないキーの組み合わせが問題として返る、`servings`が`cups`の数と食い違うと問題。実データ21場面は問題なし。
- **杯の中身**：テスト用の`cups`データ（2杯・杯ごとに別の`tags`、反応なしの杯、`favorite:false`の杯）で、Event列の形・`new_bowl`が2杯目以降にだけ付く・全REACTに`aggregate:true`・退店会話が最後の杯の`after`になる。
- **周辺が変わらない**：Day1の必要数（9杯）・朝の予報（`Forecast`）が変わらない。通常の1杯の場面（`delivery_man_02〜04`ほか）は変わらない。注文カード・[聞き直す]が複数杯の場面で出ない（現行どおり）。
- **分岐の消去**：`THREE_CUPS_EPISODE`がコード（`scripts/`・`tests/`）に残っていない（grepで確認して報告）。
- **自動試遊（3シード×13方針）が4-3の結果と完全一致**。
- 書き換える既存テストと理由の一覧（`THREE_CUPS_EPISODE`を使うテスト：`tests/after_serve_test.gd`など）。

## 5. 注意

- **動作を変えない**。差が出たら原因を調べて報告すること（数値は調整しない）。
- 範囲外：会話の文言を新しく書く（4-5・4-8）、複数杯の場面での本文・選択・締め・`sets_facts`・`callback`（§3.2の表のとおり将来）、`DebugPanel`の受け側の変更（必要になった場合のみ理由付きで）、配達員の2回目以降の来店（`delivery_man_02〜04`は1杯の場面のまま）、レシピ保存・会話ログ（B）、修繕基金（A）。
- 保存の版は5のまま。`cups`は場面データの任意キーで、保存する状態を増やさない（来店記録の`visits[].serves`などの形も変えない）。版を上げる必要が出る場合は理由を示す。
- 新しい`class_name`を足す場合は`--import`が走り、`CURRENT_SPEC.md`の改行だけの差分が出ることがある（`git checkout`で戻し、コミットに入れない）。`BALANCE_REDESIGN_PLAN.md`・`BALANCE_REDESIGN_V2.md`・`planning/playtest_2026_10_11/runtime_data/`は未追跡のまま触らない。`DESIGN.md`の作業ツリー差分は改行だけの差分なのでコミットしない。コミットメッセージはファイル経由で作ること。push はしない（しまさんが手元で行う）。

## 6. 依頼のまとめ

1. 上記を踏まえ、データの形（キー名の確認を含む）・使えるキーの範囲・変更するファイル／関数・分岐の消し方・テスト・コミットの分けを一覧にした実装planを提示してから着手する。確認事項は`Q1, Q2, …`の番号を付けて、推奨を既定として示すこと。
2. コミットメッセージは「システム整理E: 内容」の形式。
3. 実装後、`tests/run_tests.gd`を実機で実行して全件成功を確認し、自動試遊（3シード×13方針）が**4-3の結果と完全一致**することを確認して報告する。
4. 完了後、`CURRENT_SPEC.md`の該当箇所（§5「1杯ずつ接客する客」・場面データの節・ファイル表・テスト数）を実装事実に合わせて更新する依頼を改めて出す（このチャット側で別途対応）。
