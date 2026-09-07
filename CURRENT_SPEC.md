# 夜湯（仮題）現状仕様書

このドキュメントは **「今どこまで実装され、どう動いているか」の事実の記録**。
DESIGN.md が「これから作る指示書」なのに対し、こちらは「現在の到達点」を映す。
実装済みコードを正とする。最終更新時点で Day1 の状態遷移が通しで動き、
**夜の核（会話から好みを読む → 3枠に味と具を選ぶ → 段階評価 → 反応）まで実装済み**。
鍋の残量・水・在庫の消費・メニュー・廃棄はまだ無い。

---

## 0. 全体像（一言で）

サイバーパンク／九龍風スラムの屋台で一日一鍋のスープを営む会話＋小規模経営ゲーム。
現状は **本番UI・絵なし**。開発用の DebugPanel（State Viewer）上で、状態を見ながら
ボタンで手動進行できる段階。Day1（起床→仕込み→営業→閉店→翌日）が状態遷移として
通しで動く。

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

---

## 2. GameState（日をまたいで残る実行中の事実）

ここでいう「残る」はゲーム実行中の日またぎを指す。ディスクへのセーブは未実装。

```
day_count   : int   = 1     # 何日目か。NEXT_DAY で +1
money       : int   = 300   # 所持金。支払いで減り売上で増える
reputation  : int   = 0     # 評判（予約のみ・未使用）
inventory   : Array = []    # 具材・調味料の id 文字列（型は将来 Ingredient へ）
rumors      : Array = []    # スマホ情報（予約のみ・未使用）
phase       : Phase = WAKE  # 今どのフェーズか
soup        : null          # 今日の鍋（未実装・仕込み前は null）※日次リセット対象
served      : Array = []    # 今夜の提供実績 ※日次リセット対象
```

### 状態変更の入口（受け側はここだけを通す）
- `apply_money(delta)` … 支払いも売上も全部ここ。差はデータ側の text（トーン）
- `add_inventory(item, count)` … 在庫を足す唯一の入口
- `remove_inventory(item, count)` … 在庫を減らす（仕込みでの消費）
- `record_served(record)` … 提供実績を1件記録
- `reset_for_new_day()` … soup と served だけクリア（money 等は残す）
- `advance_day()` … day_count +1
- `is_collection_day()` … 今日が徴収日か。現状 `day_count == 1`（将来 [1,7,14] 等へ）

---

## 3. フェーズ遷移（FlowController）

```
WAKE → PREP → OPEN → CLOSE → NEXT_DAY →（WAKE へ折り返し）
```

- **一方向。前に戻らない。** これが「一日一鍋・仕込み直し不可」を構造で保証する。
- NEXT_DAY→WAKE の折り返しで `reset_for_new_day()` ＋ `advance_day()`。
- `advance_phase()` でフェーズを1つ進める。`[次のPhase]` ボタンから叩く。

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
| PAY | 支払い | `apply_money(-amount)` |
| ADD_ITEM | 在庫追加 | `add_inventory(item, amount)` |
| REMOVE_ITEM | 在庫消費 | `remove_inventory(item, amount)` |
| SET_SOUP | 共有鍋の作成 | `set_soup(base_id, tags)` |
| GREET / SERVE | 表示のみ（接客） | なし |
| ADJUST | 具材の選択（入力待ち） | `options` を持つので EventRunner が停止。<br>椀への反映は受け側（選択肢ボタン） |
| REACT | 判定＋売上確定 | `judge_bowl()` で4段階判定 ＋ `apply_money(+sale)` ＋ `record_served()` |

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

- ADJUST は `options`（7つの具材）を持つ Event。`options` を持つ Event は
  EventRunner が入力待ちとして扱う（個数は関知しない）。
- 具材ボタンを押すと `current_bowl.additions` に足すだけで、**runner は進まない**。
  進むのは `[入力完了]`（提供）を押したとき。「選ぶ」と「進む」を分離している。
- 上限3つ。**重複可**（同じ具材を複数入れられる。将来「強さ」を持たせる余地）。
- 3つ埋まると具材ボタンを無効化。3つ未満でも提供でき、0個なら具なし。

### 判定（REACT）— 一致数＋favorite で4段階

```
一致数 = 3枠の中身のtags と 客の wanted_tags の一致数
        ※鍋(soup)のtags は数えない
        ※wanted_tags 側をループして数えるので、具材を重複させても
          同じtagは1回しか数えられない

  0個 → BAD / 1個 → OK / 2個以上 → GOOD
  favorite（好物の具材id）が入っていれば1段上げる（一致0には効かない）
  → 1個+fav = GOOD / 2個以上+fav = GREAT
```

- 判定は `OpenController.judge_bowl(wanted_tags, favorite)`。結果・一致数・
  favorite の有無・反応のランダム番号を `current_bowl` に記録する（客が替われば消える）。
- 反応 text は Event の `reactions` 辞書（`{BAD/OK/GOOD/GREAT: [2種]}`）から
  結果で引く。**Event データは書き換えない**（受け側が都度読んで選ぶ）。
- 計器盤では反応行の頭に `【GOOD】` のように結果を付けて表示する（データ側には入れない）。

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

### Day1 の3人（wanted_tags と favorite）

| 客 | wanted_tags | favorite（仮） | 好みの伝え方 |
|----|------------|--------------|------------|
| delivery_man | `HOT` + `POWER` | tofu | 明言する（今日は辛くしてくれ） |
| thug | `MELLOW` + `GENTLE` | meat_ball | 遠回しに漏らす（口当たりがまろくなるやつ） |
| granny | `SAVORY` + `FILLING` | offal | 比喩と記憶で語る（薬棚の匂い、腹の底へ残る） |

favorite は本来レア食材（たまにしか売っていない／高い）にする予定だが、
現状は検証用に Day1 の在庫から仮に割り当てている。

---

## 6. Day1 の内容（実装済みの台本）

### WAKE
起床 TEXT → スマホ（WAIT_INPUT で停止）→「準備へ」TEXT

### PREP（水道代は徴収日のみ・水汲みは毎日）
```
食肉売場へ来た（TEXT）
ベース代 -80（PAY）
ベース受け取り（ADD_ITEM soup_base）
水を汲む（TEXT・仮。実際の水入手は未実装）
水道代 -50（PAY）※徴収日のみ
仕込み（REMOVE_ITEM soup_base）
```

### OPEN（客3人）
```
queue = [delivery_man, thug, normal_customer]
各客: GREET → ADJUST（素通し）→ SERVE → REACT（売上確定）
売上: delivery_man +45 / thug +40 / normal_customer +55
thug のみ REACT 後に場所代 -150（PAY）※徴収日のみ
```

### CLOSE
閉店の締めくくり TEXT ×3（状態は動かさない）

### NEXT_DAY
日次リセット（soup / served クリア）＋ day_count +1 → WAKE へ

### 所持金の推移
- **Day1（徴収日）:** 300 →(-80 -50)→ 170 →(+45 +40 -150 +55)→ **160**
- **Day2（非徴収日）:** 160 →(-80)→ 80 →(+45 +40 +55)→ **220**
  ※場所代・水道代とも徴収日でないため出ていかない

### 三つの支払いのトーン（金額処理は共通、text だけで差別化）
- 市場 -80: 淡々「いつもの。80だ」
- 水道 -50: 生活の愚痴「今月分、払っとけよ」（徴収日のみ）
- 場所代 -150: 理不尽「あ、そうだ。今月分。」（徴収日のみ）

---

## 7. 条件別Event列生成（Day2テスト・確認済み）

`GameState.is_collection_day()`（現状 `day_count == 1`）をデータ関数が読み、
EventRunnerへ渡す前に含めるEventを出し分ける。EventRunner自体は分岐せず、
生成済みの平坦なEvent列を同じ方法で再生する。

- 場所代（`_customer_extra_events`）: thug かつ徴収日のときだけ PAY を差す
- 水道代（`prep_events`）: 徴収日のときだけ PAY を含める（水汲み TEXT は毎日）
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
| `scripts/ingredients.gd` | 具材マスタ（id → tags） |
| `scripts/day1_events.gd` | Day1 の Event データ（wake/prep/customer/close）+ 分岐 |
| `scripts/debug_panel.gd` | State Viewer 表示 ＋ 受け側（_apply_event） |
| `scenes/debug_panel.tscn` | DebugPanel のシーン |

※ Graybox（graybox_open）は STEP 17.5 の検証後に削除した。
具材が増えて計器盤で操作しきれなくなった段階で作り直す。

---

## 9. まだ無いもの（今後のテーマ）

### A. 夜の核の残り
- **メニュー・レシピ**（見られるようにする。指針であって縛りではない）
- **廃棄**（作った椀を捨てる。served に記録するが廃棄フラグを残す）
- **在庫の消費**（具材を使うと減る。市場で買い足す。favorite をレア食材にする）
- 味を2つ重ねるときの成立表

### B. 鍋（7.5 の管理要素）
- 残量・濃さ・時間劣化・水の量（現状 soup は base_id と tags のみ）
- 評判 → 翌日の客数 → 鍋の配分、という連鎖

### C. データの外部化
- 会話・客・具材をコードから別ファイルへ（データ形が安定してから）

### D. 本番UI（見た目・一番最後）
- 絵・セリフ表示・屋台画面
- 選択肢は調味料と具材で表示を分ける（種類が増えると1列では探しにくい）

### その他
- reputation / rumors は状態として予約済み・未使用
- 7日分のシナリオ（現状は Day1 の3人ぶんのみ・仮文言）
- 提供後の会話（現状は一口目の感想で終わり、一日が短く感じる）
- セーブ

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

```
[済] 最小データ形を決める（Soup / Bowl / Ingredient / Customer）
[済] PREPで共有鍋を作る（SET_SOUP）
[済] 辛味を入れる一操作 → 二択 → 5つの味から1つ
[済] 3枠で味と具を選ぶ（選ぶと進むを分離・上限3・重複可）
[済] 一致数による段階評価（BAD / OK / GOOD）
[済] favorite でクリティカル（GREAT）
```

**次の候補**（順序は未定）：
- 提供後の会話を厚くする（触って分かった課題。一日が短く感じる）
- メニュー・レシピ（見られるようにする）
- 在庫の消費と市場での買い足し（favorite をレア食材にする）
- 廃棄
- 7日分の会話を書く

鍋（残量・濃さ・水）は、上の縦切りが面白いと確認できてから載せる。
完成UI は最後。Graybox は具材が増えて計器盤で操作しきれなくなった段階で作り直す。
