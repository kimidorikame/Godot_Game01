# 夜湯（仮題）現状仕様書

このドキュメントは **「今どこまで実装され、どう動いているか」の事実の記録**。
DESIGN.md が「これから作る指示書」なのに対し、こちらは「現在の到達点」を映す。
実装済みコードを正とする。最終更新時点で Day1 の状態遷移プロトタイプが通しで動き、
Day2 の徴収日条件による Event 列生成まで確認済み。料理の選択・判定はまだ未実装。

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
| GREET / ADJUST / SERVE | 表示のみ（接客） | なし（ADJUST は現状ダミー素通し） |
| REACT | 売上確定 | `apply_money(+sale)` ＋ `record_served()` |

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
| `scripts/open_controller.gd` | OPEN の客キュー管理 |
| `scripts/day1_events.gd` | Day1 の Event データ（wake/prep/customer/close）+ 分岐 |
| `scripts/debug_panel.gd` | State Viewer 表示 ＋ 受け側（_apply_event） |
| `scenes/debug_panel.tscn` | DebugPanel のシーン |

---

## 9. まだ無いもの（今後のテーマ）

### A. 夜の核（次に検証する縦切り）
- 会話から好みを知る→味付けを選ぶ→椀のtagsが変わる→GOOD/MISS判定→反応
- 鍋と椀の二層、tags による味の表現（DESIGN.md 7.5 / 9.5）
- 水量・鍋の残量・濃さ・時間劣化は、縦切り確認後に必要なら載せる管理圧力
  （現状 soup は null、水は TEXT のみ）

### B. データの外部化（作りやすさのインフラ）
- 会話・客・具材・調味料をコードから別ファイルへ
- 現状は day1_events.gd にセリフ等を直書き
- データ形が固まる前には行わない。少なくとも2種類のIngredientで試した後、
  安定した一種類から段階的に外部化する。

### C. 選択システム（自由度）
- 具材購入、クズ野菜漁り、味付けの選択（現状 PREP・ADJUST は一本道/素通し）
- WAIT_INPUT で待って選ばせる仕組みの応用

### D. 本番UI（見た目・一番最後）
- 絵・セリフ表示・屋台画面。動く中身ができてから被せる
- 完成UIとは別に、客一人分の操作感を確認するGrayboxはDESIGN.md STEP 17で作る

### その他
- reputation / rumors は状態として予約済み・未使用
- 7日分のシナリオ、セーブ、ボリューム（1日の密度）

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

## 11. 次の開発方針（未実装）

現在の実装対象は DESIGN.md 9.5「ビルド順・第2フェーズ（STEP 11〜18）」。
最小の縦切りを次の順で通す。

```
最小データ形と寿命を決める
→ PREPで共有鍋を作る
→ Day1で辛味を入れる一操作
→ Day2で二択
→ GOOD / MISS判定
→ 反応・ServedRecord
→ 客一人のGraybox
→ 安定したデータだけ外部化
```

水量・残量・濃さ・時間劣化、完成UI、7日分のシナリオは、この縦切りで
面白さと操作感を確認するまで作らない。
