# CLAUDE.md

Agnoria（iOS / iPadOS / macOS の英語 4 択ドリル）で作業するときの決まり。仕様は `docs/SPEC.md`、判断の記録は `docs/SPEC-REVIEW.md`、手順は `README.md` を正とし、ここには運用の決まりだけを書く。

## 変更の流れ

- `main` に直接 push しない。作業ブランチを切って push し、PR を作る。PR の本文に動作確認の手順を書く。
- マージは動作確認が済んでから。確認はユーザーが行う（実機・TestFlight）。OK が出るまで待つ。
- マージはマージコミット（`gh pr merge --merge --delete-branch`）で行う。スカッシュマージとリベースマージは使わない（ブランチのコミット履歴をそのまま残す）。マージしたらリモートとローカルの作業ブランチを消す（残さない）。
- コミットと push は sawasige アカウントで行う（`SAWADA Shigeru <6521997+sawasige@users.noreply.github.com>`）。`gh` は仕事用アカウントから切り替えてから使い、終わったら戻す。
- コミットメッセージ・PR・Issue に AI の帰属（`Co-Authored-By: Claude`、「Generated with Claude Code」など）を書かない。
- Issue にローカルのパスを書かない（他の人には意味がない）。

## コードとビルド

- Xcode 27 / Swift 6（Swift 6 言語モード、MainActor 既定分離）。プロジェクトファイルは Xcode のテンプレートを正とし、XcodeGen などの外部ツールは使わない。
- 依存ライブラリは Firebase（`FirebaseAnalyticsCore` と `FirebaseCrashlytics`）だけ。追加するときは理由を SPEC-REVIEW に書く。
- アプリ内の文字列に「TOEIC」を使わない（商標回避、SPEC §1）。`grep -rn TOEIC Agnoria/` が 0 件であること。ストアの説明文と公開ページで ETS の商標注記付きで触れるのは可。
- UI テスト（撮影用の一時テストを含む）は必ず `XCUIApplication.launchQuiet()` で起動する。Mac から音を出さず、計測も送らないため。一時テストはコミットしない。
- macOS の UI テストはユーザーが Mac を使っている間は動かない（自動化モードのタイムアウト）。Mac はビルドとユニットテスト（`-only-testing:AgnoriaTests`）だけにする。
- xcodebuild が進まないときは待ち続けず、`ps` で CPU を見て止める。
- 変更したら iOS シミュレータでテスト（ユニット + UI）、Mac でビルド + ユニットテストを通してから PR にする。

## リリースと App Store Connect

- ビルドと TestFlight は Xcode Cloud の「Default」ワークフローをユーザーが手動で開始する。こちらから起動しない。
- メタデータとスクリーンショットは `bundle exec fastlane ios upload_metadata`、審査提出は `fastlane ios submit_review build:N`。
- App Store Connect の API キーはリポジトリに置かない。runrun-ios のキーをパスで参照する（Fastfile の `setup_api_key`）。中身を表示しない。
- ストアの文章（説明文、プロモーション、キャプション、リリースノート）は商品説明の調子で書く。開発者の一人称（「〜作りました」）、仕様書の言葉（「必ず 4 択で正誤が出る」）、アプリ内の用語（帯、習得率）は使わない。書いたら必ずプレビューを見せ、ユーザーの OK を得てから App Store Connect に上げる。
- ストアの文章の PR は、文面の OK が出た時点で確認済みとして扱う。App Store Connect に上げる（審査に出す）のと同時にマージし、別に OK を待たない（リポジトリと App Store Connect の内容をずらさない）。
- App Store Connect の Web でしかできない項目（App のプライバシー、審査用連絡先、年齢制限、価格）はユーザーに依頼する。

## 計測（Firebase）

- イベントは `UsageAnalytics` を通す。View から Firebase を直接呼ばない。問題の内容・回答・個人を特定できる情報は送らない。
- Debug ビルドは起動引数 `-analytics YES` を付けたときだけ送る。`GoogleService-Info.plist` はコミットしてよい（公開情報扱い。API キーは Bundle ID で制限済み）。
