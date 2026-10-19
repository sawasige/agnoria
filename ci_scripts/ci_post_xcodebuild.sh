#!/bin/sh
# Xcode Cloud: アーカイブ後に dSYM を Crashlytics に送る（クラッシュのシンボル化に必要。SPEC §7.1）。
# アーカイブ以外のアクション（ビルド・テスト）では CI_ARCHIVE_PATH が無いので何もしない
set -eu
if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
  echo "not an archive action; skipping dSYM upload"
  exit 0
fi
PLIST="$CI_PRIMARY_REPOSITORY_PATH/Agnoria/GoogleService-Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "GoogleService-Info.plist not found; skipping dSYM upload"
  exit 0
fi
UPLOAD="$CI_DERIVED_DATA_PATH/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
"$UPLOAD" -gsp "$PLIST" -p ios "$CI_ARCHIVE_PATH/dSYMs"
