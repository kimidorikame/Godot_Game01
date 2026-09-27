# 夜湯・7日間自動試遊の結果

2026-09-26。分析対象は **1eadb70155e4d614466bfd5003d10b65be6bb3bb**。GitHubとローカルの一致を確認し、`git archive` のコピーを固定して実行した。ゲーム本体は変更していない。

**7方針×30シード＝210周、1470日分を完了。進行停止0、ゲームオーバー0。** ただし、小仕込み固定では供給不足で早期閉店した夜が60回あり、営業内容がすべて成功したという意味ではない。現行既存テストも10スイート・597項目で失敗0。

## 比較表

現金・評判・杯数は各方針30周の平均。現金幅は観測最小〜最大。GOOD以上率は「GOOD＋GREAT／評価対象需要」で、未提供も分母に残す。現行の評価なし持ち帰り1杯は除外する。1500/1600は計測上の比較目標であり、現行に終了判定画面があることを意味しない。

| 方針 | 最終現金 | 現金幅 | 最終評判 | 提供／7日 | 未提供／7日 | GOOD以上率 | 現金1500達成 | 現金1600達成 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 予報＋基本GOOD | 2007 | 1832〜2165 | 71.7 | 88.5 | 0.0 | 99.7% | 30/30 | 30/30 |
| 予報＋既知好物 | 1991 | 1832〜2149 | 75.5 | 95.1 | 0.0 | 99.7% | 30/30 | 30/30 |
| 小仕込み固定 | 1738 | 1595〜1866 | 63.4 | 77.0 | 9.3 | 86.8% | 30/30 | 29/30 |
| 大仕込み固定 | 1818 | 1626〜1989 | 71.7 | 88.5 | 0.0 | 99.7% | 30/30 | 30/30 |
| SOUR＋FILLINGだけ | 1367 | 1156〜1678 | 16.0 | 58.0 | 2.0 | 6.9% | 4/30 | 1/30 |
| 素材ゼロ | 1889 | 1740〜2010 | 3.0 | 57.3 | 0.0 | 0.0% | 30/30 | 30/30 |
| Day3・5に取り違え | 1964 | 1839〜2085 | 69.3 | 86.3 | 0.0 | 96.5% | 30/30 | 30/30 |

現行の空料理は最終現金で基本GOODの約94%に達する。注文を無視した安い完成料理より、何も入れない方が大幅に儲かる。鍋や固定費の締め付けを先に強めるより、販売成立条件を揃えるべき根拠になる。

好物は基本GOODより提供が6.6杯増え、売上は約297増えるが、最終現金は約16少ない。好物方針は評判・満足を伸ばす意味がある一方、現金最大化だけでは常に選ぶ理由にならない。これは比較した方針の結果であり、好物投入の全組合せを探索した最適化ではない。

## 方法と自動操作の限界

- Godot **4.4.1-stable mono official**、Windows、ヘッドレス。project featuresは4.7表記。4.7での挙動は今回未検証。
- 実際の `debug_panel.tscn` を生成し、DebugPanelの操作ハンドラ、GameState、EventRunner、OpenController、配布されている客JSONを使う。
- 全周を初期現金600・本来の初期在庫で開始。通しプレイへの資金・在庫の追加なし。市場の購入には実際の代金を払う。
- Day2以降は朝SNSに公開される客種・人数・タグ・判明済み好物を読む。仕入れ時点で翌日の抽選を読まない。画面を人間の目で読んでクリックしたテストではなく、同じ情報を内部データから取り出す自動操作。
- Day1は実注文が13杯であることを事前に知り、基本方針は大仕込みを選ぶ。予報の配達員表示から3杯を推測させる初見の負担は再現していない。持ち帰りはMELLOW＋GENTLEの料理を選ぶ。
- 毎朝 `seed(run_seed * 1000 + day)`。シード1〜30。反応文の乱数が翌朝の抽選をずらすのを避けるために日単位で固定する。評判に依存する人数変動は維持する。
- 仕入れは新鮮な在庫を先に割り当て、不足分のパック購入代が小さい候補を選ぶ。だしは2個まで補充する。翌日までの完全最適化はしない。
- 標準の仕込みは需要12以下で小、15以下で中、16以上で大。Day1のみ大。水・だしは実際の可否判定に従い、団体は最大2レシピで対応する。
- 小・大固定は仕込みだけを変える。SOUR＋FILLING方針は客の要求に関係なく同じ安い料理を出す。初日は該当する酸味を持たず店も閉まっているため、その方針でも完全な2素材料理にならない。
- 素材ゼロ方針は一度も食材を選ばず、市場で買わない。Day1は中仕込み、以降は需要に応じた仕込み。BADの実際の評判低下・需要減を受ける。
- 取り違え方針はDay3とDay5の最初の名前あり客で違うタグの料理を選ぶ。直接BADを書き込まないため、結果は客や手元の在庫次第。独立設計モデルの「個人1杯＋団体1組をBAD」にする条件とは別。
- Day7の精算を実行した後、翌朝の自動新規ゲームリセット前で記録する。
- 自動操作中は12ステップごとに次の描画フレームを待ち、`queue_free()` の削除待ちが溜まらないようにする。

人の操作速度、読み間違い、疲労、面白さは測っていない。30シードで全ルートの安全性を保証しない。標準方針の平均操作ハンドラ呼び出しは約530回／7日、そのうち文章送り約201回。素材ゼロは約239回。マウスクリック実測や所要時間ではなく、反復操作を減らす検討の参考値である。

## 整合性確認

全1470日で次をassertした。

- 需要杯数＝提供杯数＋未提供杯数。
- 売上＝提供杯数×45。
- 評価別杯数の合計＝提供杯数（評価なしも集計）。
- 現金・鍋残量が負にならない。

597項目の既存テストは、ADJUST表示、日次ログ、初回好物、団体部分提供、食材価格、仕込み、評判需要、客日程、鍋、日費用を含む。試験ログにはWindows証明書ストアへのアクセス失敗、既存試験が意図して読む不存在JSONのエラーがある。通しプレイにはGDScript実行エラーを検出していない。

## 別途再現した現行の不整合

| 条件 | 実際の結果 | 判断 |
|---|---|---|
| 新規Day1 | 需要関数9、注文13、だし0、店は利用不可 | 9杯案とチュートリアルの食い違い |
| Day1の朝 | 現金520、支払い予定170、今後の場所代＋水道代140 | 予算表示の不一致。二重引落ではない |
| 14杯・濃さ3・水2・だし1から水→だし→水 | 同時残量18 | 同時容量14を採用するならガード不足 |
| 味なし・豆腐＋肉団子を既知好物のチンピラへ | GOOD | 基本2軸成立後だけ好物加点する提案とは差がある |
| 基本GOOD、濃さ1、傷んだ素材 | OK | 減点は2条件合計でも1段階。現行仕様どおり |
| 残量0・濃さ0/1、だしあり・水あり | だし→水で注文へ戻れる | 旧版の復旧不能は解消 |
| 全17品の新鮮在庫を所持 | ADJUSTが1280×720へ収まる | 実描画も確認。新鮮・傷み併存の全条件は未網羅 |

境界プローブのみ、狙った状態を作るために在庫・鍋へ値を設定した。これを通しプレイの成績へ混ぜていない。

![全在庫ADJUSTの実描画](D:/Projects/GODOT/godot-project-01/planning/playtest_2026_09_26/adjust_all_stock.png)

## 再現方法

固定コピーはローカルの `snapshot_1eadb70` にある。実行時データもこのQAフォルダへ隔離する。PowerShellでリポジトリ直下から：

```powershell
$qaRoot = Join-Path (Get-Location) 'planning/playtest_2026_09_26'
$snapshotPath = Join-Path $qaRoot 'snapshot_1eadb70'
$godotExe = 'D:/soft/Godot_v4.4.1-stable_mono_win64/Godot_v4.4.1-stable_mono_win64_console.exe'
$env:APPDATA = Join-Path $qaRoot 'runtime_data'
& $godotExe --headless --path $snapshotPath --script res://planning/playtest_2026_09_26/run_playthroughs.gd -- 30
Copy-Item -LiteralPath (Join-Path $snapshotPath 'planning/playtest_2026_09_26/playthrough_results.json') -Destination (Join-Path $qaRoot 'current_playthrough_results.json')
node planning/playtest_2026_09_26/summarize_playthroughs.mjs
& $godotExe --headless --path $snapshotPath --script res://tests/run_tests.gd
& $godotExe --headless --path $snapshotPath --script res://planning/playtest_2026_09_26/probe_latest.gd
node planning/playtest_2026_09_26/compare_proposal.mjs 1000
```

別環境では該当コミットを `git archive` で展開し、`playthroughs.gd`・`run_playthroughs.gd`・`probe_latest.gd` の3本を同じ相対位置へコピーし、Godotの `--headless --editor --import --quit` を一度実行する。外側フォルダの `.gdignore` を固定コピーの中へコピーしない。

`compare_proposal.mjs` はGodotを使わない独立モデル。28条件×1000シード＝28,000試行。初日9杯・有料初期セット210・固定常連日程など、現行実装と異なる。詳細・推奨値は [改善案](../BALANCE_REVIEW_2026_09_26.md) を参照。

## 証拠ファイルと旧結果の区別

- 現行210周：[current_playthrough_results.json](current_playthrough_results.json)、[playthrough_summary.json](playthrough_summary.json)、[current_output.txt](current_output.txt)。
- 現行既存テスト：[current_tests_output.txt](current_tests_output.txt)。
- 現行境界プローブ：[latest_probes.json](latest_probes.json)、[probe_latest.gd](probe_latest.gd)。
- 設計モデル：[proposal_model.mjs](proposal_model.mjs)、[compare_proposal.mjs](compare_proposal.mjs)、[proposal_results.json](proposal_results.json)。モデルは検証時点で凍結し、BAD返金感度の任意分岐だけを追加した。
- `agent_fun.md`・`agent_mechanics.md`・`ui_probe*`・`existing_tests*` は更新前のed75f77を含む中間調査。`playthrough_results.json`・`playthrough_output.txt` は通し試験の少数シード予備走行。**現行の結論には本書とcurrent/latestの結果を使う。** 旧プローブの「Day1市場で買いすぎて詰む」は閉店中の店を直接呼んでおり、通常UIの再現として棄却した。
- `snapshot_1eadb70`・`runtime_data`・`source_1eadb70.zip` はローカル再現用として同フォルダの `.gitignore` で除外。QAルートの `.gdignore` は開発中のゲームが検証コピーを取り込まないためのもの。
