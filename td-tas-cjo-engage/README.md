# td-tas-cjo-engage

Treasure AI Studio で、Treasure Data CDP の **CJO（Customer Journey Orchestration）ジャーニーの新規作成・改修**を行い、配信チャネルとして **Engage Studio** を使うための Skill です。
Engage Studio の契約有無を確認し、契約している場合はワークスペースや Always-On Campaign などの**セットアップ**もこの Skill で進められます。

## できること

| 領域 | 内容 |
|---|---|
| Engage Studio | 契約有無の判定、構成の棚卸し、ワークスペース作成・親セグメント割当・送信ドメイン割当、送信者 / コネクション確認、配信準備チェック |
| メール | テンプレート / Always-On Campaign / One-Off Campaign の YAML 作成、親セグメントの列からの差し込み変数（NULL率に応じた既定値）、DAM 画像 |
| プレーンテキスト | HTML（画像内文字は vision）からプレーンテキスト版を生成し、UTM を確認のうえ同意後に push。HTML / テキスト / 件名の整合性チェック |
| 新規ジャーニー | 5ステップ（基準セグメント → 分岐 → アクティベーション → ステージ → 検証・push）で1つずつ確認しながら作成 |
| 既存ジャーニー改修 | **必ずテストジャーニー `test_v<N>_<本番名>` を新規作成して確認**してから本番へ。エントリー条件変更の影響（途中ユーザーの離脱）を人数で提示 |
| アクティベーション | Engage V1 連携、スケジュール、ビヘイビア列、API でのみ可能な列名変更・ストリングビルダー（クーポンコード） |

## 安全方針

- 既存ジャーニーは本番を直接変更しない（テストジャーニー → 利用者確認 → 本番）。
- REST API は不正な値でも受け付けることがあるため、本番に直接当てない。GET バックアップと dry-run を既定にしています。
- 配信が始まる操作（journey resume / run、campaign / AOC launch）と削除は Skill から実行しません。
- 書き込みは validate → dry-run → preview → 承認 → 実行 → 再取得で検証。

## 使い方

`td-tas-cjo-engage/` を Skill として登録し、Treasure AI Studio で依頼します。

依頼例:

- 「Engage Studioを契約しているか確認して、足りない設定を教えて」
- 「会員登録後のウェルカムジャーニーを作って。メールは Engage の Always-On Campaign で」
- 「<ジャーニーURL> の Stage2 の待機を3日から5日にして」
- 「F1向けステージにクーポンコード ABC123 を渡して」
- 「<テンプレートURL> のプレーンテキストを作って」
- 「<キャンペーンURL> の HTML とテキストに食い違いがないか確認して」

## 構成

```
td-tas-cjo-engage/
├── SKILL.md                     # AI 向け入口（必須ルールと振り分け）
├── references/
│   ├── engage-setup.md          # 契約判定・棚卸し・セットアップ
│   ├── engage-email.md          # テンプレート / AOC / One-Off の YAML、差し込み変数
│   ├── plaintext.md             # プレーンテキスト生成・整合性チェック
│   ├── journey-build.md         # 新規ジャーニー 5ステップ
│   ├── journey-update-safety.md # 改修の必須手順（テストジャーニー・エントリー条件判定）
│   ├── activation-engage.md     # アクティベーション YAML と API PATCH
│   ├── segment-rules.md         # セグメント条件・除外・エラーコード
│   ├── journey-validation.md    # ジャーニー YAML 文法・フロー制御
│   ├── journey-monitoring.md    # 状態確認・反映確認
│   └── known-issues.md          # 既知の挙動（DEMO 検証で更新）
├── scripts/                     # Python 標準ライブラリのみ（clone_test_journey.py は PyYAML 推奨）
├── templates/project-memo.yml   # 顧客ごとの ID・合意事項メモ
└── tests/demo-scenarios.md      # DEMO 環境での検証シナリオと結果ログ
```

## 出典

- [cjo-journey-tips](../cjo-journey-tips/SKILL.md)、[engage-html-to-plaintext](../engage-html-to-plaintext/SKILL.md)、[engage-mail-check](../engage-mail-check/SKILL.md)
- [td-skills-compact](../td-skills-compact/)（td-tdx-journey / validate-journey / segment / validate-segment / activation / connector-config / engage / parent-segment / parent-segment-analysis / basic）
- tdx 2026.10.4 の CLI 本体（YAML スキーマ、push の照合方法）と `tdx connection schema treasure_engage_v1`
- 利用者報告（API の不正値受付、エントリー条件変更時のバージョンアップと途中離脱）

## 開発の進め方

初版の作成後、DEMO 環境で [tests/demo-scenarios.md](tests/demo-scenarios.md) を順に実行し、結果を [references/known-issues.md](references/known-issues.md) と各 reference に反映して更新していきます。
