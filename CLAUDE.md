# CLAUDE.md

## Repository Purpose
- DMGBuildNotarize is a macOS app that turns a signed `.app` bundle into a signed, notarized `.dmg`.
- The main workflow validates the app bundle, builds and styles the DMG, signs it, submits it for notarization, staples the result, and verifies the finished image.

## Project Structure
- `DMGBuildNotarize/App/`: app entry point.
- `DMGBuildNotarize/Views/`: SwiftUI screens and UI components.
- `DMGBuildNotarize/Stores/`: app state and controller objects.
- `DMGBuildNotarize/Services/`: packaging, signing, notarization, validation, and process-running logic.
- `DMGBuildNotarize/Model/`: data models used across the app.
- `DMGBuildNotarize/Support/`: shared helpers and utility code.

## Build and Test
- Open `DMGBuildNotarize.xcodeproj` in Xcode and run the `DMGBuildNotarize` scheme.
- Command-line tests:
  - `xcodebuild test -project DMGBuildNotarize.xcodeproj -scheme DMGBuildNotarize`

## Localization
- The project ships English (`en.lproj`) and Spanish (`es.lproj`) localizations.
- Dynamic UI strings must use `String(localized:)` so that `Localizable.strings` entries are applied at runtime.
- When adding or changing user-facing text, update both `en.lproj/Localizable.strings` and `es.lproj/Localizable.strings`.

## Agent Guidance
- Prefer small, focused changes and avoid refactoring unrelated code.
- Keep user-facing terminology consistent with the README: signed app in, polished notarized DMG out.
- When editing UI strings, preserve localization behavior already used in the codebase.
- For packaging flow changes, be careful not to reorder validation, signing, notarization, stapling, and verification steps without a clear reason.
- Update `README.md` only when behavior or developer workflow documentation changes.
- The project targets macOS 14 Sonoma; update the deployment target in `project.pbxproj` if the minimum OS version changes.

## DMG Building Modes
- When `create-dmg` is installed (`/usr/local/bin/create-dmg` or `/opt/homebrew/bin/create-dmg`), `PackagingPipeline` uses it to produce a polished DMG in a single step (7 stages shown in the UI). This avoids AppleScript and does not require Automation permission.
- When `create-dmg` is not installed, the pipeline falls back to the original AppleScript-based Finder layout flow (10 stages). The entitlement `com.apple.security.automation.apple-events` is still declared for the fallback path.
- `PackagingPipeline.stages` returns the correct stage list for the active mode; `PackagingController` uses this list to initialize the stage progress UI.
