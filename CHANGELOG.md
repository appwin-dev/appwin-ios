# Changelog - Appwin SDK for iOS

Versions follow [semantic versioning](https://semver.org).

Each Appwin artefact versions independently: a fix here does not move the iOS,
Android or React Native SDK. All four numbers live in one place, `version.json`
in the monorepo, and the release script derives every manifest and every
cross-artefact pin from it.

The four products (`AppwinCore`, `AppwinSupport`, `AppwinCommunity`,
`AppwinNotifications`) ship from a single package, so they share **this**
version between them.

## 0.1.1

The four podspecs are publishable to the CocoaPods registry: their source is
the tagged repository instead of a local path, and each product pins
`AppwinCore` at its own version rather than accepting any. No code change.

SPM is unaffected: this version and 0.1.0 carry the same sources.

## 0.1.0

First release.
