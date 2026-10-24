# PlaySession の使い方（UI準備A 完了時点）　2026-10-24

対象：本番UI（`UI_A` の B 以降）を作る人。DebugPanel は検証用に残し、本番UIは**橋を使わず `PlaySession` を直接使う**。
実装：[scripts/play_session.gd](../scripts/play_session.gd)。ゲームの挙動・数値・乱数の消費順・保存の形式は UI準備A で一切変えていない（純粋な移動と、読むだけの問いの追加）。

## 0. 基本の約束

- 画面は「**操作を呼ぶ**」「**問いを読む**」「**`changed` を受けて全体を描き直す**」だけ。ゲームの判定は画面に書かない。
- ボタンの有効・無効は**問い**（`can_*` など）で決める。問いは「ゲームの状態として押せるか」だけを返す。**スマホを開いている間の無効化、鍋⇄トッピングの表示の切り替え、タブなど「表示だけの状態」は UI が持つ**（`PlaySession` は持たない）。
- 返す値は文面ではなく**値と理由のコード**。文の言い回し・配置は UI が決める（例外：`format_day_summary` と `Result.format_*` は既存の文面を返す）。
- `changed` の回数に意味は無い（1回の操作で複数回出てよい）。出るたびに全体を描き直す。

## 1. 起動と接続

```gdscript
var session := PlaySession.new()   # FlowController は中で作る。シーンの子ノードにする（autoload にはしない）
add_child(session)
session.changed.connect(_redraw)                  # 状態が変わった → 全体を描き直す
session.phase_entering.connect(_on_phase_entering) # フェーズの列を組む直前 → 表示だけの状態（スマホの開閉など）を捨てる
session.start()                                   # 1回だけ。セーブの読み込み・初期在庫・最初のフェーズの列
# 描き直しの最後に（会話ログ・既読のため）：
session.record_visible_event()
```

- 進行：`session.flow.advance_phase()` が [次のPhase]（WAKE→PREP→OPEN→CLOSE→NEXT_DAY→WAKE。最終日の翌は RESULT）。押せるかは `session.flow.is_advance_blocked()`（true なら押せない）。フェーズの列の組み直し・日の終わりの集計（日次ログ・評判の確定）は `PlaySession` が自動で行う。
- `record_visible_event()`：見えている行を会話ログ（`TalkLog`）と既読（`ReadState`）へ記録する（同じ行は1回だけ）。**描き直しの最後に呼ぶ**（DebugPanel は `_refresh` の末尾で呼んでいる）。`skip_read()` の中では自分で呼ぶ。

## 2. シグナル

| シグナル | いつ出るか | UIがすること |
|---|---|---|
| `changed()` | 各操作の末尾。runner の再生位置が動いたとき（Event 列の差し替えなど）にも出る | 問いを読み直して全体を描き直す |
| `phase_entering(phase:int)` | フェーズごとの Event 列を組む**直前**（起動時の最初の組み立てでも出る） | 表示だけの状態（スマホの開閉・タブなど）を捨てる |

`session.flow`（`FlowController`）の `phase_changed`・`runner_updated`・`day_ending`・`game_restarted` は `PlaySession` が自分で受ける。UI は結線しない。

## 3. 操作（本番UIが呼ぶ）

「押せる条件」は、押す前に読む問い。条件を満たさないときに呼ぶと、何も起きないか、従来どおりの防御的な扱いになる（UI が無効にしておく約束）。

### 進行・会話

| 関数 | 何が起きるか | 押せる条件 |
|---|---|---|
| `next_event()` | 会話を1つ進める。新しく現在になった Event の効果（支払い・在庫・鍋・提供など）を受ける | `can_next_event()` |
| `complete_input()` | 入力待ちを解除して先へ進む（椀の提供・選択後の続きなど）。モブの団体は最初の1回で確認へ進む | `can_complete_input()` |
| `choose_story_option(choice_id, option_id)` | 店主の距離感の選択。来店記録へ残し、締めを組んで先へ進む | `current_choices()` が空でない |
| `skip_read() -> int` | 既読スキップ。止まる条件（未読の行・入力待ち・客やフェーズの切り替わり・200歩）まで `next_event` を繰り返す。進めた歩数を返す | `can_skip_step()` |

### 市場・仕込み

| 関数 | 何が起きるか | 押せる条件 |
|---|---|---|
| `select_stall(id)` | 店へ入る（`market_shop` が id になる） | `market_stalls()` の `enabled` |
| `buy_item(shop, id)` | 店の商品を1回分買う（所持金・在庫・帳簿）。足りなければ何もしない | `shop_view(shop)` の `affordable` |
| `leave_shop()` | 店から市場のトップへ戻る | 店の中にいる |
| `choose_prep_tier(tier_id)` | 仕込みの段階を買う（小・中・大）。残りの仕込みの列に差し替わる | `prep_tiers()` の `affordable` |
| `exit_market() -> bool` | 市場を出る。徴収日は水道代を払ってから先へ進む。払えずゲームオーバーなら false | `can_exit_market()` |

### 開店：椀・提供・断る

| 関数 | 何が起きるか | 押せる条件 |
|---|---|---|
| `select_ingredient(id, damaged=false)` | 具材・味付けを椀に足す（在庫を引く。モブの団体は確定まで引かない） | `ingredient_options()` の `can_pick` |
| `discard_bowl()` | 椀を捨てて作り直す（客は進まない） | `can_discard()` |
| `decline_customer()` | 名前あり客・配達員を断る（未提供として記録される） | `can_decline()` |
| `reask()` / `clear_reask()` | 聞き直し（頼みの台詞を再表示する対象にする／消す）。何も変えない | `can_reask()` |
| `apply_recipe(ingredients)` | 「いつもの」・保存レシピを椀に入れる（具材ボタンを順に押したのと同じ） | `recipe_adjust_buttons()` の `can_apply` |
| `start_recipe_save()` → `select_recipe_slot(slot)` → `select_recipe_name(name)` / `cancel_recipe_save()` | 提供後に椀をレシピに保存する（段階：ボタン待ち→枠→名前） | `recipe_save_view()["can_save"]` |
| `group_serve(n, ordered)` / `group_decline(ordered)` / `group_retry(achievable, ordered)` | モブの団体の確認：N人分を提供／注文を断る／残りに別の具材で挑戦 | `mob_group_choice()`（`can_serve`・`can_retry`） |

### 開店：鍋・閉店

| 関数 | 何が起きるか | 押せる条件 |
|---|---|---|
| `add_water()` / `add_dashi()` | 水（残量+2・濃さ-2）／濃縮だし（濃さ+2）を足す | `pot_view()` の `can_add_water`／`can_add_dashi` |
| `resume_after_shortage()` | 鍋が尽きて保留中の客に「営業を続ける」。保留中の提供をここで行う | `is_shortage_pending()` |
| `close_shop()` | 閉店（早仕舞い）。保留中の客は出せなかった扱いでCLOSEへ飛ぶ。未払いの場所代は先に請求 | `can_close_now()` |
| `open_pot()` / `close_pot()` | **DebugPanel 用の鍋モード**。`pot_open` が true の間は `can_next_event()` が false になり会話が止まる | `can_touch_pot()` |

本番UIでは**鍋タブは表示だけ**とし、`open_pot()` は呼ばない（会話が止まるため）。水・だしの鍵（`pot_locked_until_water()`／`pot_locked_until_dashi()`。鍋モードに入った時点で鍋が空／濃さ0なら、足すまで戻れない）の使い方は B で決める。`add_water`／`add_dashi` は `pot_open` なしでも呼べる。

### 閉店・日・周回

| 関数 | 何が起きるか | 押せる条件 |
|---|---|---|
| `contribute_fund(amount)` | 修繕基金に積む（選んだ対象へ） | `fund_view()["steps"]` の `can` |
| `select_fund_target(id)` | 積む先を切り替える（実行時のみ・保存しない） | `fund_view()["targets"]` の `repaired`／`locked` が false |
| `retry()` | 同じ朝から（直近の朝）。GAME_OVER の仮ボタン | `exits()["can_retry"]` |
| `last_morning()` | 直近（最終日）の朝からやり直す | `exits()["can_last_morning"]` |
| `run_again()` | Day1の朝から。GAME_OVER で Day1 の記録が無いときは新しい周と同じ動作 | `exits()["can_run_again"]` |
| `new_run()` | 新しい周（全部初期化してDay1のWAKEから） | `exits()["can_new_run"]` |
| `continue_game()` | 起動時に読めたセーブの朝へ戻る | `exits()["can_continue"]` |
| `retry_from_morning(day=-1) -> bool` | 指定した日（既定は直近）の朝へ戻す。戻れなければ false | 朝の記録がある |

内部用（UI は通常呼ばない）：`pay_or_game_over(amount, category)`・`game_over(reason)`・`on_day_ending()`・`set_runner_for_phase(phase)`・`on_phase_changed(phase)`・`flush_visit_tally()` など。

## 4. 読む問い（返す値の形）

| 関数 | 返す値 |
|---|---|
| `day_info()` | `{day, phase, phase_name, slot_name, slot_index, customer_index, money, reputation}`（時間帯は開店中のみ） |
| `budget()` | `{money, reserved, usable}`（残金／確保／使える） |
| `current_line()` | `{type, speaker（話し手の客id・地の文は ""）, text, part}`。REACT は判定後の反応文 |
| `is_waiting_input()` | bool（入力待ちか） |
| `current_choices()` | `{choice_id, options[{id,label}]}`。選択中でなければ `{}` |
| `can_next_event()` / `can_complete_input()` / `can_skip_step()` | bool |
| `can_touch_pot()` / `can_discard()` / `can_decline()` / `can_reask()` / `can_close_now()` | bool |
| `is_shortage_pending()` | bool（鍋が尽きて「続ける／閉店」の選択待ちの客がいる） |
| `pot_view()` | `{exists, remaining, capacity, strength, strength_min, strength_max, can_add_water, water_doses_left, can_add_dashi, dashi_units, can_touch, pot_open, shortage_pending, locked_until_water, locked_until_dashi}`（鍋が無ければ `{exists:false}`） |
| `order_card_view()` | `{customer, base[タグ], today[タグ], label}`。名前あり客のADJUST中のみ |
| `bowl_view()` | `{customer, additions[品目id], additions_damaged[additions と同じ並びで傷んだ側か], max_additions, used_spoiled, result, discard_count, tags, addition_tags}` |
| `ingredient_options()` | `[{id, label, damaged, kind("seasoning"/"topping"), tags, fresh, damaged_stock, count, can_pick}]`（ADJUST中のみ） |
| `sale_hint()` | `{blockers[コード: NO_FLAVOR/NO_TOPPING/STRENGTH_ZERO/SHORT_SERVINGS], penalties[{code:"STRENGTH_EXTREME", value}/{code:"SPOILED"}]}` |
| `current_servings()` / `react_for_now()` / `adjust_customer_id()` | 今の注文の杯数／今のREACT Event／聞き直し対象の客id |
| `mob_group_choice()` | `{ordered, achievable, remaining, recipe_number, can_serve, can_retry}`（確認中でなければ `{}`） |
| `recipe_adjust_buttons()` | `[{kind("usual"/"saved"), name, ingredients, missing, can_apply}]`（椀が空のADJUSTのみ） |
| `recipe_save_view()` | `{can_save, stage("" /"slot"/"name"), ingredients, slots[{index,name,selectable}], names[]}`（保存できなければ `{can_save:false}`） |
| `market_stalls()` | `[{id, label, enabled}]`（市場にいる間のみ） |
| `shop_view(shop)` | `[{id, item, label, price, count, unit_price, fresh, damaged, affordable, kind}]` |
| `prep_tiers()` | `[{id, label, servings, price, affordable}]` |
| `prep_tier_paid()` / `today_base()` | 鍋の素を買ったか／`{paid, tier_id, label, servings, scraps}`（クズ野菜ベースの日は scraps=true・支払い無し） |
| `can_exit_market()` / `is_in_market()` / `is_in_prep_tier()` | bool |
| `tonight_result()` | `{ordered_cups, served_cups, unserved_cups, grades（評価の内訳）, sales}`（閉店の今夜の結果） |
| `previous_day_record()` | 前日の日次ログ1日分（`on_day_ending` が作る log_entry と同じキー）。Day1の朝は `{}` |
| `morning_cost()` | 今朝払った運営費 |
| `fund_view()` | `{available, complete, targets[{id,label,paid,price,repaired,locked,selected}], selected, paid_tonight, nightly_max, max_contribution, steps[{amount,can}], notice, reserve}`（積み立てが出ない間は `{available:false}`） |
| `result_view()` | `{summary（Result.summarize）, goals（Result.judge_goals。完走・標準・挑戦・料理・常連）}` |
| `exits()` | `{available, can_retry, can_last_morning, can_run_again, run_again_is_new_run, can_new_run, can_continue}` |
| `game_over_info()` | `{available, kind（"daily_cost"／"water"／"rent"／"kit"／""）, amount, money, day, phase}`。GAME_OVER で、払えなかった支払いの記録があるときだけ available（UI準備B④で追加。表示だけ） |
| `phone_news()` | `[{day, is_today, news[{headline,body[],provisional}], dm[{from,text,provisional}], events[{lines[],provisional}]}]`（新しい日が上・今日と過ぎた日だけ） |
| `phone_recipes()` | `{slots[{index,name,tags,ingredients}], usual[{customer,ingredients}]}`（空き枠は name が ""） |
| `talk_log_entries()` | `[{day, kind, speaker, text}]`（今日の会話ログ。コピー） |

## 5. 読んでよい状態（変数）

`open`（客キュー `OpenController`）・`pot_open`・`pending_shortage_ev`・`market_shop`・`market_visited_water`・`scraps_base`・`pending_group_choice`・`mob_recipe_number`・`recipe_save_stage`・`fund_target`・`fund_notice`・`reask_customer_id`／`reask_lines`・`last_day_summary_text`・`log_*`（その日の日次ログのカウンタ）・`save_armed`・`pending_continue`。**直接書かない**（操作を使う）。

## 6. 画面ごとの対応表（どの項目をどの問いで読むか）

### 開店：鍋

| 項目 | 読むもの |
|---|---|
| 残り杯数・鍋の上限・濃さ | `pot_view()` の `remaining`・`capacity`・`strength`（`strength_min`／`strength_max`） |
| 水を足せるか・今夜あと何回 | `pot_view()` の `can_add_water`・`water_doses_left` |
| だしを足せるか・残り数 | `pot_view()` の `can_add_dashi`・`dashi_units` |
| 鍋を触れるか | `can_touch_pot()`（`pot_view()["can_touch"]`） |
| 鍋が尽きて保留中／続ける・閉店 | `is_shortage_pending()`・`resume_after_shortage()`・`can_close_now()`・`close_shop()` |
| 水・だしの鍵 | `pot_view()` の `locked_until_water`／`locked_until_dashi`（使い方は B で決める） |

### 開店：トッピング

| 項目 | 読むもの |
|---|---|
| 注文カード（いつもの／今日） | `order_card_view()` |
| 椀の中身 | `bowl_view()`（品目idと、品目ごとの傷んだ側の印 `additions_damaged`。UI準備B③で追加。表示だけ） |
| 提供できない理由・減点の理由（コード） | `sale_hint()` |
| 選べる品目（id・調味料か具か・タグ・新鮮／傷んだ在庫） | `ingredient_options()` |
| 提供・廃棄・断る・聞き直す・いつもの・保存が押せるか | `can_complete_input()`・`can_discard()`・`can_decline()`・`can_reask()`・`recipe_adjust_buttons()`・`recipe_save_view()` |
| モブの団体の確認 | `mob_group_choice()` |
| 話している文・反応 | `current_line()` |

### 朝

| 項目 | 読むもの |
|---|---|
| 前日成績 | `previous_day_record()`（日次ログと同じキー）。既存の文面は `format_day_summary(record)` |
| 今朝払った運営費 | `morning_cost()` |
| 日・所持金・評判・予算 | `day_info()`・`budget()` |
| 語り・次へ | `current_line()`・`can_next_event()` |

### 市場・購入

| 項目 | 読むもの |
|---|---|
| 店の一覧と開いているか | `market_stalls()` |
| 店の商品（価格・個数・単価・在庫の新鮮／傷んだ数） | `shop_view(shop)`（今いる店は `market_shop`） |
| 仕込み3段階と買えるか | `prep_tiers()` |
| 鍋の素を買ったか／「鍋の素 中11杯 買った」 | `prep_tier_paid()`／`today_base()` |
| 市場を出られるか | `can_exit_market()` |
| 予算（残金／確保／使える） | `budget()` |

### 閉店

| 項目 | 読むもの |
|---|---|
| 今夜の提供・注文・未提供の杯数・評価の内訳・売上 | `tonight_result()` |
| 修繕基金（対象ごとの状態・今夜の額・1晩の上限・今日積める上限・刻み） | `fund_view()` |
| 次へ（朝へ） | `flow.is_advance_blocked()`・`flow.advance_phase()` |

### 結果・ゲームオーバー

| 項目 | 読むもの |
|---|---|
| 成績・目標 | `result_view()`（`Result.format_report`／`format_goals`／`format_story` で文面） |
| ゲームオーバーの理由 | 理由の文：`current_line()`。種類と額：`game_over_info()`（UI準備B④で追加） |
| 出口（同じ朝から／直近の朝／Day1から／新しい周／続きから） | `exits()` と `retry()`・`last_morning()`・`run_again()`・`new_run()`・`continue_game()` |

### スマホ

| 項目 | 読むもの |
|---|---|
| ニュース（今日と過ぎた日） | `phone_news()` |
| 保存レシピ・客ごとの「いつもの」 | `phone_recipes()` |
| ログ | `talk_log_entries()` |
| SNS（予報） | 今は DebugPanel の `_format_tonight_memo` のみ（C で DM に置き換える） |

## 7. まだ取れない項目（作っていない）

| 項目 | 状況 | 予定 |
|---|---|---|
| 足りなかった杯数の内訳（素材・鍋・断った） | `tonight_result()` は未提供の合計だけ | C |
| 客足（評判の横の言葉） | 無い | C |
| DM（常連からのDM） | `phone_news()` の `dm` は街のDMだけ | C |
| 短縮名（客の表示名の短縮） | `log_speaker`・`ScheduleData.customer_display_name` は正式な表示名 | C |
| 会話ログの構造化の拡張（注文の要約など） | `talk_log_entries()` は行のみ。注文の要約は文字列（`TalkLog.order_summary_lines()`） | 対象外 |
| 開店中に鍋を触れる条件（ADJUST中も触れる） | `can_touch_pot()` は今の挙動のまま | C |
| 水・だしの鍵の本番UIでの使い方 | 問いは揃っている | B |
