# Flipabulary

Flipabulary is an offline vocabulary and flashcard app for iPhone, iPad, and iPhone Duo. It stores words, translations, examples, stacks, and tags locally, then schedules short self-assessed review sessions with Again and Good.

## Features

- **Words**: saved/due totals, New/Learning/Learned/Difficult filters, Unicode-aware local search, stack scoping, repeat progress.
- **Cards**: required word/translation validation, optional examples, phonetic/part-of-speech details, tags, duplicate warnings, Add another, edit, delete, and single-card review.
- **Stacks**: create, rename, select, delete with a card move/delete choice, per-stack session limits, shuffle, translation-first, custom learning steps and rules.
- **Review**: deterministic queue admission, reveal-before-rating, translation-first privacy, bounded retries, elapsed time, queue sidebar, end-session summary, and resume after relaunch. The card flips in 3D repeatedly between front and back. Swipe left for Again or right for Good for a Tinder-style throw animation; the rating buttons remain available.
- **Learning model**: configurable threshold, mistake reset, cumulative decay milestones, return threshold, hysteresis, calendar-safe month/DST handling, and a daily new-card quota.
- **Widgets**: Summary and List kinds in Small, Medium, Large, and Extra Large, with App Group snapshots, per-widget App Intents, deep links, gallery placeholders, and light/dark rendering.
- **Reminders**: opt-in local notifications, permission handling, weekday/time/scope/sound settings, a seven-day workload-aware schedule, test reminder, and typed notification routing.
- **Support**: StoreKit 2 products with one-time/monthly options, catalog prices, custom configured amounts, purchase states, and restore.
- **Languages**: live in-app switching between English, German, Spanish, Portuguese (Brasil), French, Russian, Polish, Ukrainian, Simplified Chinese, Korean, Japanese, Vietnamese, Italian, Dutch, Turkish, Indonesian, and the system language.

## Requirements

- Xcode 27.2 or later
- iOS / iPadOS 18.0+
- No third-party dependencies

## Build and test

```sh
xcodebuild -project flipabulary.xcodeproj -scheme flipabulary \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

xcodebuild test -project flipabulary.xcodeproj -scheme flipabulary \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

The WidgetKit extension is embedded as `FlipabularyWidgetsExtension`. The app and extension share widget data through the `group.com.mrmaier.flipabulary` App Group.

## Local StoreKit

`flipabulary/Resources/Flipabulary.storekit` contains the local support catalog used by the shared scheme. Product prices and availability are read from StoreKit at runtime; when no catalog is available the Support screen shows an honest unavailable state instead of a dead purchase button.

## Typography

Poppins is not bundled in this repository. The typography layer uses Poppins when the licensed font is available and otherwise falls back to the Dynamic Type-scaled system rounded face.

## Repository scope

The public repository contains application source, tests, widget extension, assets, README, and local StoreKit configuration. Internal design documents, plans, logs, and visual evidence are not published.
