# Treasure Data Skills 命名規則

## 形式

```
td-<カテゴリ>-<機能名>
```

- 先頭は必ず `td-`(Treasure Data向けであることを示す)
- `<カテゴリ>` は元リポジトリの親フォルダに対応する(下表)
- `<機能名>` は小文字英数字とハイフンのみ。カテゴリ名の重複は避ける(例: `workflow-llm` ではなく `td-workflow-llm`)
- zipファイル名、zip内の最上位フォルダ名、`SKILL.md` の `name:` の3つを同一にする(例: `td-sql-trino.zip` → `td-sql-trino/SKILL.md` → `name: td-sql-trino`)
- 1つのzipに、最上位フォルダ1つ・`SKILL.md` 1つ(Claude Desktopの登録条件)

## カテゴリ

| カテゴリ | 元の親フォルダ | 意味 |
|---|---|---|
| `sql` | `sql-skills` | TD向けSQL(Trino / Hive)の記述・最適化・移行 |
| `tdx` | `tdx-skills` | `tdx` CLIによるTD CDP・Engage・AI Foundry等の操作 |
| `workflow` | `workflow-skills` | Treasure Workflow(Digdag / dbt / LLM連携)の作成 |

## 新旧対応表

| 新名称 | 旧名称 | 元フォルダ |
|---|---|---|
| `td-sql-hive` | `hive` | `sql-skills` |
| `td-sql-time-filtering` | `time-filtering` | `sql-skills` |
| `td-sql-trino` | `trino` | `sql-skills` |
| `td-sql-trino-optimizer` | `trino-optimizer` | `sql-skills` |
| `td-sql-trino-to-hive-migration` | `trino-to-hive-migration` | `sql-skills` |
| `td-tdx-activation` | `activation` | `tdx-skills` |
| `td-tdx-cas` | `cas` | `tdx-skills` |
| `td-tdx-connector-config` | `connector-config` | `tdx-skills` |
| `td-tdx-engage` | `engage` | `tdx-skills` |
| `td-tdx-foundry-agent` | `foundry-agent` | `tdx-skills` |
| `td-tdx-foundry-agent-prompt` | `foundry-agent-prompt` | `tdx-skills` |
| `td-tdx-foundry-agent-test` | `foundry-agent-test` | `tdx-skills` |
| `td-tdx-journey` | `journey` | `tdx-skills` |
| `td-tdx-parent-segment` | `parent-segment` | `tdx-skills` |
| `td-tdx-parent-segment-analysis` | `parent-segment-analysis` | `tdx-skills` |
| `td-tdx-segment` | `segment` | `tdx-skills` |
| `td-tdx-workflow` | `td-workflow` | `tdx-skills` |
| `td-tdx-basic` | `tdx-basic` | `tdx-skills` |
| `td-tdx-validate-journey` | `validate-journey` | `tdx-skills` |
| `td-tdx-validate-segment` | `validate-segment` | `tdx-skills` |
| `td-workflow-dbt` | `dbt` | `workflow-skills` |
| `td-workflow-digdag` | `digdag` | `workflow-skills` |
| `td-workflow-llm` | `llm-workflow` | `workflow-skills` |

## 新規追加時のルール

1. 内容がSQL・tdx CLI・ワークフローのどれに当たるかでカテゴリを決める。どれにも当たらない場合は、新カテゴリを追加してこの表も更新する
2. `td-<カテゴリ>-<機能名>` でフォルダ名と `name:` を決める
3. `description` の末尾に、TD関連語(Treasure Data / TD / トレジャーデータ / トレジャデータ / トレジャー)でも発火する一文を入れる
4. 他のSkillのファイルを相対パスで参照しない(Skillは1つずつ独立して登録されるため)。必要なら参照先のファイルをSkill内の `references/` に含める

## 変更点メモ

- `td-workflow-llm` は元々 `../digdag/references/` を参照していたため、必要な5ファイル(operators, py-operator, patterns-etl, patterns-control, scaffold)を自身の `references/` にコピーした
- `td-workflow-llm` 本文中の「digdag skill」は `td-workflow-digdag` に書き換えた。構文やオペレーター一覧は、そちらのSkillも登録すると参照できる
