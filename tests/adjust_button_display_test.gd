extends RefCounted
## 素材ボタンに所持数を表示(B)／調味料と具材のボタンを2行に分ける(C)の検証。
## 判定ロジック・経済数値は変更していないので、ここではADJUSTボタンの文言と配置先
## （_seasoning_row/_options_row）だけを見る。対象は名前あり客（thug）で十分
## （B・Cはモブ固有の仕様ではなく、ADJUSTの表示に関する全客共通の変更のため）。


func _setup(t: SceneTree):
	GameState.reset_for_new_game()
	GameState.day_count = 1
	var panel = load("res://scenes/debug_panel.tscn").instantiate()
	t.root.add_child(panel)   # _ready()が自動でinitial_inventory()を積む
	# 苦瓜(bitter_melon)は初期在庫に無い品目なので、ADJUSTのoptionsスナップショットに
	# 含めるため客をロードする前に積んでおく（options は接客開始時の1回だけの
	# スナップショットなので、後から積んでも今夜のADJUSTには反映されない）。
	GameState.add_inventory("bitter_melon", 2)
	GameState.phase = GameState.Phase.OPEN
	panel._open = OpenController.new([{ "name": "宵の口", "customers": ["thug"] }])
	GameState.set_soup("bone_broth", ["meaty"], 10, 3, 2)
	panel._load_current_customer()
	var guard := 0
	while panel.flow.runner.status != EventRunner.Status.WAITING_INPUT and guard < 50:
		guard += 1
		panel._on_next_event_pressed()
	return panel


func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	var panel = _setup(t)

	# 初期在庫：nam_prik_pao等の調味料10個・具材はDay1Events.initial_inventory参照
	# （Day1の13杯・モブ3種抽選に耐える数へ2026-09-26に増量。offal4/meat_ball6/
	# tofu5/broken_wrapper5。詳細はinitial_inventory()のコメント）。
	c.check("下準備: ナムプリックパオは10個", GameState.fresh_count("nam_prik_pao") == 10)
	c.check("下準備: 肉団子は6個", GameState.fresh_count("meat_ball") == 6)

	var seasoning_texts := []
	for btn in panel._seasoning_row.get_children():
		seasoning_texts.append(str(btn.text))
	var ingredient_texts := []
	for btn in panel._options_row.get_children():
		ingredient_texts.append(str(btn.text))

	# --- B: 所持数がボタンのtextに表示される ---
	c.check("ナムプリックパオのボタンに所持数(10)が表示される",
		seasoning_texts.has("ナムプリックパオ(10)"), str(seasoning_texts))
	c.check("肉団子のボタンに所持数(6)が表示される",
		ingredient_texts.has("肉団子(6)"), str(ingredient_texts))

	# --- C: 調味料(味の軸のみ)は_seasoning_row、具材(具の軸を持つ)は_options_rowに入る ---
	c.check("調味料(ナムプリックパオ・ココナッツミルク・薬膳ナンプラーだれ)は調味料の行のみに入る",
		seasoning_texts.has("ナムプリックパオ(10)")
		and seasoning_texts.has("ココナッツミルク(10)")
		and seasoning_texts.has("薬膳ナンプラーだれ(10)"), str(seasoning_texts))
	c.check("具材(肉団子・下処理したモツ・豆腐・割れた餃子皮)は具材の行のみに入る",
		ingredient_texts.has("肉団子(6)") and ingredient_texts.has("下処理したモツ(4)")
		and ingredient_texts.has("豆腐(5)") and ingredient_texts.has("割れた餃子皮(5)"),
		str(ingredient_texts))
	c.check("調味料の行に具材(肉団子)は混ざらない",
		not seasoning_texts.has("肉団子(6)"), str(seasoning_texts))
	c.check("具材の行に調味料(ナムプリックパオ)は混ざらない",
		not ingredient_texts.has("ナムプリックパオ(10)"), str(ingredient_texts))
	c.check("[廃棄する]は具材の行に入る", ingredient_texts.has("廃棄する"), str(ingredient_texts))

	# --- C: 苦瓜(bitter_melon)はBITTERのみ＝味の素材なので、is_topping()基準では
	#        調味料の行に入る（指示文の独自表とは唯一食い違う点。ingredients.gd自身の
	#        コメントに明記された既存仕様どおり） ---
	c.check("苦瓜(bitter_melon)は調味料の行に入る(is_topping準拠)",
		seasoning_texts.has("苦瓜(2)"), str(seasoning_texts))
	c.check("苦瓜は具材の行には入らない", not ingredient_texts.has("苦瓜(2)"), str(ingredient_texts))

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
