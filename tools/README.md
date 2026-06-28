# qBittorrent Static Manifest Generator

Generate a checksum manifest for static `qbittorrent-nox` artifacts from [`jerry048/Dedicated-Seedbox`](https://github.com/jerry048/Dedicated-Seedbox), or from a local checkout of that repository.

The generated manifest is intended for installers that download static qBittorrent binaries. Because those binaries may be installed or executed with elevated privileges, this tool records a SHA-256 checksum for every artifact so installers can verify the exact file before use.

## What it does

`generate_qbittorrent_manifest.py` discovers qBittorrent static binaries, calculates their SHA-256 hashes, and writes a tab-separated manifest.

By default, it:

1. Inspects the GitHub repository `jerry048/Dedicated-Seedbox`.
2. Looks under `Torrent Clients/qBittorrent`.
3. Finds files matching this layout:

   ```text
   Torrent Clients/qBittorrent/<arch>/qBittorrent-<qb_version> - libtorrent-<libtorrent_version>/qbittorrent-nox
   ```

4. Downloads each matching artifact.
5. Rejects suspiciously small files and Git LFS pointer files.
6. Calculates SHA-256 checksums.
7. Writes `manifests/qbittorrent.tsv`.

## Requirements

- Python 3.9 or newer
- Network access for remote generation or manifest verification
- Optional: a GitHub token via `GITHUB_TOKEN` to avoid low unauthenticated API rate limits
- Optional: a local `Dedicated-Seedbox` checkout for offline/local checksum generation

No third-party Python packages are required.

## Installation

Place the script in the `tools/` directory of the repository that should contain the generated manifest:

```text
Dedicated-Seedbox/
├── manifests/
└── tools/
    └── generate_qbittorrent_manifest.py
```

Make it executable:

```bash
chmod +x tools/generate_qbittorrent_manifest.py
```

You can also run it directly with Python:

```bash
python3 tools/generate_qbittorrent_manifest.py --help
```

## Quick start

Generate the default manifest from the remote GitHub repository:

```bash
tools/generate_qbittorrent_manifest.py
```

Write the manifest to a custom path:

```bash
tools/generate_qbittorrent_manifest.py --output manifests/qbittorrent.tsv
```

Print the manifest to stdout without writing a file:

```bash
tools/generate_qbittorrent_manifest.py --dry-run
```

Generate entries only for `amd64`:

```bash
tools/generate_qbittorrent_manifest.py --arch amd64
```

Generate entries for multiple architectures:

```bash
tools/generate_qbittorrent_manifest.py --arch amd64,arm64
```

Use a specific tag, branch, or commit:

```bash
tools/generate_qbittorrent_manifest.py --ref v2.0.0
```

Read artifacts from a local checkout instead of downloading them:

```bash
tools/generate_qbittorrent_manifest.py --local-repo /path/to/Dedicated-Seedbox
```

Verify an existing manifest against its recorded artifact URLs:

```bash
tools/generate_qbittorrent_manifest.py --verify manifests/qbittorrent.tsv
```

## Manifest format

The output is a TSV file with this header:

```text
# qb_version	libtorrent_version	arch	source	url	sha256	config_family
```

Columns:

| Column | Description |
| --- | --- |
| `qb_version` | qBittorrent version parsed from the artifact path. |
| `libtorrent_version` | libtorrent version parsed from the artifact path. |
| `arch` | Normalized architecture name. Supported values are `amd64` and `arm64`. |
| `source` | Always `static` for generated entries. |
| `url` | Raw artifact URL used by installers and verification. |
| `sha256` | SHA-256 checksum of the binary artifact. |
| `config_family` | qBittorrent configuration compatibility family inferred from the qBittorrent version. |

A generated manifest also includes comments with the generator version, generation timestamp, source repository, discovery ref, and raw URL ref.

## Configuration families

The script assigns `config_family` based on the qBittorrent version:

| qBittorrent version | `config_family` |
| --- | --- |
| `4.1.x` | `legacy_41` |
| `4.2.x` or `4.3.x` | `classic_pbkdf2` |
| Anything else | `modern_pbkdf2` |

## Architecture handling

Repository folder names are normalized to the manifest architecture names:

| Repository folder | Manifest architecture |
| --- | --- |
| `amd64` | `amd64` |
| `x86_64` | `amd64` |
| `x64` | `amd64` |
| `arm64` | `arm64` |
| `aarch64` | `arm64` |
| `ARM64` | `arm64` |

Unknown architecture folders are ignored.

## CLI options

| Option | Default | Description |
| --- | --- | --- |
| `--owner` | `jerry048` | GitHub owner to inspect. |
| `--repo` | `Dedicated-Seedbox` | GitHub repository to inspect. |
| `--ref` | `main` | Branch, tag, or commit used for discovery. |
| `--pin-url-ref` / `--no-pin-url-ref` | `--pin-url-ref` | Resolve `--ref` to a commit SHA and use that SHA in raw artifact URLs. |
| `--artifact-root` | `Torrent Clients/qBittorrent` | Repository path containing qBittorrent architecture folders. |
| `--output`, `-o` | `manifests/qbittorrent.tsv` relative to the inferred repo root | Manifest path to write, or `-` for stdout. |
| `--local-repo` | unset | Read artifacts from a local checkout instead of GitHub raw downloads. |
| `--cache-dir` | `$XDG_CACHE_HOME/seedbox-qbittorrent-manifest` or `~/.cache/seedbox-qbittorrent-manifest` | Cache downloaded artifacts by URL. |
| `--no-cache` | disabled | Disable the download cache. |
| `--github-token` | `$GITHUB_TOKEN` | GitHub token for API and artifact requests. |
| `--arch` | all supported architectures | Include only normalized architectures such as `amd64` or `arm64`. May be comma-separated or repeated. |
| `--qb-version` | all qBittorrent versions | Include only specific qBittorrent versions. May be comma-separated or repeated. |
| `--libtorrent-version` | all libtorrent versions | Include only specific libtorrent versions. May be comma-separated or repeated. |
| `--min-bytes` | `524288` | Minimum artifact size accepted as a real binary. Use `0` only when intentionally disabling this check. |
| `--dry-run` | disabled | Print the manifest to stdout without writing. |
| `--verify MANIFEST` | unset | Verify an existing manifest instead of generating a new one. |
| `--version` | n/a | Print the tool version. |

## Filtering examples

Generate only qBittorrent `5.0.3` entries:

```bash
tools/generate_qbittorrent_manifest.py --qb-version 5.0.3
```

Generate only entries for libtorrent `v2.0.11`:

```bash
tools/generate_qbittorrent_manifest.py --libtorrent-version v2.0.11
```

Combine filters:

```bash
tools/generate_qbittorrent_manifest.py \
  --arch amd64 \
  --qb-version 5.0.3 \
  --libtorrent-version v2.0.11
```

Repeat options instead of using comma-separated values:

```bash
tools/generate_qbittorrent_manifest.py \
  --arch amd64 \
  --arch arm64 \
  --qb-version 5.0.3 \
  --qb-version 5.0.4
```

## Remote mode vs local mode

### Remote mode

Remote mode is the default. It discovers artifacts through the GitHub API and downloads raw artifact files to calculate checksums.

```bash
tools/generate_qbittorrent_manifest.py --ref main
```

By default, `--pin-url-ref` resolves the requested ref to an immutable commit SHA and uses that SHA in the manifest URLs. This makes generated URLs deterministic even if a branch moves later.

### Local mode

Local mode reads artifacts from an existing checkout and calculates checksums from local files.

```bash
tools/generate_qbittorrent_manifest.py \
  --local-repo /path/to/Dedicated-Seedbox \
  --ref main
```

Local mode is useful when:

- You already have the artifacts locally.
- Raw GitHub downloads return Git LFS pointers instead of binary files.
- GitHub tree discovery is truncated.
- You want generation to work with limited network access.

When `--pin-url-ref` is enabled in local mode, the script still tries to resolve `--ref` to a commit SHA for deterministic URLs. If that lookup fails, local generation continues and uses the provided ref in the URLs.

## Verification

Use `--verify` to re-download every static artifact listed in an existing manifest and compare its SHA-256 checksum:

```bash
tools/generate_qbittorrent_manifest.py --verify manifests/qbittorrent.tsv
```

Verification fails when:

- A manifest row is missing a valid 64-character SHA-256 checksum.
- An artifact cannot be downloaded.
- The downloaded artifact is a Git LFS pointer file.
- The downloaded artifact is smaller than `--min-bytes`.
- The calculated SHA-256 does not match the manifest.

The command exits with status `0` when all entries pass and `1` when any entry fails.

## Caching

Downloaded artifacts are cached by URL. The default cache directory is:

```text
$XDG_CACHE_HOME/seedbox-qbittorrent-manifest
```

If `XDG_CACHE_HOME` is not set, the script uses:

```text
~/.cache/seedbox-qbittorrent-manifest
```

Disable caching with:

```bash
tools/generate_qbittorrent_manifest.py --no-cache
```

Use a custom cache directory with:

```bash
tools/generate_qbittorrent_manifest.py --cache-dir /tmp/qbittorrent-artifact-cache
```

## Security notes

- Keep `sha256` populated for every production manifest entry.
- Prefer the default `--pin-url-ref` behavior so raw URLs point at an immutable commit SHA instead of a moving branch.
- Do not disable `--min-bytes` unless you know the artifact is expected to be smaller than the default threshold.
- If remote downloads return Git LFS pointer files, use a local checkout with Git LFS installed and run the tool with `--local-repo`.
- Re-run `--verify` before publishing or consuming a regenerated manifest.

## Troubleshooting

### `GitHub returned a truncated tree`

GitHub did not return the full recursive tree. Use a local checkout:

```bash
tools/generate_qbittorrent_manifest.py --local-repo /path/to/Dedicated-Seedbox
```

You can also narrow discovery with filters such as `--arch`, `--qb-version`, or `--libtorrent-version`.

### `resolved to a Git LFS pointer, not the binary`

The URL returned a Git LFS pointer instead of the actual binary artifact. Install Git LFS, fetch the files locally, and generate from the local checkout:

```bash
git lfs install
git lfs pull
tools/generate_qbittorrent_manifest.py --local-repo /path/to/Dedicated-Seedbox
```

### `unsupported --arch value`

Only normalized manifest architectures are accepted for `--arch`:

```text
amd64, arm64
```

Repository folder aliases such as `x86_64`, `x64`, `aarch64`, and `ARM64` are handled automatically during discovery, but filters must use normalized names.

### `no qBittorrent static artifacts matched the requested filters`

Check that:

- `--artifact-root` points to the correct path.
- The repository contains files named `qbittorrent-nox` under the expected directory structure.
- Your `--arch`, `--qb-version`, or `--libtorrent-version` filters are not too restrictive.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success. |
| `1` | Manifest generation or verification failed. |
| `2` | Invalid CLI usage, such as an unsupported architecture filter. |
| `130` | Interrupted by the user. |
