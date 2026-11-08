# Phreox workflows

The builds and releases of Phreox. The code is in [Phreox/phreox](https://github.com/Phreox/phreox) (a submodule here, `./phreox`); the workflows are here so that they can be changed and run without
touching the code repository.

```
.github/workflows/publish.yml   the apps (desktop, Android), the service, the backend, the space node and the web version, as one release of Phreox/releases
.github/workflows/natives.yml   libopus and PortAudio for every platform (called by publish.yml)
.github/workflows/website.yml   the website (phreox.com), on its own tags
.github/actions/source/         puts the commit that is built into ./phreox
scripts/release.sh              the draft release: make it, put files in it, publish it
```

## How a build starts

`Phreox/phreox` has one workflow, `dispatch`, which on every push of the main branch and of a tag starts a workflow here (`workflow_dispatch`: `publish.yml` for the apps, `website.yml` for
`website-X.Y.Z` tags) with the branch or tag, its kind and the commit. The workflows here move the submodule `phreox` to that commit and build it. By hand: **Actions > publish > Run workflow** with a branch or tag.

## When the apps are in the release

The release is published as soon as the quick parts are in it (service, backend, space node, web). The Android app and the desktop apps (AppImage, exe, dmg) are added to the published release one
after the other when they are done, and `SHA256SUMS` is written again each time (`release.sh refresh-checksums`, which also copes with two jobs writing it at the same moment). The apps look at the release for the file of their
own system and offer an update only when it is there, so a file that is not there yet is not a problem. The libopus and PortAudio builds that the jobs need are in a second draft that is thrown away at the end, so the
release has nothing but its files.

## No artifacts

Nothing built is kept in a run. The release in `Phreox/releases` is made as a **draft** first; every job puts its files straight into it (`scripts/release.sh upload`), and the last job
writes `SHA256SUMS` from the digests GitHub made, replaces the previous dev release and publishes the draft. What a job needs of another (the libopus and PortAudio builds) is a file of the draft too
(`natives-*.tar.gz`) and is removed before publishing. A run that fails or is cancelled throws its draft away.

## The desktop app

The Linux app (`desktop`) is the Rust app: `phreox-frontend` is built with `cargo` and packaged by `phreox-frontend/scripts/platform-package-linux.sh` into an AppImage, no npm. The Windows and macOS apps
(`desktop-win`, `desktop-mac`) are still the Electron app, built from the branch `react-legacy` of the frontend repository, until the Rust builds for them exist (what is missing: the AV1 decoder `dav1d` without a system package, a checked run of the NSIS
installer with the WinShell plugin, and a run on macOS; `phreox-frontend/scripts/platform-package-windows.sh` and `-macos.sh` are written). The web version, the Android app and the website are the React app and also come from `react-legacy`.

## Secrets (of this repository)

| Secret | For |
|---|---|
| `RELEASES_TOKEN` | write access to the contents of `Phreox/releases` |
| `SUBMODULES_TOKEN` | read access to `Phreox/phreox` and all its submodules (they are private) |
| `UPDATE_TOKEN` | the token the apps use to ask `Phreox/releases` for updates (built into them) |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` | the key every Android build is signed with |

`Phreox/phreox` needs one secret, `WORKFLOWS_TOKEN`: a token that may start workflows in this repository (a fine-grained token with "Actions: read and write" on `Phreox/workflows`; nothing more).

## Notes

- The version code of the Android app is `100000 + run number`: the numbers of the old workflow in `Phreox/phreox` were below that, so an installed app can still be updated.
- The installers of Windows and macOS wait a long time for a runner. The release waits for them (up to 40 minutes), but if they fail it is published without them.
