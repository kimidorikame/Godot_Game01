extends RefCounted
class_name TalkLog
## 会話ログと注文の要約（フェーズ4・手順4-7②。DESIGN.md 10.4）。スマホの「ログ」タブの元。
##
## 会話ログ：プレイヤーに見せた行の時系列。1行＝{ day, kind, speaker, text }（kind：narration／talk／serve／
## reaction／news／choice。speaker は表示名。店主の行・地の文は空）。**実行時の記録のみで保存しない**
## （朝の保存・再挑戦では復元しない＝保存状態も版も増やさない）。今日の分だけ（WAKE でクリア。再挑戦で
## 戻した朝は空から）。上限 MAX_LINES 行を超えたら古い行から捨てる。記録するのは DebugPanel の
## _record_visible_event()（_refresh の末尾）で、状態を読むだけ：ゲームの数値・乱数には触れない。
##
## 注文の要約：来店ごとの1行。来店記録（CustomerMemory）と場面の注文（今日の頼み）から組む＝
## 新しい保存状態は要らない（全日分が出せる）。

const MAX_LINES := 300
const KINDS := ["narration", "talk", "serve", "reaction", "news", "choice"]

static var entries: Array = []


static func clear() -> void:
	entries = []


## 1行足す。上限を超えたら古い行から捨てる。空の本文は足さない。
static func add(day: int, kind: String, speaker: String, text: String) -> void:
	if text == "":
		return
	entries.append({ "day": day, "kind": kind, "speaker": speaker, "text": text })
	if entries.size() > MAX_LINES:
		entries = entries.slice(entries.size() - MAX_LINES)


## 今日の会話ログの本文（上から古い順）。
static func log_text() -> String:
	if entries.is_empty():
		return "（まだありません）"
	var lines := PackedStringArray()
	for e in entries:
		var speaker := str(e["speaker"])
		lines.append("・%s%s" % [speaker + "：" if speaker != "" else "", str(e["text"])])
	return "\n".join(lines)


## 注文の要約（新しい日が上）。来店記録の全日分。
## 例：Day2 宵の口　チンピラ：いつもの MELLOW/GENTLE ／ 今日 HOT/POWER（辛め） → 出した：…＋… → GOOD
## 複数杯の来店は杯ごとに「具材（評価）」を並べる。出さなかった来店は「出さなかった」。
static func order_summary_lines() -> Array:
	var rows := []
	for customer_id in GameState.customer_memory:
		for visit in CustomerMemory.visits_of(str(customer_id)):
			rows.append({ "customer": str(customer_id), "visit": visit,
				"sort": int(visit["day"]) * 100 + _slot_order(int(visit["day"]), str(visit["slot"])) })
	rows.sort_custom(func(a, b): return int(a["sort"]) > int(b["sort"]))
	var lines := []
	for row in rows:
		lines.append(_summary_line(row["customer"], row["visit"]))
	return lines


static func _slot_order(day: int, slot_name: String) -> int:
	var slots := ScheduleData.regular_slots(day)
	for i in range(slots.size()):
		if str(slots[i].get("slot", "")) == slot_name:
			return i
	return 9


static func _summary_line(customer_id: String, visit: Dictionary) -> String:
	var base := ScheduleData.customer_profile(customer_id).get("wanted_tags", []) as Array
	var order := "いつもの %s" % "/".join(PackedStringArray(base))
	var today := Day1Events.today_request_of(customer_id, str(visit["episode_id"]))
	if not today.is_empty():
		var label := str(today.get("label", ""))
		order += " ／ 今日 %s%s" % ["/".join(PackedStringArray(today["tags"])), "（%s）" % label if label != "" else ""]
	var served := ""
	var grades: Array = visit["grades"]
	var cups: Array = visit["ingredients"]
	if int(visit["served"]) <= 0:
		served = "まだ出していない" if int(visit["day"]) == GameState.day_count else "出さなかった"
	elif grades.size() <= 1:
		served = "出した：%s → %s" % [RecipeBook.ingredient_text(cups[0] if not cups.is_empty() else []),
			str(grades[0]) if not grades.is_empty() and str(grades[0]) != "" else "評価なし"]
	else:
		var parts := PackedStringArray()
		for i in range(grades.size()):
			parts.append("%s（%s）" % [RecipeBook.ingredient_text(cups[i] if i < cups.size() else []),
				str(grades[i]) if str(grades[i]) != "" else "評価なし"])
		served = "出した：%s" % "／".join(parts)
	var name_text := ScheduleData.customer_display_name(customer_id)
	return "Day%d %s　%s：%s → %s" % [int(visit["day"]), str(visit["slot"]), name_text, order, served]


## スマホの「ログ」タブの本文。
static func tab_text() -> String:
	var lines := PackedStringArray(["◆注文の要約◆"])
	var summary := order_summary_lines()
	if summary.is_empty():
		lines.append("（まだありません）")
	else:
		lines.append_array(PackedStringArray(summary))
	lines.append("◆今日の会話ログ◆")
	lines.append(log_text())
	return "\n".join(lines)
