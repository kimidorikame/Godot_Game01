# 夜湯（仮題）設計サマリ

サイバーパンク／九龍風スラムの屋台で、一日一鍋のスープを仕込み、客との会話から
事情や好みを読み取りながら料理を出す「会話＋小規模経営」ゲーム。

このドキュメントは Claude Code 向けの実装指示書。前提は **Godot 4 + GDScript**。

---

## 1. 企画核

- 昼：情報収集・仕入れ・仕込み
- 夜：客が来る → 会話する → スープを調整する → 提供する → 客が反応する
- 翌日へ

### 一日一鍋の制約（企画の中心）

- ベーススープは1日1種。全客がその鍋から取り分ける。
- 客ごとに足せるのはトッピング・調味・火加減の微調整だけ。
- 「万人向けの無難な鍋」か「特定客に刺さる尖った鍋」かの賭けが毎日発生する。
- 仕込み直しは不可。これを**状態遷移の一方向性で構造的に保証する**（後述）。

---

## 2. 状態の二層構造

状態は「日をまたいで残る事実」と「イベント列をどこまで再生したか」に分離する。
この分離が設計の要。混ぜると入力待ちの所在が曖昧になりバグる。

### GameState（永続・日をまたいで保持）

```
GameState
  day            : int          # 日数カウント
  money          : int          # 所持金
  reputation     : int          # 評判
  inventory[]    : Ingredient   # 初期具材・調味料・購入した食材
  rumors[]       : Rumor        # スマホで得た情報の断片
  phase          : Phase        # 今どのフェーズか（下記 enum）
  soup           : Soup         # 今日の鍋（base + additions[]）※NEXT_DAYでリセット
  served[]       : ServedRecord # 今夜の提供実績          ※NEXT_DAYでリセット
```

- `money / reputation` は支払いで減り、売上で増える。初期所持金は支払いで消え、
  売上だけが手元に残る（自転車操業感）。
- `soup` と `served[]` は日ごとの使い捨て。**NEXT_DAY でリセットする**。

### EventRunner（使い捨て・使い回す部品）

```
EventRunner
  events[]       : Event
  index          : int
  status         : PLAYING | WAITING_INPUT | DONE
```

- イベント列を `index` で1つずつ進める。
- `status` は **EventRunner が自分で持つ**。GameState には置かない。
  「PREPの入力待ち」と「客Aの接客の入力待ち」を別インスタンスの状態として独立させるため。
- PREP は `EventRunner(prep_events)` を1本回す。
- OPEN は客ごとに `EventRunner(customer_events)` を回す（queue の数だけ）。
  → EventRunner は使い回せる汎用部品。

### status の意味

- `PLAYING`      : セリフ・演出を表示中。自動で進む。
- `WAITING_INPUT`: 選択肢・味付けなどプレイヤー入力待ちで停止。
- `DONE`         : 列を最後まで消化。上位フェーズを次へ進める合図。

---

## 3. 上位フェーズ遷移（前に戻らない一方向）

```
WAKE → PREP → OPEN → CLOSE → NEXT_DAY → （WAKEへ戻る）
```

- 前に戻らない。これで「仕込み直し」「営業中に仕入れへ戻る」抜け道が構造的に消え、
  一日一鍋の取り返しのつかなさが担保される。
- `NEXT_DAY` は短いが独立フェーズとして残す。ここで日と日の隙間の処理をまとめる：
  - 日次リセット（soup / served[] をクリア）
  - オートセーブ
  - 翌日イベント生成（rumors の抽選など）
  - 在庫処理
  - reputation 反映
  - `day += 1` してから WAKE へ
- `phase` は「今どのフェーズか」を GameState が知るために持つ。
  「フェーズ内をどこまで再生したか」は EventRunner.status が持つ。役割を分ける。

Phase enum: `WAKE, PREP, OPEN, CLOSE, NEXT_DAY`

---

## 4. OPEN の内部（客ループ・下位階層）

OPEN だけ別階層にするのは正しい設計。
理由：GREET は「一日のどこにいるか」ではなく「一人の客の接客のどこにいるか」だから。
フラットに並べると客が進むたび上位フローに「戻り」が現れ、一方向の原則が崩れる。

```
OpenController（OPENの間だけ生存）
  customer_queue[] : Customer
  current_customer : Customer
  soup             : GameState.soup を参照（全客で共有）
```

各客の接客は EventRunner で回す、以下の小さな遷移：

```
GREET  → ADJUST → SERVE → REACT →（次の客へ / queueが空ならOPEN終了→CLOSE）
（注文を聞く）（味付け・入力待ち）（提供）（反応・売上確定）
```

- `soup` はループの外（GameState）にあり、全客で共有される。
- チンピラの場所代は客ループを特別扱いしない。その客の REACT の後ろに
  `pay` イベントを1つ挿すだけ。

---

## 5. Event の型（全イベント共通の器）

Day1 も通常日も、フェーズの中身はこの Event の配列として持ち、上から再生する。

```
Event
  type   : "wake" | "phone" | "buy" | "move" | "pay" | "prep"
         | "open" | "customer" | "adjust" | "serve" | "react" | "close"
  text   : 表示するセリフ・状況
  effect : 状態変化（例 { money: -80 }）。無ければ空。
  next   : 次のイベント、または分岐条件
```

- Day1 はこの配列を上から順に再生するだけ（分岐なし）。
- 2日目以降は同じ器のまま、`buy` を自動支払いからプレイヤー選択に差し替える、
  `customer` の中身を抽選にする、といった形で使い回す。
- 初日と通常日で別コードを書かない。

---

## 6. Day1 の位置づけ（自由度を切る日）

**Day1＝生活を教える日 / Day2＝ゲームを始める日** に分ける。

Day1 は自由な買い物なし。自動での支払いのみ。最初から持っている具材・調味料と
購入したベースで営業する。プレイヤーに「このゲームでは何をして生きているのか」を
体験させる、固定イベント連鎖の一本道。

### Day1 のイベント連鎖

```
wake      店内・起床
phone     スマホ（16:42 / 未読3件）※ここで初めて操作可能
  news    地区ニュース：第八码頭で夜間荷役スト
  dm      老張「骨と大根、取っといた。遅れるなよ」
move      市場へ
buy       店主「いつもの。80だ」          money -= 80
move      水場へ
pay       「今月分、払っとけよ」            money -= 50
prep      水を汲む → 仕込み（初期具材＋ベースで鍋完成）
open      屋台を開ける
customer  配達員「いつもの。今日は辛め」→[辛味を入れる]→ 売上 +45
customer  チンピラ 注文→少し食う→「今月分」 money -= 150 → 売上 +40
customer  三人目（通常）                                売上 +55
close     閉店
```

### 所持金の推移（自転車操業感）

開始 300 →（-80 ベース）→ 220 →（-50 水道）→ 170 →（+45 客A）→ 215
→（-150 場所代）→ 65 →（+40 チンピラ）→ 105 →（+55 客C）→ **160**

支払いは出ていくだけ、売上だけが残る。閉店時に手元がいくら増減したかを実感させる。

### 三つの支払いを「トーン」で差別化

金額処理はすべて `money -= x` で同じ。添えるセリフの温度だけで意味を変える
（コードは共通、差はデータ側の text で持つ）。

- **市場**：淡々とした取引。「いつもの。80だ。」
- **水場**：生活の愚痴混じり。「今月分、払っとけよ」「はいはい、分かってる」
- **場所代**：チンピラが先に客として普通に注文して食べ、食い終わってから切り出す
  理不尽。「あ、そうだ。今月分。」→「食い終わってから言うなよ」

### 一人目＝物語に偽装したチュートリアル

「辛味を入れる」一操作を、常連の「いつもの、今日は辛め」という自然な注文として見せる。
この一杯だけ満足度判定を**固定成功値**にしておき、プレイヤーは仕組みを知らないまま
「うまくいった感触」を得る。判定ロジック自体は Day2 から本稼働、Day1 は同じ関数に
固定フラグを渡すだけで共存させる。

### スマホ＝操作解禁の合図

起床後すぐ自由にせず、スマホを見る動作を挟んでから操作可能にする。
Day1 では情報は「読むだけ」。ニュース（第八码頭のスト）は後日の仕入れ・客足への
伏線置き場。DM は市場イベントへの導線。Day2 以降にこの情報を在庫・客へ接続すれば、
同じスマホUIが情報収集ツールへ育つ。

---

## 7. 満足度判定（Day2 以降で本稼働）

- 客の `prefs[]`（好みの tags）と、出した一杯の `tags`（base_tags + additions）の
  一致度を数値化して満足度とする。
- 満足度が売上・reputation・翌日の情報に反映される。
- Day1 では一人目のみ固定成功。判定関数に固定フラグを渡して同じ経路を通す。

### データ構造の骨組み

```
Ingredient : id, name, cost, tags[]        # 辛/温/苦/滋養 …
SoupBase   : id, name, base_tags[]
Soup       : base: SoupBase, additions[]: Ingredient
Customer   : id, name, prefs[], story_flags[], satisfaction_rule
Rumor      : id, text, effect              # 将来、在庫・客足に影響
```

---

## 7.5 夜の核：鍋と椀の二層＋鍋の劣化（目指す姿・最初は作らない）

夜の営業で「何をするゲームか」の核。**これは目標像であり、最初の OPEN では作らない**
（客1人・固定評価から始める。9章 STEP 6〜参照）。ここを記録しておくのは、
トッピングや客評価を後付けしても手戻りしないための「共通の言葉」を先に決めるため。

### 鍋（ベース）と椀（一杯）の二層

- **鍋 = 同じ出汁**。1日1種。全椀に共通する土台。フレーバーの方向性を決める。
  「作っている感」と、後半で客が増えたときに全員をさばくための共通ベース。
- **椀 = 味付けのメイン**。共通の出汁を使いつつ、客ごとに具・トッピング・調味で仕上げる。
  ここでメニューが分岐する（例：キヌガサタケ＋豚軟骨／魚の浮き袋＋季節野菜）。

味は2層で合算する：

```
椀の最終 tags = 鍋の base_tags（共通） + その椀に足した tags（具/トッピング/調味）
```

客評価は**椀の最終 tags** を客の prefs と照合して満足度を出す（7章）。
調整は「椀の tags を増やす」、評価は「椀の tags を読む」。両者が同じ tags を介するので、
どちらを先に実装しても破綻しない。この共通言語を先に決めるのが手戻り防止の要。

### 鍋は時間と提供で劣化する（受動的な対処ゲーム）

鍋は放置すると崩れる。プレイヤーはそれを監視して水・ベースで直し続ける。
鍋（Soup）は tags だけでなく**残量**と**濃さ**という数値を持つ：

```
Soup（目指す姿）
  base_tags[]  … 出汁の方向性（共通）
  残量         … 客に出すと減る。水/ベースを足すと増える
  濃さ         … 時間経過で上がる（煮詰まる）。水で下がる。ベースで上がる
```

崩れ方は2パターン。どちらも「濃さを一定範囲に保つ」ゲームとして統一的に扱える：

- **量的劣化**：客が来る→残量が減る→水を足す（かさ増し）→薄まる→ベースを足す→味が戻る
- **質的劣化**：時間が経つ→煮詰まる→水を足す→味が戻る

### この構想から決まったこと

- **水は「量」で持つ**（個数 ADD_ITEM ではない）。営業中に薄める/かさ増しで継続的に使う
  調整弁だから。→ PREP の水汲みも、この量に足す形になる（STEP 4 では未実装・保留）。
- **椀の味変（トッピング）** と **鍋の味変（煮詰める・薄める・ベース足す）** は別の操作・別の頻度。
  椀＝客ごと（毎回）の細かい仕上げ。鍋＝残量/濃さを保つための、より大きな調整。

### 重要：これはレベル3。最初は作らない

この「鍋の残量・濃さ・時間劣化」は最もリッチな作り込み（＝以前に管理しきれなくなった領域）。
最初の OPEN は **客1人・椀にトッピング1つ・評価は固定成功** の最小から始め、
残量・濃さ・時間劣化・水の量管理は、客ループが動いてから一つずつ足す。

---


## 8. 実装の初手（Claude Code への最初の指示）

いきなり全部作らない。土台から小さく始める。
本番のゲーム画面より先に「開発用 State Viewer」を作る。これがこのプロジェクトの
最重要方針。理由は下の 8.1 を参照。

### 実装済み

- **GameState**（autoload シングルトン）は実装済み。事実のみを持ち、進行度
  （status / index / customer_step の類）は持たない。金額は apply_money(delta) を
  唯一の入口に通す。日次リセットは reset_for_new_day()（soup / served のみクリア）。

### 順序

1. **開発用 State Viewer の表示部を作る**：今ある GameState の
   `day_count / money / reputation / inventory / phase / soup / served` を
   画面に映すだけの最小版。まだ本番のゲーム画面ではない。
2. **デバッグボタンを置く**（この時点では押せる状態だけでよい）：
   - EventRunner 操作：`[次のEvent] [入力完了]`
   - フェーズ操作：`[次のPhase] / [OPENへ] [CLOSEへ] [Day +1]`
3. **EventRunner を作る**：events[] を index で進め、status(PLAYING /
   WAITING_INPUT / DONE) を自分で持つ最小実装。`[次のEvent]` ボタンから叩けるように。
4. **検証用の最小 Day1 イベント列を数個**流し、Viewer 上で
   「入力 → 状態変化」（例 money: 100 → 95, event_index: 2 → 3）が
   目で追えることを確認する。EventRunner は Viewer を検証装置として並走させて作る。
5. 上位フェーズ遷移（FlowController：WAKE→PREP→OPEN→CLOSE→NEXT_DAY・一方向）を載せ、
   フェーズ操作ボタンから手で叩けるようにする。
6. OPEN の OpenController と客ループ（EventRunner の使い回し）を載せる。
7. Day1 の台本（本ドキュメント6章）を Event データとして流し込む。
8. ここまで Viewer で検証できてから、本番のゲーム画面（セリフ表示・味付けUI）を作る。
9. Day2 以降：buy を選択制に、customer を抽選に、満足度判定を本稼働。

### 8.1 なぜ State Viewer を先に作るのか

「AI に実装させると内部で何が動いているか分からない」問題に直接効くから。
イベントを1つ実行するたびに状態の変化（water: 0→10 / money: 100→95 /
event_index: 2→3 など）が画面に出れば、コードを全部読まずとも「入力 → 状態変化」の
因果が追える。EventRunner や FlowController を実装したそばから、本番UIを作らずに
デバッグボタンで手叩き検証できる。Viewer は「作ってから確認する」ものではなく
「作りながら確認する」ための土台。

### Godot 実装メモ

- EventRunner はノードにしてもプレーンな `RefCounted` クラスにしてもよい。
  接客ごとに生成・破棄する使い捨て部品なので、`RefCounted` が素直。
- GameState は単一の autoload（シングルトン）に置くと日またぎで保持しやすい。
- フェーズ遷移は state machine ノード、または enum + match で素朴に。
  フェーズ数が少ないので過剰な framework は不要。
- セリフ表示・選択肢UIは EventRunner の status を見て描画を切り替える
  （WAITING_INPUT のとき入力を受け付ける）。

---

## 9. ビルド順（この順で刻む）

全体を一気に作らない。下の順で1STEPずつ、各STEPの最後に「止まって理解する」。
State基盤 → DebugPanel → WAKE → PREP → OPEN一人 → OPEN三人 → CLOSE → NEXT_DAY
→ Day2分岐 → 本番UI。

### STEP 1：State基盤（実装対象を4つに絞る）
- GameState（実装済み）/ FlowController / EventRunner / DebugPanel の4つだけ。
- OPEN内部の客処理・市場・料理・シナリオはまだ作らない。
- Claude Code へはまず **Plan（最小変更案）だけ**出させ、コードは変更させない。
  無関係なリファクタリング・追加システムは禁止。Plan確認後に実装。

### STEP 1.5：Event 型を仮決めする（早めに）
- EventRunner が処理する対象なので、EventRunner 実装と同時に型を決める。
- 最初はこの4つだけで WAKE も PREP も組める：
  `TEXT / PAY / ADD_ITEM / WAIT_INPUT`
- 営業用（`CUSTOMER_ENTER / ADJUST_SOUP / SERVE / CUSTOMER_REACT`）は
  OPEN に入る STEP 6 で足す。後付けでよい。
- **シナリオデータと処理を分離する**（『夜湯』で特に重要・確定事項）。
  Event はデータ（例 `{ type: PAY, amount: 20 }`）、処理はそれを受けて
  `GameState.apply_money(-20)` を呼ぶだけ。処理をデータ側に埋め込まない。

### STEP 2：開発用 DebugPanel（本番UIは作らない）
- 8章の State Viewer。GameState と EventRunner.status を映し、デバッグボタンで叩く。
- 白背景・Label・Button・DebugPanel で十分。絵もシナリオも無し。

### STEP 3：WAKE だけ作る
- Day1 の wake → phone → 「準備へ」の数イベントだけ。WAKE→PREP の遷移を確認。

### STEP 4：PREP を作る
- 市場→ベース購入→水場→使用料→水汲み→仕込み→OPENへ、を全部 Event で流す。
- 「PREP という巨大なコード」を作らない。TEXT / PAY / ADD_ITEM の並びで表現。

### STEP 5：PREP まで完全に理解する（一度止まる）
- 「WAKEのeventsを処理→DONEでFlowControllerがPREPへ→PAYでmoney減→
  ADD_ITEMでinventory増→最後のEvent後にOPENへ」を**自分の言葉で説明できる**まで。
- できなければ Claude Code に「この操作で、どのファイルのどの処理が呼ばれ、
  どの状態変数が変わり、次にどの処理へ進むか」を説明させる。これが「理解した」の基準。

### STEP 6：OPEN は客1人だけ
- queue = [delivery_man] のみ。GREET→ADJUST→SERVE→REACT を実装。
- ADJUST で status=WAITING_INPUT で止まり、[卵][生姜][提供]等の入力を受ける。

### STEP 7：客3人にする
- queue = [delivery_man, thug, normal_customer]。3人が順に回り、
  queue が空 → OPEN終了 → CLOSE を確認。

### STEP 8：pay イベントを差し込む
- チンピラの REACT 後ろに `PAY_PROTECTION_MONEY` を1つ差すだけ。
- **チンピラ専用 State を作らない**（`THUG_PAYMENT_STATE` 等を増やさない）。
  単なる Event として表現する＝確定事項どおり。

### STEP 9：CLOSE → NEXT_DAY
- CLOSE：売上表示→精算→本日の結果。
- NEXT_DAY：day_count += 1、reset_for_new_day()（soup / served クリア）、
  current_customer = null 等。→ WAKE へ。これで一日完成。

### STEP 10：Day1 を一周して全状態を説明できるか（一度止まる）
- WAKE→PREP→OPEN(客1→2→3)→CLOSE→NEXT_DAY→WAKE の全状態を自分で説明できること。
- できてから Day2 へ。

### Day2 は「分岐テスト」にする（新システムを足さない）
- 同じ EventRunner で分岐が処理できるかだけ試す。
- 例：Day1 で SET_FLAG した `granny_helped` を見て `if 〜 else` で Event を出し分ける。
- これが動けば基盤が固まったと判断。

### まだ作らないもの（この段階で手を出さない）
7日分の本シナリオ / 完成版市場 / レシピシステム / スマホ画面 / 立ち絵 /
本番UI / セーブの完全設計 / 好感度 / 評判の詳細 / 料理バランス / 複雑な分岐。
reputation・rumors は状態として予約するだけでよく、まだ使わない。

### 本番UIは最後
- Day1 が完全に状態遷移するようになってから、
  WAKE→自室UI / PREP→市場・水場UI / OPEN→屋台UI / CLOSE→精算UI に置き換える。
- この順なら「UIのせいで動かない」のか「状態遷移のせいで動かない」のかを切り分けられる。

---

## 設計上の確定事項（変更しないこと）

- 状態は GameState（永続）と EventRunner（使い捨て）の二層。status は EventRunner 側。
- 上位フェーズは一方向。戻らない。
- OPEN は別階層。客ループは下位に隔離する。
- 全イベントは共通の Event 型。Day1 と通常日で別コードを書かない。
- Event はシナリオデータ、処理はそれを受ける側。処理をデータに埋め込まない
  （例：`{type: PAY, amount: 20}` を受けて apply_money(-20) を呼ぶ）。
- soup は全客で共有。NEXT_DAY でリセット。
- 本番のゲーム画面より先に開発用 State Viewer を作る。EventRunner 等は
  Viewer を検証装置として並走させながら実装する（8章・8.1参照）。
