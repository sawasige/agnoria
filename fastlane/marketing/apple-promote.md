# Apple「App Store でのプロモーション」申請（developer.apple.com/contact/app-store/promote/）

1.3 が公開されてから出す。フォームの項目に合わせた文案（英語）。

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
