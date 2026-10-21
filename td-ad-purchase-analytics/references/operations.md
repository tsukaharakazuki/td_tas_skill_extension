# 構築・更新・復旧

## ローカル初期化
```bash
python3 -I <skill_dir>/scripts/init_project.py --workspace <workspace> --name <project_slug> --dry-run
python3 -I <skill_dir>/scripts/init_project.py --workspace <workspace> --name <project_slug>
```

`Project/` がなければ作り、その中の新しいプロジェクトだけを作る。既存projectは上書きしない。更新では既存MEMORYを読む。既存フォルダへ再初期化しない。

1. `references/hearing.md` に沿って不足情報を確認する。
2. `config/project.json` に合意済み設定を保存する。adapter SQLを調査結果に基づいて編集する。`configured: true` は確認完了後にだけ設定する。
3. `dashboard_template/SKILL.md` と `template.html` を読む。バンドル版のcommit/hashは `references/dashboard.md`。remote最新版へ差し替えるときは、別の空フォルダへ取得・レビューし、両方を同じcommitにpinし直す。
4. `validate_project.py <project> --compile-config` で設定を検証してparamsを生成する。失敗したらpushしない。
5. `.dig` のtimezoneはproject設定と一致させる。v1はscheduleなし。日次自動実行やAgent登録は別途承認する。

## TDに接続する前の確認
`tdx-skills:tdx-basic` と `workflow-skills:digdag`、管理時は `tdx-skills:workflow` を読む。

- 現在のTreasure Workアカウントを維持する。`--profile`、`tdx profile use`、projectのsite/profile指定で別アカウントへ切り替えない。
- `tdx.json` は `workflow_project` と `database` だけを記録する。リージョンは現在のアカウントから確認し、勝手にus01/jp01と仮定しない。
- 実在するoutput DBを使う。新規DB作成、既存同名Workflowの置換は対象を確認して承認を得る。
- 初回は全保持ログ、更新も全再構築。スキャン規模と出力テーブル数を説明する。過去成功テーブルの削除は含まない。
- 認証エラーはSettingsのAdd Account/Re-authenticateへ案内する。ユーザーへ端末でのログインを依頼しない。

## push / run
CLIはバージョンごとにhelpを確認し、不明なフラグを推測しない。

1. まず付属の `validate_project.py` でローカル検証する。`tdx wf validate` は導入CLIに存在する場合だけ使用する（2026-10-21の作成環境ではwfのhelpに掲載なし）。不在のサブコマンドを成功したかのように報告しない。CLIのpush時検証等の利用可能な検証手段をhelpで確認する。いずれもサーバーでのSQL成功を保証しない。
2. pushの差分を確認し、対象project・既存Workflowへの影響を説明して承認後に `tdx wf push`。
3. `tdx wf run <project_name>.ad_purchase_analytics --dry-run` を先に行う。operator、入力/出力、外部通知がないこと、走査範囲、費用見込みを説明する。
4. **明示的な承認を得てから**非dry-run実行。外部送信operatorを追加した場合は宛先・対象人数も説明する。実行時 `-p` による上書きは使わない。configを編集して検証・pushし直す。
5. attemptが成功するまで監視する。正常終了だけでなく同一attemptの `qa.hard_errors=0` と `complete` の1行を確認する。

`tdx wf run` のdry-runはコスト見積もりでもSQL実行試験でもない。dry-run成功だけをもって「検証済み」と言わない。

## 成功後のdashboard更新
1. `run_id=<session_unixtime>_<attempt_id>` を確定する。同じrun_idのcohort/inflow/lookback/qa/completeだけを読み出す。
2. 出力取得の既定40行制限に注意する。CLIのexport/outputや十分なlimitで全行数を照合する。切れた結果は描画しない。
3. 会員ID・Cookie・生URLをブラウザへ渡さない。lookbackもsource別の注文数/売上等に**集約してから**取得する。
4. `references/dashboard.md` のJSON bundleを作る。QAの同一runを確認し、`config_sha256`を記録する。`render_dashboard.py`を実行する。
5. 新しいrunのHTMLを開き、desktop/390px・NULL表示・全体と施策別の整合を確認する。
6. 承認されたローカル更新だけ `--promote` を使い、`dashboard_output/index.html` と `runs/latest_success.json` を置き換える。失敗時は前回成功を保つ。
7. project MEMORYの成功履歴と `Project/MEMORY.md` の索引を更新する。

## 再実行と保持
- 同じattempt内の手動再実行は原本が変わる可能性がある。v1では新しいattemptから全再構築する。タスク途中からの再開・既存runの追記を通常更新に使わない。
- 重複起動を避ける。古いrunを新しいrunの後でpromoteしない。rendererも新旧順を確認する。
- 前回成功の入力最古時刻より今回の最古時刻が後退した場合、履歴保持切れを確認する。全件数の減少、異常な初回獲得急増も確認する。再現に必要な元データ保持がない場合は止める。
- 同一時刻境界、SDK session ID再利用、イベントID重複、受信時刻とイベント時刻の遅延を実データでテストする。
- 不要な試行別テーブルの削除・保存期間設定は別の承認対象。active runを削除しない。

## MEMORYの範囲
プロジェクトの設定・意思決定は `Project/<project>/MEMORY.md` が正本。グローバルの個人MEMORYへ顧客データを横流ししない。この仕様自体はSkillに書かれているので、グローバルMEMORYへ重複保存しない。必要な場合だけ、非機密なprojectメモへのポインタをユーザーの同意のもと保存する。

作成 Treasure Work
