Treasure Data 接続キット（Claude アプリ用 / オフライン導入）
================================================================

このキットを使うと、Claude アプリから Treasure Data を操作できるようになります。
registry.npmjs.org への通信は不要です。Treasure Data のドメインだけで動きます。


■ 事前に必要なこと（Claude の組織管理者の方）

  1. Claude のネットワーク許可（管理者設定 → Capabilities）に次を追加
       *.treasuredata.com
       *.treasuredata.co.jp
     ※ registry.npmjs.org は不要です

  2. Claude アプリにプラグイン「td-claude2tdx-connect」がインストールされていること


■ セットアップ手順（5分ほど）

  1. この zip を展開し、中の「TreasureAI」フォルダを
     ドキュメントなど分かりやすい場所に置きます。

  2. TreasureAI フォルダの中の「tdx_key.txt」をメモ帳で開き、
       1行目: Treasure Data の API キー
       2行目: リージョン（日本の場合の例: ap01。us01 の場合は省略可）
     を書いて上書き保存します。

  3. Claude デスクトップアプリで、メッセージ欄の横の「+」→「フォルダを追加」から
     TreasureAI フォルダを接続します。

  4. Claude に「TDに繋ぎたい」と話しかけます。
     Claude が次の順に案内します。
       ・環境の診断（「プラン C：オフライン一式」が推奨として表示されます）
       ・操作範囲の選択（参照のみ / SQL 書き込み可 など）
       ・導入と検証


■ ご注意

  ・API キーをチャット欄に貼らないでください。会話履歴に残ります。
    貼ってしまった場合は、Treasure Data の管理画面でそのキーを無効化し、作り直してください。
  ・tdx_key.txt をメモ帳で保存するとき、文字コードは「UTF-8」のままにしてください。
    「UTF-8 (BOM 付き)」を選ぶとキーが正しく読めません。
  ・tdx-bundle-*.tgz と同名の .sha256 は、どちらも消したり書き換えたりしないでください。
    導入時にこの2つを照合し、一致しない場合は安全のため導入を中止します。
  ・Claude からできる操作の最終的な範囲は、API キーの Treasure Data ユーザー権限で決まります。
    用途に合わせて権限を絞ったユーザーのキーをお使いください。


■ セキュリティ審査用の資料（review フォルダ）

  package-lock.json  含まれる全パッケージと、それぞれのハッシュ
  sbom.cdx.json      SBOM（CycloneDX 形式）
  audit.txt          既知の脆弱性レポート（npm audit）
  signatures.txt     全パッケージのレジストリ署名の検証結果
