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
- Open `/home/runner/work/DMGBuildNotarize-2/DMGBuildNotarize-2/DMGBuildNotarize.xcodeproj` in Xcode and run the `DMGBuildNotarize` scheme.
- Command-line tests:
  - `xcodebuild test -project DMGBuildNotarize.xcodeproj -scheme DMGBuildNotarize`

## Agent Guidance
- Prefer small, focused changes and avoid refactoring unrelated code.
- Keep user-facing terminology consistent with the README: signed app in, polished notarized DMG out.
- When editing UI strings, preserve localization behavior already used in the codebase.
- For packaging flow changes, be careful not to reorder validation, signing, notarization, stapling, and verification steps without a clear reason.
- Update `README.md` only when behavior or developer workflow documentation changes.
