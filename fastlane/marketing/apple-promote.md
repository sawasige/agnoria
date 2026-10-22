# Apple のフィーチャー申請（App Store Connect → アプリ → フィーチャー → ノミネート）

旧フォーム（developer.apple.com/contact/app-store/promote/）は廃止され、「Getting featured」の案内に転送される。申請は App Store Connect の「ノミネート」で行う（名前 → タイプ → 説明 1000 字 → 公開日 → 詳細ページで プラットフォーム・役立つ情報 500 字・補足資料のリンク → 提出）。Apple はリリースの 3 週間前までの申請を勧める。

- 1.3: 2026-10-22 に「アプリの機能強化」で提出済み（ノミネート ID 859ed7b2-1471-4daa-bd7c-0a6d574d3e8c）。返事は来ない。採用されると App Store Connect のアプリに通知
- 1.4: 2026-10-22 20:22 に「アプリの機能強化」で提出（ノミネート ID 09fd5f79-b8c5-462a-8c8f-73f35f6fd770）。Web の「ノミネートを作成」が「下書きの数が上限に達しました」（API では下書き 0 件）で開けなかったので、App Store Connect API（POST /v1/nominations → PATCH submitted: true）で 1.3 と同じ形（APP_ENHANCEMENTS、iPhone + iPad、ja、全 175 地域、プレスキットのリンク）で作った。名前「Agnoria 1.4 iPhone Duo 対応（全ポーズに最適化）」、公開日 2026-10-24。文面は下の「1.4」
- 1.5 以降: 提出の 3 週間前に出す

## 1.4（iPhone Duo 対応）の文面

説明（997 字）:

Agnoria is a free, ad-free English drill for learners in Japan aiming at 450 to 600 on the TOEIC L&R test. Its premise: people quit when they cannot feel themselves improving, so every answer visibly adds to what the learner has mastered, and clearing a score stage is celebrated. Open the app, tap “10 questions,” done in three minutes. Progress runs through four score stages for vocabulary, grammar and question-response listening.

Version 1.4 is optimized for iPhone Duo in every pose. Built with the iOS 27.1 SDK, it adapts to the available space rather than checking device or orientation: on the inner display and in landscape, the quiz shows progress and the explanation on the left and the question and choices on the right, so the answer and why it is right are visible without scrolling; on the outer display the bars are slimmed down and the explanation scrolls into view automatically. iPhone now supports landscape too. The product page has iPhone Duo screenshots for both displays.

役立つ情報（481 字）:

Optimized for iPhone Duo in all poses: closed (outer display), open (inner display), portrait and landscape, half-folded. Layout adapts to available width and height per Apple’s iPhone Duo guidance (no idiom or orientation checks). Built with Xcode 27.1 / iOS 27.1 SDK, SwiftUI, SwiftData + CloudKit, WidgetKit, Foundation Models (on-device), AVSpeechSynthesizer, Liquid Glass. Version 1.4 submitted for review Oct 22, 2026. Japanese-language app, Japan storefront. Solo developer.

以下は説明欄に使った文案（英語）。

- App name: Agnoria
- App Store link: https://apps.apple.com/jp/app/id6823061416
- Availability: Japan（Japanese）
- Release / update date: 1.3 の公開日

## Tell us about your app（300 語以内）

Agnoria is a free, ad-free English drill for learners in Japan aiming at 450 to 600 on the TOEIC L&R test. Its premise is that people quit when they cannot feel themselves improving, so every answer visibly adds to what the learner has mastered, and clearing a score stage is celebrated. You open the app, tap “10 questions,” and answer: the app mixes new items, recent misses and things you haven’t seen in a while, matched to your level. A set takes about three minutes. Progress runs through four score stages (450, 500, 550, 600), tracked separately for vocabulary, grammar and question-response listening, so learners always see where they are and how many questions remain to the next stage.

Version 1.3 adds Part 2-style question-response listening: a short question and three replies are spoken by the device’s speech synthesis, with different voices and accents (US, UK, Australian) for the question and the replies, and the text is revealed only after answering.

## Which Apple technologies does your app use?

- Apple Intelligence / Foundation Models framework: on-device rephrasing of grammar explanations and generation of practice questions, with guided generation (@Generable). Nothing leaves the device.
- Liquid Glass (iOS 26 design): glass cards, buttons and the fixed action bar; cards lift and tilt when swiped to the next question.
- SwiftUI + SwiftData with CloudKit: learning records sync privately across iPhone and iPad.
- WidgetKit: Home Screen widget with the day’s status, streak and stage progress.
- AVSpeechSynthesizer: question-response listening with per-item voice and accent selection.
- UserNotifications: a daily reminder only on days the learner hasn’t studied.
- Swift 6 language mode, Xcode Cloud for CI and TestFlight.

## Why feature it?

It is a small, focused app built entirely with current Apple frameworks, with no accounts, no ads and no third-party servers, aimed at a large and underserved group: first-time TOEIC takers and people who gave up before. The listening mode is built on the system voices rather than recordings, so it works offline and keeps the app small.
