---
name: td-tas-dashboard-template
description: Treasure AI StudioのHTMLレポート・ダッシュボードを作るとき、またはほかのSkillがHTML出力を作るときに使用する。Treasure AIのブランドカラー、Manrope/Interのタイポグラフィ、公式ロゴ、「Prepared by Treasure Data」表記を適用し、TD担当が作成したものだと分かる見た目にする。「ダッシュボードを作って」「HTMLレポート」「ブランドに合わせて」「ロゴを入れて」「カラーパレット」「Treasure AIっぽく」「td-tas-dashboard-template」などで使う。
---

# td-tas-dashboard-template

Treasure AI StudioのHTMLレポート・ダッシュボードに、Treasure Dataのブランド（カラー・フォント・ロゴ）を適用するためのテンプレートSkillです。TD担当が作成したと分かる見た目に統一することが目的です。

## 他のSkillから読み込まれたとき

1. このSKILL.mdを読み、下記の色・フォント・ロゴ規則を守る。
2. HTMLは白紙から書かず、同じフォルダの `template.html` を出発点にする。
3. ヘッダーのロゴとフッターの「Prepared by Treasure Data」は必ず残す。
4. 色は `:root` の `--tas-*` 変数だけを使う。色の直書きは増やさない。
5. 完成後にチェックリストを確認してから渡す。

## カラーパレット

ブランドガイド（Treasure AI Brand Guidelines 2026 v0.1、p.11）のHEX値。画面表示・Web出力ではHEXを使う。

| 名前 | HEX | 用途 |
|---|---|---|
| Primary 1 | `#494FFF` | 表ヘッダー、KPI値、見出しの強調、主系列 |
| Primary 2 | `#8753FF` | 引用の罫線、補助の強調。全色ロゴの背景にも使える |
| Secondary 1 | `#847BF2` | 補助系列 |
| Secondary 2 | `#C466D4` | 補助系列 |
| Accent 1 | `#9DCC4C` | 正の変化、系列（文字色には使わない） |
| Accent 2 | `#D9E47C` | 系列（文字色には使わない） |
| Accent 3 | `#EE2328` | 警告とマイナス表示だけに使う |
| Accent 4 | `#F15C60` | 系列、注意 |
| Accent 5 | `#F69068` | 系列 |
| Neutral 1 | `#FFFFFF` | 背景 |
| Neutral 2 | `#000000` | 本文 |

派生トーン（ガイドには定義がなく、パレットから作った値）: `--tas-surface`（Primary 1の6%、カード背景）、`--tas-muted`（黒の64%、補足文字）、`--tas-border`（黒の12%、罫線）。

**グラフの系列色**は次の順で使う: Primary 1 → Primary 2 → Secondary 2 → Secondary 1 → Accent 5 → Accent 1 → Accent 2 → Accent 4。Accent 3は系列に使わない。Accent 1・2は白地では文字として読みにくいので、塗りつぶしに使い、ラベルは黒で載せる。

## タイポグラフィ

| 用途 | フォント | サイズ目安 | 行間 |
|---|---|---|---|
| タイトル・大見出し | Manrope Bold | 40px | 110–125% |
| 中見出し | Manrope Bold | 24px | 120–130% |
| 段落見出し | Inter Bold | 16px | 130% |
| 本文 | Inter Regular | 15px | 150% |
| 本文中の強調 | Inter SemiBold | 本文と同じ | — |
| 引用 | Inter Italic | 17px | 135% |

- 文字は左揃えを基本にする。
- ガイドに日本語の書体の指定はない。`template.html` の `--tas-font-*` では、ManropeとInterの後ろに日本語フォント（Hiragino、Noto Sans JP、Yu Gothic、Meiryo）を続けている。
- 読み込みは Google Fonts（Manrope・Interはいずれも SIL Open Font License）。

## ロゴ

ロゴのSVGは `assets/logo/` にある。横組みを優先し、縦組みは横幅が取れない場合だけ使う。

| ファイル | 使う場面 |
|---|---|
| `treasure-ai-horizontal-full-color.svg` | **優先。** 白・ライトグレー・Primary 2 の背景 |
| `treasure-ai-horizontal-white.svg` | 濃い背景（Primary 1 や黒）の上 |
| `treasure-ai-horizontal-one-color.svg` | 単色でしか出せない場面（印刷、単色表示） |
| `treasure-ai-vertical-full-color.svg` | 横幅が足りない場合の代替（背景は全色ロゴと同じ） |
| `treasure-ai-vertical-white.svg` | 縦組みを濃い背景に置く場合 |
| `treasure-ai-vertical-one-color.svg` | 縦組みを単色で置く場合 |
| `treasure-ai-icon-full-color.svg` / `treasure-ai-icon-white.svg` | ダイヤモンドだけを使う小さな箇所（バッジ等）。ロゴの代わりにはしない |

HTMLでは、SVGのマークアップを `<header>` 内にそのまま貼る（`template.html` の方法）。画像ファイルへのリンクにはしない。

**守ること（ブランドガイド p.7–10）**
- 提供されたSVGをそのまま使う。作り直し、色変更、比率変更、回転、影、縁取り、文字の差し替えはしない。
- 写真や画像の上には置かない。
- 周囲に余白を取り、他の要素を入れない。ガイド p.7 は余白をダイヤモンドアイコンの大きさを基準に測ると定めている。数値は未定義なので、アイコンの高さ以上を推奨値とする。
- 単独のダイヤモンドを中央に置くときは、幾何学的な中心より下へ約5%ずらす（ガイド p.10）。
- SVGのviewBoxはロゴの描画範囲に切り詰め済み。CSSでは `width` だけを指定し、`height` は `auto` にする。

## 必ず入れる表記

- ヘッダー左上: 横組みロゴ
- フッター: `Prepared by Treasure Data` と更新日

## 手順

1. 目的、データ、読み手を確認する。他のSkillから呼ばれたときは、その入力を使う。
2. `template.html` をコピーし、`<title>`、ページタイトル、リード文、KPI、表、グラフ、注記を差し替える。
3. ヘッダーのロゴ、フッター、`:root` の変数は変えない。
4. 色は `var(--tas-*)` で指定する。
5. 下のチェックリストを確認する。
6. 出力を渡し、Treasure AI Studioでの表示を確認する。

## チェックリスト

- [ ] ロゴは公式SVGで、横組みを優先している。改変していない
- [ ] ロゴの周囲に余白があり、画像の上に置いていない
- [ ] 色は `--tas-*` だけ。Accent 3は警告とマイナスだけ
- [ ] 見出しはManrope、本文はInter（日本語はフォールバック）
- [ ] フッターに `Prepared by Treasure Data` と更新日がある
- [ ] 外部リソースはGoogle Fontsだけ。外部JavaScriptを読み込んでいない
- [ ] スマートフォン幅（390px程度）で見出しと表が崩れない

## ガイドの注意点（判断して採用した値）

- Secondary 1 は RGB値（132, 123, 142）と HEX（#847BF2）が一致しない。HEXを採用。
- 引用の書体は、本文の説明ではManropeとされ、仕様欄ではInter Italicとされている。仕様欄（Inter Italic）を採用。
- 白いロゴの使用条件（ガイド p.8 右上の例）は明記されていない。濃い背景の上だけに使う。
- 日本語の書体はガイドに含まれない。

## 問い合わせ

ブランドガイドの内容の確認は brand@treasuredata.com（Marketing Creative Services Team）へ。
