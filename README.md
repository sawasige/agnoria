# Agnoria

**Agnoria（アグノリア）** は、スコア帯 450→600 点を目指す学習者向けの英語 4 択ドリルアプリです。単語と Part5 形式の文法を 10 問 1 セットで繰り返し、苦手な問題を自動で優先して出題します。

> 名前はギリシャ語 *Agnoia*（無知）と、ローマの女神 *Agenoria*（子どもに学ぶ力を授ける）から。「無知から学び始める」の意。

- 対応 OS: iOS / iPadOS 27 以上、macOS 27 以上（ネイティブ SwiftUI の 1 ターゲット）
- 広告なし・課金なし・アカウントなし。全データをバンドル同梱。開発者のサーバーとは通信しない
- 依存ライブラリは Firebase（Analytics と Crashlytics）だけ。機能の利用回数とクラッシュ情報の送信で、問題の内容や回答は送らない

## 特徴

- **必ず 4 択で正誤が出る**: 「わかる／わからない」の自己申告ではなく、誤答を含む選択肢で判定する
- **回答後は左スワイプでも次へ**: 画面のどこでも左にスワイプするとカードをめくるように次の問題へ。下に次のカードが見えるが問題文は伏せ字
- **おまかせ出題**: 単語・文法をまたいで、未回答 → 直近で間違えた問題 → 放置した問題の順に重み付きで 10 問を選ぶ。卒業した問題も時間が経てば復習に回る
- **ステージ**: スコア帯を 450 → 500 → 550 → 600 の順に進む。帯の習得率が 80% で次の帯が開く。設定で手動変更も可。**帯をクリアすると、女神が喜ぶ専用画面と紙吹雪・ファンファーレで祝う**
- **単語は 1 語から 3 形式**: 意味を選ぶ / 例文の穴埋め / 日→英。穴埋めは語尾変化（-s, -ed, -ing, -ly など）も検出する
- **ホームはダッシュボード**: 今の帯の習得率とクリアまでの目安（セット数・日数）、連続日数と今日の回答、直近 14 日の推移、復習待ちの件数だけを表示。学習の入口は画面下の「おまかせで10問」と「分野」の 2 ボタン
- **進捗の可視化**: 習得・学習中・苦手・未学習の 4 段階を積み上げバーで表示。分野別の内訳は進捗画面（Swift Charts）で確認できる
- **音**: 正解・不正解の効果音（グロッケンとマリンバの短い音）と帯クリアのファンファーレ、例文の読み上げ（en-US）。どちらもマナーモードに従う
- **女神 Agenoria**: アイコンと同じキャラクターがホームのヘッダーに立ち、結果画面では成績に応じて表情が変わる
- **Liquid Glass UI**: メッシュグラデーション背景とガラス効果のカード・ボタン。ダークモード、Dynamic Type、VoiceOver に対応
- **解説**: 単語は意味・例文・和訳、文法は空欄を正解で埋めた英文（正解太字）・和訳・解説
- **Apple Intelligence（任意）**: 対応端末では文法解説の言い換えと、単語穴埋めの類題生成（例文・誤答・和訳）ができる。非対応端末では該当 UI を表示しない
- **Mac**: 選択肢は `1`〜`4` キー、次へは Return、やめるは Esc
- **ウィジェット**（iOS）: 連続日数と今日の状態（small）、今の帯の習得率と 4 帯の並び（medium）。アプリが App Group に書いた写しを表示する
- **iCloud 同期**: 学習の記録（正誤・ブックマーク・セット）を iCloud のプライベートデータベースで端末間に同期する。問題データは同期しない。起動引数 `-cloudSync NO` で切れる（UI テストはこれで起動）

## 開発環境

- Xcode 27 / Swift 6（Swift 6 言語モード、Approachable Concurrency、MainActor 既定分離）
- SwiftUI + SwiftData、MV アーキテクチャ（View + `@Observable` のストア）
- テストは Swift Testing（`import Testing`）
- Bundle ID: `com.himatsubu.Agnoria`

プロジェクトファイルは Xcode 27 の Multiplatform App テンプレートから生成したものを正とし、XcodeGen などの外部ツールは使いません。テンプレートからのビルド設定の変更は Bundle ID / Team、対応デバイス、Swift 6 言語モードのみです。ソースとリソースは synchronized folder なので、ファイルを置くだけで Xcode に反映されます。

### ビルドとテスト

```sh
# iOS Simulator
xcodebuild -project Agnoria.xcodeproj -scheme Agnoria \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Agnoria.xcodeproj -scheme Agnoria \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# macOS
xcodebuild -project Agnoria.xcodeproj -scheme Agnoria -destination 'platform=macOS' build
xcodebuild -project Agnoria.xcodeproj -scheme Agnoria -destination 'platform=macOS' test
```

### Firebase の設定ファイル

利用状況の計測とクラッシュ報告（SPEC §7.1）は `Agnoria/GoogleService-Info.plist` があるときだけ動きます。このファイルはリポジトリにコミットしてあります（中身は Google が公開情報として扱うもの。API キーは Bundle ID で制限）。無いビルドでは計測が無効のまま普通に動きます。Debug ビルドは起動引数 `-analytics YES` を付けたときだけ送信します。`-debugCrash YES` を付けると Crashlytics の確認用にわざと落ちます（Debug のみ）。

### 実機へのインストール

```sh
UDID=$(xcrun devicectl list devices | grep -i iPhone | grep connected | awk '{print $(NF-2)}')
xcodebuild -project Agnoria.xcodeproj -scheme Agnoria \
  -destination "platform=iOS,id=$UDID" -allowProvisioningUpdates build
APP=$(xcodebuild -project Agnoria.xcodeproj -scheme Agnoria \
  -destination "platform=iOS,id=$UDID" -showBuildSettings | awk '/BUILT_PRODUCTS_DIR/{print $3; exit}')/Agnoria.app
xcrun devicectl device install app --device "$UDID" "$APP"
xcrun devicectl device process launch --terminate-existing --device "$UDID" com.himatsubu.Agnoria
```

## ディレクトリ構成

```
Agnoria/
  App/        エントリポイント、AppModel（画面遷移・セット実行・履歴）、QuizRun
  Models/     SwiftData モデル、出題条件（DrillMode / QuizConfig）、スナップショット
  Logic/      純粋ロジック: 穴埋め、優先度、セット生成、習得段階、ステージ、連続日数、クリアまでの目安
  Data/       バンドル JSON の読み込みと SwiftData への取り込み（内容が変わったときのみ）
  Services/   設定、音声セッション、効果音、読み上げ、Foundation Models、利用状況の計測とクラッシュ報告（UsageAnalytics）
  Views/      Home / Quiz / Result / Settings / Stats と共通部品（Shared）
  Resources/  Data/words.json, Data/grammar.json, Sounds/correct.caf, Sounds/wrong.caf
AgnoriaWidget/    ウィジェット拡張（WidgetKit。Shared/ の WidgetSnapshot を読むだけ）
Shared/           アプリと拡張の両方に入れる型（WidgetSnapshot）
AgnoriaTests/     ユニットテスト（Swift Testing）
AgnoriaUITests/   UI テスト（`XCUIApplication.launchQuiet()` で効果音と読み上げを切って起動する。テスト中に Mac から音を出さないため）
docs/             仕様書と設計判断の記録
ci_scripts/       Xcode Cloud のスクリプト（アーカイブ後に dSYM を Crashlytics へ送る）
```

## 問題データ

`Agnoria/Resources/Data/` に単語 400 語・文法 200 問を同梱しています（各スコア帯 100 語 / 50 問）。形式は [docs/SPEC.md](docs/SPEC.md) §2.1 を参照してください。

データを追加・修正するときの約束:

- すべてオリジナル問題。市販教材の転載や言い回しを変えただけの改変は不可
- 単語の `distractors` は意味が近い日本語の誤答 3 つを人手で作る
- 単語の綴りは全体で一意にする。`example` に `word`（または規則変化形）が含まれないと穴埋め形式が作れない
- `level` は 450 / 500 / 550 / 600 のいずれか
- アプリ内（`Agnoria/` 配下）に「TOEIC」の文字列を含めない。テストと `grep -rn TOEIC Agnoria/` で確認する

JSON を変えると次回起動時に SHA-256 で差分を検出し、バックグラウンドで取り込みます。学習履歴は問題 ID で紐づくため、問題を更新しても消えません。

## ドキュメント

- [docs/SPEC.md](docs/SPEC.md): 仕様書（v1.3）。データ形式、出題ロジック、画面、完了条件
- [docs/SPEC-REVIEW.md](docs/SPEC-REVIEW.md): 仕様の精査メモと各バージョンでの設計判断

## 未完了・既知の事項

- 生成した問題データ（既存 80 問を除く 520 問）は内容未レビュー。おかしい問題はブックマークして後で直す運用
- Dynamic Type の最大サイズでのレイアウトは未確認
