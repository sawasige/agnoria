# Agnoria — 仕様書 v1.1

> v1 からの変更点は `docs/SPEC-REVIEW.md` 参照。本文中の **[v1.1]** が変更箇所。

## 0. 概要

| 項目 | 内容 |
|---|---|
| アプリ名 | **Agnoria**（アグノリア） |
| 由来 | ギリシャ語 Agnoia（無知）＋ ローマの女神 Agenoria（子どもに学ぶ力を授ける）。「無知から学び始める」の意 |
| 目的 | TOEIC 450→600点帯の学習者が、スキマ時間に **単語** と **Part5形式の文法** を4択ドリルで繰り返す |
| 対象 | まず開発者自身。あわよくば App Store 公開 |
| 対応OS | **[v1.1]** iOS 27 以上（iPhone 縦画面のみ。iPad は後回し）/ macOS 27 以上（ネイティブ SwiftUI の1ターゲット。Mac Catalyst は使わない） |
| 通信 | なし。全データをバンドル同梱。広告なし、課金なし、アカウントなし |
| 商標回避 | アプリ名・Bundle ID・画面内の固定文言に「TOEIC」を使わない。App Store 説明文で「TOEIC対策に」と触れる程度は可 |

### 既存アプリへの不満（＝設計の軸）
- 「わかる／わからない」の自己申告は、自信のない単語を判定できない → **必ず4択で正誤が出る**
- 分野を狙って繰り返したい → **分野タイルから10問セットを何度でも**

---

## 1. 技術スタック

- Swift 6 / SwiftUI / SwiftData
- Deployment Target: iOS 27.0 / macOS 27.0 **[v1.1]**
- アーキテクチャ: MV（View + @Observable のストア）。MVVM にはしない。画面数が少ないため
- 依存ライブラリ: なし（SPM 追加禁止。標準フレームワークのみ）
- Foundation Models（Apple Intelligence）: 任意機能として利用。非対応端末では該当UIを非表示
- AVSpeechSynthesizer: 例文読み上げ（en-US）
- プロジェクト生成: XcodeGen（`project.yml` → `xcodegen generate`）。**[v1.1]** 以下がすべて通ることを完了条件とする
  - `xcodebuild -scheme Agnoria -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - `xcodebuild -scheme Agnoria -destination 'platform=macOS' build`
  - 上記2つの destination で `xcodebuild ... test`
- テスト: Swift Testing（`import Testing`）。出題ロジック・復習ロジック・JSON読み込みにユニットテストを付ける

---

## 2. データ

### 2.1 バンドルJSON

`Agnoria/Resources/Data/` 配下に `grammar.json` / `words.json` を置く。起動時に SwiftData へ取り込む。

#### `grammar.json`（Part5 文法）
```json
{
  "id": "pos-001",
  "category": "品詞",
  "question": "The manager asked the team to submit their reports ______.",
  "choices": ["prompt", "promptly", "promptness", "prompted"],
  "answer": 1,
  "explanation": "動詞 submit を修飾するので副詞 promptly。-ly は副詞の目印。",
  "level": 500
}
```
- `answer` は `choices` のインデックス（0始まり）
- `category` は以下の5種（v1）: `品詞` / `前置詞・接続詞` / `語彙` / `時制・態` / `代名詞・関係詞`
- `level` は 450 / 500 / 550 / 600 の4段階（目安スコア帯）

#### `words.json`（単語）
```json
{
  "id": "w-0001",
  "word": "invoice",
  "pos": "名詞",
  "meaning": "請求書",
  "example": "Please pay the invoice within 30 days.",
  "example_ja": "30日以内に請求書をお支払いください。",
  "distractors": ["領収書", "見積書", "契約書"],
  "category": "ビジネス一般",
  "level": 450
}
```
- `distractors` は **意味が近い日本語の誤答3つ**（人手で作成。ランダム語は不可）
- `category` は以下の5種（v1）: `ビジネス一般` / `人事・採用` / `会議・連絡` / `店舗・顧客` / `混同しやすい語`
- `pos` は `名詞` / `動詞` / `形容詞` / `副詞` / `前置詞` / `接続詞`

#### 取り込みルール
- `id` を主キーに upsert。JSON側で問題文を修正したら次回起動時に反映される
- 学習履歴（正誤・ブックマーク）は `id` に紐づくので、問題を更新しても履歴は消えない
- JSON に存在しなくなった `id` は削除しない（履歴保護）。`isArchived = true` にして出題対象から外す。再び JSON に現れたら `isArchived = false` に戻す
- **[v1.1]** 取り込みは毎起動時にバックグラウンドで行うが、2ファイルの SHA-256 が前回取り込み時と同じならスキップする（UserDefaults に保存）

### 2.2 SwiftData モデル

```
GrammarQuestion
  id: String (unique)
  category, question, choices: [String], answer: Int, explanation, level: Int
  isArchived: Bool

Word
  id: String (unique)
  word, pos, meaning, example, exampleJa, distractors: [String], category, level: Int
  isArchived: Bool

ItemProgress              // [v1.1] リレーションではなく itemID で紐づける独立レコード
  itemID: String (unique) // GrammarQuestion.id または Word.id
  recentResults: [Bool]   // 直近3回の正誤。古い順。最大3件
  totalCorrect: Int
  totalAnswered: Int
  isBookmarked: Bool
  lastAnsweredAt: Date?

StudySession              // 1セット＝10問の記録。完走したときだけ保存
  id: UUID
  startedAt, finishedAt: Date
  mode: String            // "grammar" / "word"
  category: String?       // nil = ミックス
  questionFormat: String? // 単語のとき: "meaning" / "cloze" / "jaToEn"
  results: [SessionResult]  // [v1.1] Codable 構造体の配列として埋め込む

SessionResult
  itemID: String
  isCorrect: Bool
  chosenIndex: Int
  elapsedMs: Int
```

---

## 3. 出題ロジック

### 3.1 単語の出題形式（1語から3形式を自動生成）

| 形式 | 問題 | 選択肢 | 誤答の出どころ |
|---|---|---|---|
| `meaning` 意味を選ぶ | `invoice` | 請求書 / 領収書 / 見積書 / 契約書 | `distractors` |
| `cloze` 例文穴埋め | `Please pay the ______ within 30 days.` | invoice / receipt / estimate / contract | 同じ `pos`・同じ `level` の他の単語から3語をランダム抽出 |
| `jaToEn` 日→英 | 請求書 | invoice / receipt / estimate / contract | 同上 |

- `cloze` は `example` 中の `word` を `______` に置換。**[v1.1]** 完全一致（大文字小文字無視）→ 規則的な語尾変化（-s/-es/-ed/-d/-ing/-ly、-e 脱落、-y→-ies、子音重ね）の順に探す。単純な先頭一致はしない（`in` が `invoice` に化けるため）。見つからなければその語は `meaning` 形式で出す
- 誤答抽出は **[v1.1]** 同 `pos`・同 `level` → 同 `pos` → 全単語 の順に条件を緩める。自分自身・同じ綴り・同じ `meaning` の語は除く

### 3.2 セット生成（10問）

```
入力: mode, category（nilならミックス）, format（単語のみ）
1. 対象 = isArchived == false かつ category 一致（ミックスなら全件）
2. 優先度スコアを付ける
     未回答:                    3
     直近3回に不正解あり:       2 + (不正解の数)
     直近3回すべて正解:         0.3   ← 「卒業」。除外はしない
     それ以外:                  1
3. スコアを重みにして重み付きランダムで10件抽出（重複なし）
4. 各問の選択肢の並びをシャッフル。正解のインデックスを記録
```

- 対象が10件未満なら、あるだけ出す（最低1件）
- 「間違えた問題だけ」モード: 直近3回に不正解を含むもののみ
- 「ブックマークだけ」モード: `isBookmarked == true` のみ

### 3.3 回答記録

- 回答時に `Progress.recentResults` に append、4件目以降は先頭を落とす
- `elapsedMs` は問題表示から回答タップまで
- Foundation Models で生成した類題（§5）は **記録しない**
- **[v1.1]** 途中離脱しても回答済みの `ItemProgress` はそのまま残す。`StudySession` だけ保存しない（連続日数には数えない）

---

## 4. 画面

### 4.1 ホーム
- 上部セグメント: `単語` / `文法`
- 分野タイル（5つ）＋ `ミックス` タイル。各タイルに累計正答率（%）と「卒業済み / 全件」を小さく表示
- 下部: `間違えた問題` / `ブックマーク` の2ボタン（件数つき。0件ならdisabled）。**[v1.1]** 件数・出題は選択中のセグメント（単語 or 文法）のもの
- ヘッダー: 連続学習日数（1日1セット以上で継続）。今日まだやっていなければ目立たせる
- 単語タブのみ: 出題形式ピッカー（意味 / 穴埋め / 日→英 / ランダム）。デフォルトはランダム

### 4.2 クイズ
- 進捗 `3 / 10`、現在の分野名
- 問題文。文法は英文、単語は形式に応じた表示（§3.1）
- 4択ボタン（縦並び）。タップで即確定
- 回答後:
  - 正解: 選んだ選択肢を緑。不正解: 選んだものを赤、正解を緑
  - 解説を下に展開（文法: `explanation` / 単語: `meaning` + `example` + `example_ja`）
  - 右上に ブックマーク トグル、読み上げボタン（例文がある場合）
  - `次へ` ボタン。最終問では `結果を見る`
- 制限時間なし。途中離脱はセット破棄（確認ダイアログあり）
- 左上 `×` でホームへ

### 4.3 結果
- 正答数 `7 / 10` を大きく
- 間違えた問題の一覧（問題・正解・解説を折りたたみで）
- ボタン: `同じ条件でもう1セット` / `間違えた問題だけやり直す` / `ホームへ`
- 間違えた問題が0なら「やり直す」は非表示

### 4.4 設定（最小）
- 出題レベルの絞り込み（**[v1.1]** 450 / 500 / 550 / 600 のトグル4つ。最低1つは ON。デフォルト全部。絞り込みの結果0件のタイルは disabled）
- 読み上げ速度
- 学習履歴のリセット（確認2段階）
- バージョン情報、由来（Agnoia / Agenoria の一言）

### 4.5 レベル称号（演出。ロジックには影響しない）
累計正解数に応じてホームのヘッダーに称号を表示。

| 累計正解 | 称号 |
|---|---|
| 0〜 | Kore（世間知らずの娘） |
| 100〜 | Kore, Learning |
| 300〜 | Persephone（冥界の女王、まだ冬） |
| 600〜 | Persephone（春を取り戻した） |

---

## 5. Foundation Models（任意機能・v1に含める）

対応端末（`SystemLanguageModel.default.availability == .available`）でのみ表示。

1. **解説の言い換え**（文法のみ **[v1.1]**）: 解説の下に `別の言い方で` ボタン。元の解説を渡して「ビジネス英語を学び始めた初中級（スコア帯450点前後）の日本語話者向けに、日本語で2文以内で言い換えて」と指示。結果は保存しない。**指示文にも商標名は入れない**（§10 の grep 条件のため）
2. **類題生成**（単語の `cloze` のみ）: 結果画面の各誤答に `類題を出す`。`word` / `pos` / `meaning` を渡して例文1文と誤答3語を生成。`@Generable` で構造化。「練習用」ラベルを付け、§3.3 の通り履歴には記録しない

生成に失敗・タイムアウト（5秒）したらボタンを静かに消す。エラー表示はしない。

---

## 6. 音声
- `AVSpeechSynthesizer`、`AVSpeechSynthesisVoice(language: "en-US")`
- 例文のみ読み上げ。単語単体の読み上げは v2
- サイレントモードでも鳴らす（`.playback` カテゴリ）。**[v1.1]** `AVAudioSession` は iOS のみなので `#if os(iOS)` で囲む

---

## 7. 非機能
- ダークモード対応（標準コンポーネントに任せる。独自色は正誤の緑／赤のみ）
- Dynamic Type 対応。4択ボタンは2行まで折り返し可
- VoiceOver: 選択肢に `A〜D` のラベル。正誤結果を読み上げ
- 起動 → ホーム表示まで 1秒以内（JSON取り込みはバックグラウンドで、内容が変わったときのみ **[v1.1]**）
- **[v1.1]** Mac: 選択肢 `1`〜`4` キー、`次へ` Return、`×` Esc。最小ウィンドウ 480×640
- クラッシュ時に学習履歴が消えないこと（SwiftData のデフォルト設定で可）

---

## 8. 問題データの作り方（開発者向け）

- **すべてオリジナル問題**。市販問題集・公式問題集・単語帳の例文・解説の転載、言い回しを変えただけの改変は不可
- 単語リスト自体（頻出語）は事実情報なので使ってよい。例文・和訳・誤答を自作する
- 初期目標: 文法 5分野 × 50問 = 250問、単語 5カテゴリ × 50語 = 250語。動いたら各100まで増やす
- 初期データ **[v1.1]**: `grammar.json`（文法30問。5分野×6問、自作）、`words.json`（単語50語。旧 `words_sample.json`）
- 生成は Claude Code に任せてよいが、以下をチェック:
  - 正解が一意であること（他の選択肢でも文法的に成立しないか）
  - `distractors` が意味的に近いこと
  - `level` が 450〜600 の帯に収まっていること（難語・専門語は入れない）

---

## 9. v2 以降（やらないことを明記）

- Part6（長文穴埋め）
- Part2（応答問題。TTS音声）
- ウィジェット（今日やったか / 1問だけ）
- iPad レイアウト
- iCloud 同期
- 単語単体の読み上げ、発音記号
- 「推定スコア」の表示（根拠がないので入れない）

---

## 10. 完了条件（v1）

- [x] `xcodebuild` で iOS シミュレータ・macOS の両方のビルドとテストが通る **[v1.1]**
- [x] サンプルJSONを読み込み、単語・文法それぞれで10問セットが最後まで回る（AppModel の通しテスト）
- [x] 間違えた問題が優先的に再出題される（ユニットテストで確認）
- [x] 3回連続正解した問題の出題頻度が下がる（ユニットテストで確認）
- [x] ブックマーク・間違えた問題モードが動く（ユニットテストで確認）
- [ ] ダークモード・Dynamic Type（最大サイズ）で崩れない
- [x] アプリ内に「TOEIC」の文字列が存在しない（`grep -rn TOEIC Agnoria/` が空。テストでも JSON を確認）
