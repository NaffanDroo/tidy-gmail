# Changelog

## [0.3.0](https://github.com/NaffanDroo/tidy-gmail/compare/v0.2.2...v0.3.0) (2026-03-29)


### Features

* export selected emails to AES-256 encrypted DMG (closes [#6](https://github.com/NaffanDroo/tidy-gmail/issues/6)) ([#31](https://github.com/NaffanDroo/tidy-gmail/issues/31)) ([c37cff1](https://github.com/NaffanDroo/tidy-gmail/commit/c37cff1d0162bdf60470760602a91b951fdd77c0))

## [0.2.2](https://github.com/NaffanDroo/tidy-gmail/compare/v0.2.1...v0.2.2) (2026-03-29)


### Bug Fixes

* **ci:** create releases as drafts so workflow can publish after DMG upload ([#29](https://github.com/NaffanDroo/tidy-gmail/issues/29)) ([41874fd](https://github.com/NaffanDroo/tidy-gmail/commit/41874fda2605a2056ab55d0fdfbcad9f80d35941))

## [0.2.1](https://github.com/NaffanDroo/tidy-gmail/compare/v0.2.0...v0.2.1) (2026-03-29)


### Bug Fixes

* **ci:** use build.sh instead of xcodebuild archive for DMG ([#27](https://github.com/NaffanDroo/tidy-gmail/issues/27)) ([79c3d1c](https://github.com/NaffanDroo/tidy-gmail/commit/79c3d1c0d39bc948659a3671b124e34542cd542a))

## [0.2.0](https://github.com/NaffanDroo/tidy-gmail/compare/v0.1.0...v0.2.0) (2026-03-29)


### Features

* bootstrap project, OAuth auth, and read-only browse inbox ([#18](https://github.com/NaffanDroo/tidy-gmail/issues/18)) ([851c1d4](https://github.com/NaffanDroo/tidy-gmail/commit/851c1d4a34e29a7abcba7ca7b2b797b95c51b76e))
* **bulk-delete:** bulk select, trash, and permanent-delete emails ([#5](https://github.com/NaffanDroo/tidy-gmail/issues/5)) ([#24](https://github.com/NaffanDroo/tidy-gmail/issues/24)) ([d70473a](https://github.com/NaffanDroo/tidy-gmail/commit/d70473ac8a089b30bfdaa3dd44f75567f358a163))
* **ui:** email detail pane, sign-out, and blue app icon ([#21](https://github.com/NaffanDroo/tidy-gmail/issues/21)) ([b9355c7](https://github.com/NaffanDroo/tidy-gmail/commit/b9355c786f20de233bfc775a0ac36cbd1b00ef1f))


### Bug Fixes

* **ci:** resolve all SwiftLint violations and wire up release-please ([#20](https://github.com/NaffanDroo/tidy-gmail/issues/20)) ([e0d7c43](https://github.com/NaffanDroo/tidy-gmail/commit/e0d7c4354a4c3187c63f11422b75cff8c6e27a37))
* **gmail:** cap fetch concurrency at 5 and remove Keychain dependency ([#19](https://github.com/NaffanDroo/tidy-gmail/issues/19)) ([a5637e9](https://github.com/NaffanDroo/tidy-gmail/commit/a5637e94f88545d392348ececbf09fe6c00cf67b))
