#!/usr/bin/env bash
# The release of an app is built as a DRAFT in Phreox/releases: every job puts its files straight into it (no artifacts of the workflow, nothing built is kept in the
# run), and one last job publishes it. This is the whole of that, with the API of GitHub (gh and curl).
#
#   release.sh draft <tag> <title> <prerelease> <notes>   makes the draft (a rerun replaces its own) and prints its id
#   release.sh upload <id> <file>...                      puts files into the draft (a file of the same name is replaced)
#   release.sh download <id> <name> <destination>         takes one file of the draft
#   release.sh names <id> [glob]                          the names of the files of the draft, one per line
#   release.sh delete <id> <glob>                         removes the files of the draft whose name fits
#   release.sh checksums <id> <file>                      writes SHA256SUMS from the digests GitHub computed for the files (nothing is downloaded)
#   release.sh refresh-checksums <id>                     (re)writes SHA256SUMS in the release, also while other jobs add files to it at the same time
#   release.sh publish <id> <prerelease> <latest>         makes the draft a release
#   release.sh discard <id>                               throws a draft away
#
# GH_TOKEN needs write access to the contents of the releases repository (RELEASES_REPO, default Phreox/releases).
set -euo pipefail

: "${GH_TOKEN:?The secret RELEASES_TOKEN (write access to the contents of Phreox/releases) is not set in this repository: add it under Settings > Secrets and variables > Actions}"

repo="${RELEASES_REPO:-Phreox/releases}"
api() { gh api -H "Accept: application/vnd.github+json" "$@"; }
assets() { api "repos/$repo/releases/$1/assets?per_page=100" --paginate --jq '.[] | [.id, .name, (.digest // "")] | @tsv'; }

command="${1:?command}"
shift

case "$command" in
  draft)
    tag="$1" title="$2" prerelease="$3" notes="$4"

    # A rerun of the same tag replaces its own draft and the release it made.
    for id in $(api "repos/$repo/releases?per_page=100" --paginate --jq ".[] | select(.tag_name == \"$tag\") | .id"); do
      api -X DELETE "repos/$repo/releases/$id" > /dev/null
    done

    gh release delete "$tag" -R "$repo" --cleanup-tag --yes > /dev/null 2>&1 || true

    api -X POST "repos/$repo/releases" -f tag_name="$tag" -f name="$title" -f body="$notes" -F draft=true -F prerelease="$prerelease" --jq .id
    ;;

  upload)
    id="$1"
    shift

    for file in "$@"; do
      name="$(basename "$file")"

      # The same name twice is refused by GitHub: the old file goes first.
      assets "$id" | awk -F'\t' -v name="$name" '$2 == name { print $1 }' | while read -r old; do api -X DELETE "repos/$repo/releases/assets/$old" > /dev/null; done

      curl -fsS --retry 5 --retry-all-errors --retry-delay 5 -X POST \
        -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/octet-stream" \
        --data-binary @"$file" "https://uploads.github.com/repos/$repo/releases/$id/assets?name=$name" -o /dev/null
      echo "uploaded $name"
    done
    ;;

  download)
    id="$1" name="$2" destination="$3"
    asset="$(assets "$id" | awk -F'\t' -v name="$name" '$2 == name { print $1 }' | head -1)"

    [[ -n "$asset" ]] || { echo "no file $name in the draft" >&2; exit 1; }

    curl -fsSL --retry 5 --retry-all-errors -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/octet-stream" "https://api.github.com/repos/$repo/releases/assets/$asset" -o "$destination"
    ;;

  names)
    id="$1" glob="${2:-*}"

    assets "$id" | cut -f2 | while read -r name; do [[ "$name" == $glob ]] && echo "$name"; done || true
    ;;

  delete)
    id="$1" glob="$2"

    assets "$id" | while IFS=$'\t' read -r asset name _; do
      if [[ "$name" == $glob ]]; then api -X DELETE "repos/$repo/releases/assets/$asset" > /dev/null; echo "removed $name"; fi
    done
    ;;

  checksums)
    id="$1" file="$2"

    : > "$file"
    assets "$id" | while IFS=$'\t' read -r _ name digest; do
      [[ "$name" == SHA256SUMS ]] && continue
      [[ "$digest" == sha256:* ]] || { echo "GitHub gave no checksum for $name" >&2; exit 1; }
      printf '%s  %s\n' "${digest#sha256:}" "$name" >> "$file"
    done
    ;;

  refresh-checksums)
    id="$1"
    work="$(mktemp -d)"

    # Jobs put their files into the release one after the other, some after it is published, and each makes the list again. Two of them may do it at the same moment, and the
    # one that finishes last would leave out the file of the other: so after writing the list it looks again, and writes it anew until every file that is there is in it.
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      if "$0" checksums "$id" "$work/SHA256SUMS" 2> /dev/null; then
        "$0" upload "$id" "$work/SHA256SUMS" > /dev/null
        sleep $((RANDOM % 5 + 2))

        listed="$(awk '{ print $2 }' "$work/SHA256SUMS" | sort)"
        present="$(assets "$id" | cut -f2 | grep -vx SHA256SUMS | sort || true)"

        if [[ "$listed" == "$present" ]]; then
          cat "$work/SHA256SUMS"
          exit 0
        fi
      else
        # GitHub works out the checksum of a file a moment after the upload.
        sleep 3
      fi
    done

    echo "SHA256SUMS does not list all files of the release" >&2
    exit 1
    ;;

  publish)
    id="$1" prerelease="$2" latest="$3"

    api -X PATCH "repos/$repo/releases/$id" -F draft=false -F prerelease="$prerelease" -f make_latest="$latest" > /dev/null
    ;;

  discard)
    api -X DELETE "repos/$repo/releases/$1" > /dev/null || true
    ;;

  *)
    echo "unknown command: $command" >&2
    exit 2
    ;;
esac
