extends RefCounted
## F4 帳簿（Ledger）の検証（DESIGN.md 10.8.4）。対象はLedgerクラス自身の記帳・集計
## ロジックと、GameState.ledgerの日をまたぐ永続化（周回でのみクリア）。
## 実際の支払い・購入経路への配線の統合確認はtests/upkeep_test.gd側で行う。

func run(t: SceneTree) -> int:
	var c := TestCheck.new()

	# --- 1. record()は{day, phase, category, amount, item, count, unit_price, ref}の
	#         形でGameState.ledgerへ1件積む ---
	GameState.reset_for_new_game()
	GameState.day_count = 3
	GameState.phase = GameState.Phase.PREP
	Ledger.record("prep", -80, "small", 0, 80)
	var entry: Dictionary = GameState.ledger[GameState.ledger.size() - 1]
	c.check("dayは記帳した瞬間のGameState.day_count", int(entry.get("day", -1)) == 3, str(entry))
	c.check("phaseは記帳した瞬間のフェーズ名", str(entry.get("phase", "")) == "PREP", str(entry))
	c.check("category/amount/item/unit_priceがそのまま入る",
		str(entry.get("category")) == "prep" and int(entry.get("amount")) == -80
		and str(entry.get("item")) == "small" and int(entry.get("unit_price")) == 80, str(entry))

	# --- 2. pending_bills_today(): reserveとreleaseの合計を反転させた値になる ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	Ledger.record("reserve", -170)
	c.check("reserveだけなら確保額は170", Ledger.pending_bills_today() == 170)
	Ledger.record("release", 80)
	c.check("release80で確保額は90に減る", Ledger.pending_bills_today() == 90)
	Ledger.record("release", 90)
	c.check("release90でさらに確保額は0になる", Ledger.pending_bills_today() == 0)

	# --- 3. pending_bills_today()は「今日」の記帳だけを見る(日をまたいだ記帳は無視) ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	Ledger.record("reserve", -80)
	GameState.day_count = 2
	Ledger.record("reserve", -170)
	c.check("2日目の確保額は2日目の記帳(170)だけで、1日目の80は混ざらない",
		Ledger.pending_bills_today() == 170, str(Ledger.pending_bills_today()))

	# --- 4. spend_by_category_today(): saleとreserve/releaseは支出に含めない。
	#         金額は正の値で返す。他カテゴリはカテゴリ別に合算される ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	Ledger.record("reserve", -170)
	Ledger.record("daily_cost", -80)
	Ledger.record("rent", -90)
	Ledger.record("market", -50, "winter_melon", 5, 10)
	Ledger.record("market", -24, "tofu", 3, 8)
	Ledger.record("sale", 45, "thug", 1)
	Ledger.record("release", 170)
	var spend := Ledger.spend_by_category_today()
	c.check("daily_cost=80・rent=90が正の値で入る",
		int(spend.get("daily_cost", 0)) == 80 and int(spend.get("rent", 0)) == 90, str(spend))
	c.check("同じカテゴリ(market)は合算される(50+24=74)",
		int(spend.get("market", 0)) == 74, str(spend))
	c.check("saleは支出に含まれない", not spend.has("sale"), str(spend))
	c.check("reserve/releaseは支出に含まれない(表示専用の二重計上を避ける)",
		not spend.has("reserve") and not spend.has("release"), str(spend))

	# --- 5. GameState.ledgerは日をまたいでも消えない(reset_for_new_dayではクリアしない)。
	#         reset_for_new_gameでのみクリアされる ---
	GameState.reset_for_new_game()
	GameState.day_count = 1
	Ledger.record("daily_cost", -80)
	var size_before_day_reset: int = GameState.ledger.size()
	GameState.reset_for_new_day()
	c.check("reset_for_new_dayではledgerは消えない(周回を通して蓄積する)",
		GameState.ledger.size() == size_before_day_reset, str(GameState.ledger.size()))
	GameState.reset_for_new_game()
	c.check("reset_for_new_gameでledgerは空になる", GameState.ledger.is_empty())

	print("失敗数: ", c.fails, " / ", c.checks, "件")
	return c.fails
