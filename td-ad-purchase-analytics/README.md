# td-ad-purchase-analytics

広告・施策から初めて観測したCookieが、その後会員化し、どれだけ購入したかを長期追跡するTreasure Work Skillです。Skill名・配布フォルダ名は `td-ad-purchase-analytics` です（同リポジトリの既存Skillと同じkebab-case）。

## できること
- `td-js-sdk` のWebログを必須入力とし、`td_client_id` を主軸にする。
- SDK session IDを利用するか、なければ `TD_SESSIONIZE_WINDOW` でセッショナイズしてsession番号を付ける。
- セッション途中の会員IDを `MAX(user_id)` で補完する。複数IDでもMAXを採用し、競合はQAに残す。
- 全保持WebログでCookie初回流入・初回session・流入元を特定し、新規/再訪sessionを分ける。
- landingとsession内流入を分け、初回session内の流入はすべて新規と扱う。
- GA4 ecommerce等のWeb購買、または会員IDで結ぶ別購買のどちらかを正本にする。
- 獲得Cookie → 会員ID観測Cookie → ログイン後購買Cookie・注文・売上を集計する。
- 任意の購入前期間（既定7日）の流入last-touchを別モデルとして集計する。
- 広告費があれば粒度・通貨を合わせた獲得コホートROASを計算する。
- プロジェクトごとにWorkflow、MEMORY、設定、TDブランドHTML、更新mappingを保存する。

## 同梱物
```text
td-ad-purchase-analytics/
├── SKILL.md                       # 読込の入口
├── README.md
├── marketplace-entry.json         # 登録用の例。既存marketplaceへ追記して使う
├── references/
│   ├── hearing.md                 # 目的・ソース・粒度の確認
│   ├── analytics-contract.md      # 指標と時間/帰属の契約
│   ├── operations.md              # 初期化・WF実行・更新・復旧
│   └── dashboard.md               # TDテンプレートと集約JSON契約
├── scripts/
│   ├── init_project.py
│   ├── validate_project.py
│   └── render_dashboard.py
├── templates/project/
│   ├── MEMORY.md
│   ├── tdx.json
│   ├── ad_purchase_analytics.dig
│   ├── config/{project.json,params.yml}
│   ├── queries/*.sql
│   ├── dashboard_template/{SKILL.md,template.html}
│   └── dashboard_output/mapping.json
├── tests/
└── examples/demo-data.json         # 合成データ。実データではない
```

## GitHub URLからの利用
このフォルダを含むPRがmainへマージされた後は、次のURLから読み込めます。PRの確認中は、URLの `main` を当該ブランチ名またはcommit SHAに置き換えてください。

`https://github.com/tsukaharakazuki/td_tas_skill_extension/tree/main/td-ad-purchase-analytics`

Treasure WorkへそのURLを渡し、「SKILL.mdと関連ファイルを読み、このSkillを導入して」と依頼します。再現性のためcommit SHAを記録します。別リポジトリに置く場合はURLを変更します。marketplace方式なら `marketplace-entry.json` のオブジェクトを既存 `.claude-plugin/marketplace.json` のplugins配列へ追加します。既存ファイル全体をこの断片で置換しません。

## プロジェクトの開始
```bash
python3 -I <skill_dir>/scripts/init_project.py --workspace <workspace> --name spring_ads --dry-run
python3 -I <skill_dir>/scripts/init_project.py --workspace <workspace> --name spring_ads
```

初期化後は `Project/spring_ads/` に保存します。`Project/MEMORY.md` は索引、project内の `MEMORY.md` は設定・意思決定・更新履歴です。既存projectへの初期化は失敗して上書きを防ぎます。

```text
Project/spring_ads/
├── MEMORY.md
├── config/
├── queries/
├── ad_purchase_analytics.dig
├── tdx.json
├── dashboard_template/
├── dashboard_output/
│   ├── mapping.json
│   ├── runs/<run_id>/index.html
│   └── index.html                  # promoteした最新成功HTML
└── runs/
    ├── <run_id>/dashboard-data.json
    └── latest_success.json
```

## 実行前の必須設定
1. ヒアリング・読み取り調査後、実テーブルに合わせてadapterを編集する。推測の列で実行しない。
2. `config/project.json` にDB・期間・session方式・会員/注文/金額の定義を記録する。
3. 残った未確定値を解消して `configured=true` とする。
4. `validate_project.py <project> --compile-config` → tdxのローカルvalidate → push差分確認・承認 → run dry-run → 実行範囲説明・明示承認 → run。
5. WF成功とQA/complete確認後、同一runの集約データだけでdashboardを更新する。

v1は**全保持履歴の再構築**です。増分更新・自動実行・キャンペーン送信は含めません。defaultではTDへのpush/run、外部公開、データ送信は一切実行しません。

## 検証
Pythonは標準ライブラリだけで動作します。
```bash
python3 -I -B -m unittest discover -s <skill_dir>/tests -v
```

ローカルテストは設定・パス・安全性・描画契約の検証です。実TD上のSQL実行、サーバーpush、timeoutちょうど1800秒の境界動作は、接続する顧客データで別途確認します。未設定のテンプレートがvalidatorで失敗するのは意図した動作です。

## 主な制約
- 新規は「保持ログ内の初回観測Cookie」であり、新規の人や新規会員とは限りません。
- セッションMAXで補完しても、実際のID観測時刻より前の注文を「ログイン後」にはしません。
- session内複数流入の施策別関連値は非加算です。全体KPIはlandingを使います。
- 購入完了URLだけで注文IDがなければ、確定注文数や売上を作れません。
- v1は単一通貨です。広告費未入力・0・粒度不一致・金額不明はROASを表示しません。
- 全保持履歴が縮むと初回観測を失うため、前回の履歴範囲を比較して止めます。完全なfirst-touch永続台帳・増分処理は別設計です。
- 累積売上は観測期間で変わります。固定7/30/90日LTV等は追加定義と実装が必要です。

## 参照と来歴
- 構成参考 [td-datafeed-workflow](https://github.com/tsukaharakazuki/td_tas_skill_extension/tree/main/td-datafeed-workflow)
- HTML原本 [td-tas-dashboard-template](https://github.com/tsukaharakazuki/td_tas_skill_extension/tree/main/td-tas-dashboard-template)
- バンドル元commit `7d087a31a2625341a6d5811d149fd633859bda32`。HTML hashは `references/dashboard.md`。
- 同梱HTML/ブランドガイドは指定リポジトリの原本から保持。ロゴはinlineの公式SVG。フォント以外の外部リソース・外部JSなし。
- 顧客へ再配布・公開する場合は、元リポジトリの利用条件とブランド利用権を確認してください。独自の権利許諾は追加しません。

作成 Treasure Work
