# 検証記録

実施日 2026-10-22 / 作成 Treasure Work

## 完了した検証
- Python標準ライブラリによるローカルテスト **74件成功**。
  - 初期化のdry-run、既存project非上書き、索引維持、パストラバーサル・symlink拒否。
  - config型、期間、SQL識別子、内部host、dashboard pin、secret/profile/site禁止。
  - 実配布テンプレートのcompile、web/separate/任意広告費の有効・無効切り分け。
  - SQLパス・参照マート・SELECT-only構造、時系列条件・occurrence保持の構造チェック。
  - 集約JSONの行数・通貨・粒度、NULL/ROAS、XSS escape、QA失敗時の前回成功維持。
- SQLGlot 26.33.0 のTrino構文parserで、変数をfixtureに置換した **SQL 17ファイルの文法解析が成功**。
- 配布 `.dig` とparams YAMLのgeneric YAML parseはerrorなし。Digdag独自 `!include` にはgeneric parserで `TAG_RESOLVE_FAILED` warningが出る（includeの意味解釈はこのparserの検証対象外）。
- TDテンプレートHTMLのSHA256がpinした原本と一致。
- 合成データによる `examples/dashboard-demo.html` を生成。実顧客の結果ではない。

## 未実施・残る確認
- **TDサーバーへのpush/run、実エンジンでのSQL実行、実データの金額・件数照合は未実施**。
- TD_SESSIONIZE_WINDOWのtimeoutちょうど1800秒、MIN_BYのROW順序、日時関数、TD型保存等は実エンジンで確認する。
- SDK session IDの完全性・再利用、同一秒のevent順序、native event ID衝突、受信時刻とevent時刻のずれを実データで確認する。
- 注文の原本・最新状態・取消返品・明細粒度、会員ID対応、費用粒度は顧客ごとに確認する。
- 最新会員観測Cookieへ1注文を帰属するモデル、session MAXによる遡及lookback、累積観測期間をユーザーに説明する。
- ブラウザのdesktop/390pxの自動表示確認は **既存ブラウザが使用中のため未実施**。他セッションを閉じたり設定を変えたりしていない。納品前・各projectの更新時には表示を確認する。
- この環境のtdx wf helpにvalidateサブコマンドはなかったため、`tdx wf validate` の成功は主張しない。付属validatorを実行し、push検証は実施時のCLIで確認する。
- `.digdagignore` でruntime成果物を除外する。実pushのdry-run時にCLIによる除外を照合する。
- この追加PRはパッケージ配置とmarketplace定義への登録を対象とする。PRのmainへのマージ、ダッシュボードの公開URL化、キャンペーン送信は行わない。

ローカルテストやparser成功は、実TD実行の代わりにはならない。初期テンプレートは `configured=false`、adapterに未確定値があり、そのままの実行を意図していない。
