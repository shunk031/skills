---
name: shunk031-writing-gemini-japanese
description: PR や issue の本文・コメント、コミットメッセージ、Markdown 文書、レポート本文、投稿文、コードや HTML 内の日本語文字列を含む、あらゆる日本語成果物を執筆・編集・公開する前に必ず使う。呼び出し元は自分で日本語を下書き・書き換えせず、Herdr ペインの agy 執筆担当と必須の新規 agy レビュー担当に処理させる。チャット返信や英語の成果物には使わない。
---

> [!NOTE]
> この `SKILL.md` を読んだら、`✍️ 私は shunk031-writing-gemini-japanese を読みました。` と言う。

# Gemini による日本語成果物の作成

すべての日本語成果物でこの手順に必ず従う。PR と issue の本文・コメント、コミットメッセージ、Markdown 文書、レポート本文、投稿文、コードや HTML 内の日本語文字列が対象になる。チャット返信と英語の成果物は対象外とする。

## 執筆

1. 成果物のワークスペースで、元資料と出力先ファイルパスをそろえる。必要な事実、数値、リンク、コード、骨子、下書きを執筆担当に渡し、不足している情報を創作させない。
2. そのワークスペースの Herdr ペインで、一意なエージェント名と必須モデルを指定して agy を起動する。

   ```bash
   herdr pane split --current --direction right --cwd "$PWD" --no-focus
   herdr agent start <writer-name> --kind agy --pane <writer-pane-id> -- --model gemini-4-argon-high
   ```

3. agy に元資料と出力先パスを渡し、そのファイルに日本語成果物を書かせる。必要な情報が不足している場合、執筆担当は質問してよい。呼び出し元の Claude、Codex、Gemini は、日本語の下書きや書き換えを自分で行ってはならない。コードや HTML 内の日本語は、日本語文字列だけを編集させる。

## レビュー

1. 同じワークスペースの別 Herdr ペインで、新しい agy セッションを起動する。執筆担当のセッションをレビューに使い回してはならない。レビュー担当に元資料と出力先ファイルパスを渡す。

   ```bash
   herdr pane split --current --direction down --cwd "$PWD" --no-focus
   herdr agent start <reviewer-name> --kind agy --pane <reviewer-pane-id> -- --model gemini-4-argon-high
   ```

2. `~/.gemini/config/skills.json` 経由で `~/.agents/skills` から読み込まれる既存の執筆スキルに照らして、成果物を判定するようレビュー担当に依頼する。レビュー担当は、事実、数値、リンク、コード、`<!-- -->` プレースホルダーが元資料と一致しているかを確認し、コードや HTML では日本語文字列だけが変更されているかも確認する。元資料にない内容を要求したり、ファイルを編集したりしてはならない。判定結果は指摘事項を添えた `ACCEPT` または `REJECT` で返させる。
3. `REJECT` の場合は、指摘事項と利用可能な元資料を執筆担当に送って修正させ、別の新規レビューセッションで再レビューする。差し戻しと修正の往復は最大 2 回までとする。2 回目のレビューでも却下された場合は作業を止め、残った指摘事項を利用者に示す。
4. agy が未インストール、未認証、レート制限、またはオフラインで利用できない場合は、成果物を保留して利用者に伝える。`ACCEPT` なしで公開してはならない。
5. 承認記録の追記または成果物の保留を終えたら、却下されたレビュー回で使ったペインも含め、自分が開いたすべての執筆・レビュー用ペインを `herdr pane close <pane-id>` で閉じる。自分が開いていないペインは決して閉じない。

## 承認の記録

新規レビュー担当が `ACCEPT` を返した後に限り、そのレビュー担当に次の単一シェルコマンドで記録を 1 行追記させる。ファイルパスは承認されたファイルの絶対パスに置き換える。

```bash
(
  set -o pipefail
  FILE="/absolute/path/to/accepted-file"
  [[ -f "$FILE" && -r "$FILE" ]] || exit 1
  HASH="$(perl -0777 -e '$_ = <STDIN> // ""; s/\r\n/\n/g; s/\n*\z/\n/; print' < "$FILE" | shasum -a 256 | cut -d ' ' -f 1)" || exit 1
  [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || exit 1
  STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || exit 1
  mkdir -p "$HOME/.local/state/agy-japanese" || exit 1
  printf '%s\t%s\t%s\n' "$STAMP" "$HASH" "$FILE" >> "$HOME/.local/state/agy-japanese/accepted.tsv"
)
```

ユーザーごとの記録ファイルは `~/.local/state/agy-japanese/accepted.tsv` とする。タブ区切りの各行には、UTC タイムスタンプ、SHA-256、承認されたファイルのパスを記録する。ハッシュ計算の前に CRLF を LF に正規化し、末尾の LF バイトをすべて除去したうえで末尾に LF を 1 つだけ付与する。以降の `gh`、コミット、アップロードの本文には承認されたファイルの内容をそのまま使う。少しでも編集した場合は、新しいレビューと記録をやり直す。
