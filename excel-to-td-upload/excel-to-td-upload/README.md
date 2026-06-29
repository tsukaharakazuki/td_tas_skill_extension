# excel-to-td-upload

Treasure Work スキル — Excel ファイルを Treasure Data にアップロードする対話型ウィザード。

## 概要

- Excel の複数シートを Treasure Data のテーブルに一括取り込み
- シート名・カラム名の日本語→英語自動変換
- `AskUserQuestion` による対話型ヒアリング
- `td table:import --json` を使った確実なアップロード

## インストール方法

### Treasure Work（グローバルスキル）

```bash
# ~/.treasure-work/.claude/skills/ 以下にフォルダごとコピー
cp -r excel-to-td-upload ~/.treasure-work/.claude/skills/
```

### Treasure Work（ワークスペーススキル）

```bash
# ワークスペースの .claude/skills/ 以下にコピー
cp -r excel-to-td-upload /path/to/workspace/.claude/skills/
```

コピー後、Treasure Work を再起動するとスキルが認識されます。

## 使い方

Treasure Work のチャットで以下のように呼び出します：

```
/excel-to-td-upload
```

または、Excel ファイルを添付して：

```
このExcelをTDにアップロードしたい

[Attached: data.xlsx]
```

## 必要環境

- Treasure Work（Claude Code）
- `td` CLI コマンド（`/usr/local/bin/td`）
- Python 3 + `openpyxl`（`pip3 install openpyxl`）
- Treasure Data の Write 権限 API キー

## 注意事項

- `pytd` は Treasure Work の OAuth トークンと非互換のため使用不可
- API キーは TD コンソール（Settings → API Keys）から取得してください
- 詳細は `SKILL.md` のトラブルシューティングを参照

## ライセンス

MIT
