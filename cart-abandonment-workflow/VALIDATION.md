# ローカル検証結果

## 結果

3モード共通版について、ネットワーク通信をOSレベルで禁止した状態でローカルテストを実施し、**32テストすべて成功**しました。

```bash
# macOSでネットワークを遮断して実行（このディレクトリを基準にした例）
/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  /usr/bin/python3 -I cart-abandonment/tests/test_workflow.py --mode full
```

macOS以外も含む通常のローカルテスト手順は、内側のREADMEを参照してください。テストはTD CLIや配信コネクタを呼びません。

## 確認した項目

- `cart / browser / both` の選択、ブラウザ単独時の不要なカート用Campaign・出力への非依存。
- 配布時にWorkflow・本番配信・テスト配信が無効で、スケジュールが存在しないこと。
- 設定ファイルの実読込、YAML・重複キー・変数展開・Digdag条件/ループのローカル評価。
- 最後の活動・最新セッション、端末をまたぐ購入/カート抑止、共有端末の曖昧性。
- 最新の空カート、同秒のカート削除優先、不正な最新PDPや在庫切れ商品の旧行復活防止。
- 通常・夜間の半開区間、DST境界、ローリング/日次の共有頻度キャップ。
- 最新の同意、欠損/競合した変更行、正規化メールの重複、配信直前の同意・実行遅延確認。
- 任意ソース無効時の非参照、商品/推薦/属性/クーポンの最新行、期限・表示項目。
- 安定した行動キーによる再選択抑止、attemptに結び付いた予約、対象ゼロ・件数上限。
- 文字列の真偽値や不正数値の拒否。
- 合成データのテスト専用宛先・許可リスト・想定通数・本番資産混同防止・出力列の一致。

配布チェックではSkillの2つの同梱コピーの一致、TDアカウント固有メタデータの不在、実メール・固定UUID・既知の顧客固有文字列の残存を検査します。旧参考SQLの固定UUID形式のセンチネルは汎用プレースホルダーへ置換しました。

```bash
python3 -I scripts/check_package.py
```

これらの検査は完全な秘密情報スキャナーではありません。公開前には差分の目視確認も行ってください。

## 検証できていないもの

ローカルでは実テンプレートSQLをSQLiteで実行し、TDの日時UDFをローカル実装、TrinoのDATE演算を明示変換しています。YAMLはRuby/Psych、条件式はNodeで確認しています。

**実TD Trino・TD hosted Digdag・接続先Campaign・Engage Liquid・実データの完全性/性能は未検証です。** ローカル成功を実機成功とは扱いません。導入先での検証・デプロイ・Workflow実行・送信には別途確認と承認が必要です。

共有ワークテーブルと予約台帳を使うため、プロジェクト・手動/定期実行間の直列化は運用側の前提です。排他ロックやexactly-once配信を保証しません。同一attemptのexportからの手動resumeは行わず、失敗時は配信先の結果と照合します。

旧カートの高度な推薦生成・RFM・Liquid列名と、ブラウザの最長滞在商品選定は、そのまま互換とはしません。必要なアダプターを実装して回帰確認してください。詳細は `MIGRATION.md` と内側のREADMEに記載しています。

---

<img src="https://work.treasure.ai/gem-emoji.svg" width="16" height="16" align="absmiddle" alt=""> Generated with [Treasure Work](https://work.treasure.ai/)
