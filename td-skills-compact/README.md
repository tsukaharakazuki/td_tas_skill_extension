# td-skills-compact

Treasure Data 向けSkill 23個を、Claude Desktop にそのままドラッグ&ドロップで追加できる形にまとめたフォルダです。

## 使い方

1. このリポジトリをダウンロードして解凍する(GitHubの「Code → Download ZIP」)
2. `td-skills-compact` フォルダを開く
3. 使いたい `td-*.zip` を、Claude Desktop の設定(Customize → Skills)にドラッグ&ドロップする

Skillは1つのzipにつき1つずつ登録します(zipの中にzipは入れられないため)。

## Skill一覧

| カテゴリ | Skill |
|---|---|
| SQL | `td-sql-hive` / `td-sql-time-filtering` / `td-sql-trino` / `td-sql-trino-optimizer` / `td-sql-trino-to-hive-migration` |
| tdx(CLI) | `td-tdx-basic` / `td-tdx-activation` / `td-tdx-cas` / `td-tdx-connector-config` / `td-tdx-engage` / `td-tdx-foundry-agent` / `td-tdx-foundry-agent-prompt` / `td-tdx-foundry-agent-test` / `td-tdx-journey` / `td-tdx-parent-segment` / `td-tdx-parent-segment-analysis` / `td-tdx-segment` / `td-tdx-validate-journey` / `td-tdx-validate-segment` / `td-tdx-workflow` |
| Workflow | `td-workflow-digdag` / `td-workflow-dbt` / `td-workflow-llm` |

- 「Treasure Data」「TD」「トレジャーデータ」などの言葉で呼び出されます
- `td-workflow-llm` は構文の参照先として `td-workflow-digdag` も登録すると便利です
- 命名規則は [NAMING.md](./NAMING.md) を参照
- 元になったSkill: [treasure-data/td-skills](https://github.com/treasure-data/td-skills)(sql-skills / tdx-skills / workflow-skills)
