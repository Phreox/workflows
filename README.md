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

## No artifacts

Nothing built is kept in a run. The release in `Phreox/releases` is made as a **draft** first; every job puts its files straight into it (`scripts/release.sh upload`), and the last job
writes `SHA256SUMS` from the digests GitHub made, replaces the previous dev release and publishes the draft. What a job needs of another (the libopus and PortAudio builds) is a file of the draft too
(`natives-*.tar.gz`) and is removed before publishing. A run that fails or is cancelled throws its draft away.

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
