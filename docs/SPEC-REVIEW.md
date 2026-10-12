# SPEC v1 精査メモ（2026-10-12）

`docs/SPEC.md` v1 を実装前に精査した結果と、v1.1 で採った決定。コードは決定どおりに実装済み。

## A. 仕様と前提の不一致

| # | 箇所 | 問題 | 決定 |
|---|---|---|---|
| A1 | §0 対応OS / §1 | 仕様は「iOS 27 / iPhone 縦のみ」だが、対象は **iPhone・iPad・Mac**。 | 1ターゲットのマルチプラットフォーム（iOS/iPadOS 27 + macOS 27、ネイティブ SwiftUI）。Mac Catalyst は不採用。iPhone は縦固定、iPad は全方向（`TARGETED_DEVICE_FAMILY = 1,2`）。iPadOS 26 以降 `UIRequiresFullScreen` は非推奨で、iPad はウィンドウのリサイズに応じる前提のため、幅に応じた列数と最大幅 720pt で対応。 |
| A2 | §8 初期データ | `questions_sample.json`（文法30問）がどこにも存在しない。`words_sample.json` は `~/Downloads` にあった。 | 文法30問（5分野×6問、level 450〜600）を新規作成して `grammar.json` に。単語50語は `words.json` としてそのまま採用。ファイル名は §2.1 の `grammar.json` / `words.json` に統一。 |
| A3 | §5 プロンプト vs §10 | Foundation Models への指示文「TOEIC 450点の学習者向けに…」をそのまま実装すると、バイナリ内に `TOEIC` 文字列が入り §10 の grep 条件に違反する。 | 指示文を「ビジネス英語を学び始めた初中級（スコア帯450点前後）の日本語話者」に変更。`grep -rn TOEIC Agnoria/` が空であることを確認済み。 |
| A4 | §6 音声 | `.playback` カテゴリは `AVAudioSession` のもので **macOS には存在しない**。 | `#if os(iOS)` で囲む。Mac ではシステム音量に従う。 |
| A5 | §7 vs §2.1 | 「JSON取り込みは初回のみ」と「JSONを修正したら次回起動時に反映」が矛盾。 | 毎起動時に JSON の SHA-256 を計算し、前回取り込み時と違うときだけバックグラウンドで upsert。同じならスキップ（1秒以内の起動要件を満たす）。 |
| A6 | §4.4 設定 | 「450〜600 の範囲スライダー」は SwiftUI 標準に無い（独自実装が必要）。 | 4段階それぞれのトグル（最低1つは ON）。実質同じ絞り込みができ、Dynamic Type・VoiceOver も標準で済む。 |

## B. ロジックの穴

| # | 箇所 | 問題 | 決定 |
|---|---|---|---|
| B1 | §3.1 cloze | 「先頭一致で置換」だと、`in` が `invoice` の先頭に、`port` が `report` 内にマッチして誤置換する。 | 完全一致 → 規則変化（-s/-es/-ed/-ing/-ly、-e脱落、-y→-ies、子音重ね）のみ許可。語長3未満は活用形マッチ対象外。テストで `in`/`invoice` の非マッチを固定。 |
| B2 | §3.1 誤答抽出 | フォールバックは「level を外す」までしか無いが、サンプルでは **前置詞が1語**しかなく、同 pos で3語確保できない。 | 同 pos・同 level → 同 pos → 全体、の3段。さらに同じ `meaning`／同じ綴りの語は誤答から除外（正解が2つになる事故を防ぐ）。 |
| B3 | §3.1 cloze | 例文に `word` が見つからない語は「cloze 対象外」とあるが、その場合に何を出すか未定義。 | その語は `meaning` 形式にフォールバックして出題数を減らさない。 |
| B4 | §4.2 途中離脱 | 「セット破棄」とあるが、§3.3 は回答ごとに Progress を即時記録する。どちらを優先するか曖昧。 | 回答済みの Progress は残す（学習は無駄にならない）。`Session` だけ保存しない（連続日数には数えない）。離脱ダイアログにその旨を表示。 |
| B5 | §2.2 Progress | `GrammarQuestion` と `Word` の両方から 1:1 で `Progress` を持つと、SwiftData では Progress 側に2本の optional 逆参照が必要になり不自然。 | `ItemProgress` を独立モデルにし `itemID`（unique）で紐づける。問題の更新・アーカイブ・再登場で履歴が消えないことをテストで確認。`Progress` という名前は Foundation の `Progress` と衝突するため `ItemProgress` に。 |
| B6 | §2.2 Session.results | `SessionResult` をリレーションにする必要がない。 | Codable 構造体の配列として `StudySession` に埋め込む。 |
| B7 | §4.1 下部ボタン | 「間違えた問題」「ブックマーク」の件数が単語・文法どちらの集計か未定義。 | 現在選択中のセグメント（単語 or 文法）の件数。出題もそのモードのみ。 |
| B8 | §4.4 レベル絞り込み | 絞り込みで対象が0件になったときの挙動が未定義。 | タイルは `0件` で disabled。開始時に0件ならアラートで「レベルを広げるか別の分野を」と案内。 |
| B9 | §5 言い換え | 単語の「解説」は意味＋例文＋和訳で、言い換える対象が無い。 | 「別の言い方で」は文法の `explanation` にのみ表示。 |

## C. Mac 対応で追加したもの（仕様外・最小）

- 選択肢に `1`〜`4` キー、`次へ` に Return、`×` に Esc のキーボードショートカット。
- ウィンドウ最小サイズ 480×640、既定 560×820。
- ツールバー配置は `.cancellationAction` / `.primaryAction` を使い、iOS では左上 `×`・右上ボタン群として表示。
- App Sandbox を有効化（通信なしなので追加の entitlement は不要）。
- 1ウィンドウのアプリなので macOS では `WindowGroup` ではなく `Window` シーン（File > New Window が付かない）。最後のウィンドウを閉じたら終了。Edit（取り消し・ペーストボード）、View > ツールバー、Help の既定メニュー項目は外す。

## D. 未解決・要判断（ユーザー向け）

1. ~~Bundle ID / Team~~ → 設定済み: `com.himatsubu.Agnoria`（テストは `com.himatsubu.AgnoriaTests`）、`DEVELOPMENT_TEAM` は RunRun と同じ。
2. **アプリアイコン**: `AppIcon.appiconset` は空。1024×1024 の画像を入れる。
3. **文法30問の内容確認**: 原則どおり自作だが、正解の一意性は人の目でも一度見てほしい（`docs/` ではなく `Agnoria/Resources/Data/grammar.json`）。
4. **Foundation Models の動作確認**: シミュレータ／Mac で Apple Intelligence が有効なときだけ UI が出る。非対応環境ではボタン自体が表示されないのが正常。
5. ~~Xcode プロジェクトの管理~~ → XcodeGen は廃止（2026-10-12）。Xcode 27 のテンプレートで作り直し、`.xcodeproj` を直接管理する。XcodeGen 時代との主な違い: synchronized folders、生成 Info.plist、`ENABLE_APP_SANDBOX` ビルド設定、Swift 5 言語モード + MainActor 既定分離、UI テストターゲット付き。

## E. 完了条件の確認結果

`docs/SPEC.md` §10 を参照。ビルド・テストの実行結果は本メモの末尾に追記する。

## F. 実行結果（2026-10-12, Xcode 27.0 / macOS 27.0.1）

| コマンド | 結果 |
|---|---|
| `xcodebuild -scheme Agnoria -destination 'platform=iOS Simulator,name=iPhone 17' build` | BUILD SUCCEEDED |
| `xcodebuild -scheme Agnoria -destination 'platform=macOS' build` | BUILD SUCCEEDED |
| `xcodebuild -scheme Agnoria -destination 'platform=iOS Simulator,name=iPhone 17' test` | 41 tests / 10 suites passed |
| `xcodebuild -scheme Agnoria -destination 'platform=macOS' test` | 41 tests / 10 suites passed |
| `grep -rn TOEIC Agnoria/` | 該当なし |
| iPhone 17 シミュレータで起動 | ホーム表示・データ取り込み（単語50 / 文法30）を確認 |

未確認: 実機、Dynamic Type 最大サイズでの目視、Foundation Models の実動作（Apple Intelligence 有効環境が必要）。
