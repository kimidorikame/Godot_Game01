extends RefCounted
## 予告DMの日ごとの文（UI準備O）：previews.pools.<客>.texts_by_day ＝ [ { days:[日…], texts:[…] } ]。その日を含む組があればその texts から、
## 無ければ texts（既定の文）から選ぶ（日と主語で決める。乱数なし）。同じ日が2つの組に入るのは検査で弾く。本文の検査（数字・「客足」・{hint}）は
## texts_by_day の文にも効く。予告は first_day（Day2）からなので、それより前の日の組は注意（preview_warnings）。今のデータには texts_by_day を入れない。


func run(t: SceneTree) -> int:
	var c := TestCheck.new()
	Dm.clear_cache()

	# --- 1. 選び方 ---
	var pool := { "texts": ["既定の文"], "texts_by_day": [
		{ "days": [2], "texts": ["二日目の文"] },
		{ "days": [3, 6], "texts": ["三六の文その一", "三六の文その二"] },
		{ "days": [5, 7], "texts": ["五七の文"] } ] }
	c.check("組のある日はその組の文（Day2・Day5・Day7）", Dm.preview_text(pool, "delivery_man", 2) == "二日目の文"
		and Dm.preview_text(pool, "delivery_man", 5) == "五七の文" and Dm.preview_text(pool, "delivery_man", 7) == "五七の文")
	var d3 := Dm.preview_text(pool, "delivery_man", 3)
	c.check("組の中での選び方は今と同じ（日と主語のハッシュ。何度呼んでも同じ）", d3 in ["三六の文その一", "三六の文その二"]
		and d3 == str(pool["texts_by_day"][1]["texts"][absi("3|delivery_man".hash()) % 2]) and Dm.preview_text(pool, "delivery_man", 3) == d3, d3)
	c.check("組の無い日（Day4）は texts（既定の文）", Dm.preview_text(pool, "delivery_man", 4) == "既定の文")
	c.check("texts_by_day が無い客は今までどおり texts", Dm.preview_text({ "texts": ["既定の文"] }, "delivery_man", 3) == "既定の文")
	var mob_pool := { "texts": ["{hint}の既定"], "tag_hint": "POWER", "texts_by_day": [{ "days": [4], "texts": ["{hint}の四日目"] }] }
	c.check("組の文でも {hint} は札の言葉に置き換わる", Dm.preview_text(mob_pool, "dock_workers", 4) == "%sの四日目" % TagWords.word("POWER"))

	# --- 2. 今のデータ ---
	c.check("今のデータには texts_by_day が無く、検査に問題も注意も無い", (Dm.previews_config()["pools"] as Dictionary).values().all(func(p): return not (p as Dictionary).has("texts_by_day"))
		and Dm.problems().is_empty() and Dm.preview_warnings().is_empty(), str(Dm.problems()) + str(Dm.preview_warnings()))

	# --- 3. 検査 ---
	var good: Dictionary = Dm.data().duplicate(true)
	good["previews"]["pools"]["delivery_man"]["texts_by_day"] = pool["texts_by_day"]
	c.check("正しい texts_by_day は検査を通る", Dm.preview_problems(good).is_empty() and Dm.preview_warnings(good).is_empty(), str(Dm.preview_problems(good)))
	var overlap: Dictionary = Dm.data().duplicate(true)
	overlap["previews"]["pools"]["delivery_man"]["texts_by_day"] = [{ "days": [2, 3], "texts": ["あ"] }, { "days": [3], "texts": ["い"] }]
	var p_overlap := Dm.preview_problems(overlap)
	c.check("同じ日が2つの組に入っていたら弾く", p_overlap.any(func(x): return str(x).contains("Day3") and str(x).contains("重なって")), str(p_overlap))
	var digits: Dictionary = Dm.data().duplicate(true)
	digits["previews"]["pools"]["delivery_man"]["texts_by_day"] = [{ "days": [3], "texts": ["今夜9時に寄る"] }]
	c.check("組の文に数字があれば弾く", Dm.preview_problems(digits).any(func(x): return str(x).contains("数字")), str(Dm.preview_problems(digits)))
	var crowd: Dictionary = Dm.data().duplicate(true)
	crowd["previews"]["pools"]["delivery_man"]["texts_by_day"] = [{ "days": [3], "texts": ["客足が多そうだ"] }]
	c.check("組の文に「客足」があれば弾く", Dm.preview_problems(crowd).any(func(x): return str(x).contains("客足")), str(Dm.preview_problems(crowd)))
	var hint: Dictionary = Dm.data().duplicate(true)
	hint["previews"]["pools"]["dock_workers"]["texts_by_day"] = [{ "days": [3], "texts": ["港の連中が寄る"] }]
	c.check("モブの組の文に {hint} が無ければ弾く（tag_hint のある種類）", Dm.preview_problems(hint).any(func(x): return str(x).contains("{hint}")), str(Dm.preview_problems(hint)))
	var shape: Dictionary = Dm.data().duplicate(true)
	shape["previews"]["pools"]["delivery_man"]["texts_by_day"] = [{ "days": [], "texts": ["あ"] }, { "days": [9], "texts": [] }]
	var p_shape := Dm.preview_problems(shape)
	c.check("日が空・範囲外（Day9）・文が空の組は弾く", p_shape.any(func(x): return str(x).contains("days が空")) and p_shape.any(func(x): return str(x).contains("9"))
		and p_shape.any(func(x): return str(x).contains("texts が空")), str(p_shape))
	var day1: Dictionary = Dm.data().duplicate(true)
	day1["previews"]["pools"]["delivery_man"]["texts_by_day"] = [{ "days": [1, 2], "texts": ["あ"] }]
	c.check("Day1 の組は弾かずに注意を出す（予告は Day2 から）", Dm.preview_problems(day1).is_empty()
		and Dm.preview_warnings(day1).size() == 1 and str(Dm.preview_warnings(day1)[0]).contains("Day1"), str(Dm.preview_warnings(day1)))
	Dm.clear_cache()
	return c.finish()
