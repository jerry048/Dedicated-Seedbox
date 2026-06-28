#!/usr/bin/env python3
"""Generate Dedicated-Seedbox/manifests/qbittorrent.tsv.

The static qBittorrent installer should never run binaries downloaded from a
moving branch unless it verifies the exact artifact checksum first. This tool
builds that checksum manifest by discovering qBittorrent static artifacts,
downloading or reading them, calculating SHA-256, and writing a TSV manifest.

Default remote mode discovers files from:
  https://github.com/jerry048/Dedicated-Seedbox

Expected artifact path pattern:
  Torrent Clients/qBittorrent/<arch>/qBittorrent-<qb_version> - libtorrent-<libtorrent_version>/qbittorrent-nox

Manifest columns:
  qb_version, libtorrent_version, arch, source, url, sha256, config_family

Examples:
  # From the Dedicated-Seedbox repo root, write manifests/qbittorrent.tsv
  tools/generate_qbittorrent_manifest.py

  # Use a tag or commit for deterministic raw URLs
  tools/generate_qbittorrent_manifest.py --ref v2.0.0

  # Generate only amd64 entries
  tools/generate_qbittorrent_manifest.py --arch amd64

  # Read artifacts from a local checkout instead of downloading them
  tools/generate_qbittorrent_manifest.py --local-repo /path/to/Dedicated-Seedbox

  # Verify the current manifest entries against their URLs
  tools/generate_qbittorrent_manifest.py --verify manifests/qbittorrent.tsv
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as _dt
import hashlib
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Iterable, Iterator, Sequence

TOOL_VERSION = "1.0.0"
DEFAULT_OWNER = "jerry048"
DEFAULT_REPO = "Dedicated-Seedbox"
DEFAULT_REF = "main"
DEFAULT_ARTIFACT_ROOT = "Torrent Clients/qBittorrent"
DEFAULT_OUTPUT = "manifests/qbittorrent.tsv"
USER_AGENT = f"seedbox-qbittorrent-manifest/{TOOL_VERSION}"

# The real upstream repository has historically used x86_64 and ARM64 folder
# names, while seedboxctl state/manifest architecture names are amd64/arm64.
ARCH_ALIASES = {
    "amd64": "amd64",
    "x86_64": "amd64",
    "x64": "amd64",
    "arm64": "arm64",
    "aarch64": "arm64",
    "ARM64": "arm64",
}

ARTIFACT_RE = re.compile(
    r"^(?P<root>Torrent Clients/qBittorrent)/"
    r"(?P<repo_arch>[^/]+)/"
    r"qBittorrent-(?P<qb_version>.+?) - libtorrent-(?P<libtorrent_version>[^/]+)/"
    r"qbittorrent-nox$"
)

MANIFEST_HEADER = (
    "# qb_version\tlibtorrent_version\tarch\tsource\turl\tsha256\tconfig_family\n"
)


@dataclasses.dataclass(frozen=True)
class Artifact:
    qb_version: str
    libtorrent_version: str
    arch: str
    repo_arch: str
    path: str
    url: str
    sha256: str = ""
    size: int = 0

    @property
    def config_family(self) -> str:
        return config_family(self.qb_version)

    def manifest_row(self) -> str:
        fields = [
            self.qb_version,
            self.libtorrent_version,
            self.arch,
            "static",
            self.url,
            self.sha256,
            self.config_family,
        ]
        return "\t".join(fields) + "\n"


class ManifestError(RuntimeError):
    pass


def eprint(*parts: object) -> None:
    print(*parts, file=sys.stderr)


def die(message: str, code: int = 1) -> None:
    eprint(f"error: {message}")
    raise SystemExit(code)


def normalize_arch(value: str) -> str | None:
    return ARCH_ALIASES.get(value)


def version_key(version: str) -> tuple:
    """Sort versions naturally without requiring third-party packaging libs."""
    parts: list[object] = []
    for chunk in re.split(r"([0-9]+)", version):
        if chunk == "":
            continue
        if chunk.isdigit():
            parts.append(int(chunk))
        else:
            parts.append(chunk.lower())
    return tuple(parts)


def artifact_sort_key(a: Artifact) -> tuple:
    return (version_key(a.qb_version), version_key(a.libtorrent_version), a.arch, a.path)


def config_family(qb_version: str) -> str:
    if qb_version.startswith("4.1."):
        return "legacy_41"
    if qb_version.startswith("4.2.") or qb_version.startswith("4.3."):
        return "classic_pbkdf2"
    return "modern_pbkdf2"


def quote_path(path: str) -> str:
    # Keep slash delimiters, encode spaces and other unsafe path characters.
    return urllib.parse.quote(path, safe="/-_.~")


def raw_url(owner: str, repo: str, ref: str, path: str) -> str:
    return f"https://raw.githubusercontent.com/{owner}/{repo}/{quote_path(ref)}/{quote_path(path)}"


def github_api_url(owner: str, repo: str, endpoint: str) -> str:
    endpoint = endpoint.lstrip("/")
    return f"https://api.github.com/repos/{owner}/{repo}/{endpoint}"


def request_headers(token: str | None = None) -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": USER_AGENT,
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def http_request(url: str, token: str | None = None, *, binary: bool = False, retries: int = 3) -> bytes:
    headers = request_headers(token)
    if binary:
        headers["Accept"] = "application/octet-stream"
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.read()
        except urllib.error.HTTPError as exc:
            last_error = exc
            if exc.code in {403, 429, 500, 502, 503, 504} and attempt < retries:
                time.sleep(min(2**attempt, 10))
                continue
            body = exc.read().decode("utf-8", "replace")[:500]
            raise ManifestError(f"HTTP {exc.code} while fetching {url}: {body}") from exc
        except urllib.error.URLError as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(min(2**attempt, 10))
                continue
            raise ManifestError(f"Network error while fetching {url}: {exc}") from exc
    raise ManifestError(f"Failed to fetch {url}: {last_error}")


def http_json(url: str, token: str | None = None) -> dict:
    data = http_request(url, token)
    try:
        return json.loads(data.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise ManifestError(f"Invalid JSON from {url}: {exc}") from exc


def resolve_ref(owner: str, repo: str, ref: str, token: str | None) -> str:
    encoded = urllib.parse.quote(ref, safe="")
    data = http_json(github_api_url(owner, repo, f"commits/{encoded}"), token)
    sha = data.get("sha")
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ManifestError(f"Could not resolve {owner}/{repo}@{ref} to a commit SHA")
    return sha


def discover_remote_artifacts(
    owner: str,
    repo: str,
    discovery_ref: str,
    url_ref: str,
    token: str | None,
    artifact_root: str,
) -> list[Artifact]:
    encoded_ref = urllib.parse.quote(discovery_ref, safe="")
    tree_url = github_api_url(owner, repo, f"git/trees/{encoded_ref}?recursive=1")
    data = http_json(tree_url, token)
    if data.get("truncated"):
        raise ManifestError(
            "GitHub returned a truncated tree. Use --local-repo with a local checkout "
            "or narrow the query with --arch/--qb-version."
        )
    tree = data.get("tree")
    if not isinstance(tree, list):
        raise ManifestError("Unexpected GitHub tree response")

    artifacts: list[Artifact] = []
    for entry in tree:
        if not isinstance(entry, dict) or entry.get("type") != "blob":
            continue
        path = entry.get("path")
        if not isinstance(path, str):
            continue
        if not path.startswith(artifact_root.rstrip("/") + "/"):
            continue
        parsed = parse_artifact_path(path, artifact_root=artifact_root)
        if parsed is None:
            continue
        qb_version, libtorrent_version, arch, repo_arch = parsed
        artifacts.append(
            Artifact(
                qb_version=qb_version,
                libtorrent_version=libtorrent_version,
                arch=arch,
                repo_arch=repo_arch,
                path=path,
                url=raw_url(owner, repo, url_ref, path),
            )
        )
    return artifacts


def discover_local_artifacts(
    local_repo: pathlib.Path,
    owner: str,
    repo: str,
    url_ref: str,
    artifact_root: str,
) -> list[Artifact]:
    base = local_repo / pathlib.Path(*artifact_root.split("/"))
    if not base.exists():
        raise ManifestError(f"Artifact root not found: {base}")

    artifacts: list[Artifact] = []
    for file_path in base.rglob("qbittorrent-nox"):
        if not file_path.is_file():
            continue
        rel = file_path.relative_to(local_repo).as_posix()
        parsed = parse_artifact_path(rel, artifact_root=artifact_root)
        if parsed is None:
            continue
        qb_version, libtorrent_version, arch, repo_arch = parsed
        data = file_path.read_bytes()
        artifacts.append(
            Artifact(
                qb_version=qb_version,
                libtorrent_version=libtorrent_version,
                arch=arch,
                repo_arch=repo_arch,
                path=rel,
                url=raw_url(owner, repo, url_ref, rel),
                sha256=hashlib.sha256(data).hexdigest(),
                size=len(data),
            )
        )
    return artifacts


def parse_artifact_path(path: str, *, artifact_root: str) -> tuple[str, str, str, str] | None:
    # Keep the default regex fast/simple, but allow callers to override the root.
    if artifact_root != DEFAULT_ARTIFACT_ROOT:
        escaped_root = re.escape(artifact_root.rstrip("/"))
        regex = re.compile(
            rf"^(?P<root>{escaped_root})/"
            r"(?P<repo_arch>[^/]+)/"
            r"qBittorrent-(?P<qb_version>.+?) - libtorrent-(?P<libtorrent_version>[^/]+)/"
            r"qbittorrent-nox$"
        )
    else:
        regex = ARTIFACT_RE

    match = regex.match(path)
    if not match:
        return None
    repo_arch = match.group("repo_arch")
    arch = normalize_arch(repo_arch)
    if arch is None:
        return None
    return (
        match.group("qb_version"),
        match.group("libtorrent_version"),
        arch,
        repo_arch,
    )


def cache_path(cache_dir: pathlib.Path, url: str) -> pathlib.Path:
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
    return cache_dir / digest


def fetch_artifact_bytes(url: str, token: str | None, cache_dir: pathlib.Path | None) -> bytes:
    if cache_dir is not None:
        cache_dir.mkdir(parents=True, exist_ok=True)
        cp = cache_path(cache_dir, url)
        if cp.exists():
            return cp.read_bytes()
        data = http_request(url, token, binary=True)
        tmp = cp.with_suffix(".tmp")
        tmp.write_bytes(data)
        os.replace(tmp, cp)
        return data
    return http_request(url, token, binary=True)


def checksum_remote_artifacts(
    artifacts: Sequence[Artifact],
    token: str | None,
    cache_dir: pathlib.Path | None,
    min_bytes: int,
) -> list[Artifact]:
    checked: list[Artifact] = []
    total = len(artifacts)
    for idx, artifact in enumerate(artifacts, start=1):
        eprint(
            f"[{idx}/{total}] sha256 {artifact.arch} "
            f"qBittorrent {artifact.qb_version} / libtorrent {artifact.libtorrent_version}"
        )
        data = fetch_artifact_bytes(artifact.url, token, cache_dir)
        validate_artifact_bytes(artifact, data, min_bytes=min_bytes)
        checked.append(
            dataclasses.replace(
                artifact,
                sha256=hashlib.sha256(data).hexdigest(),
                size=len(data),
            )
        )
    return checked


def validate_artifact_bytes(artifact: Artifact, data: bytes, min_bytes: int) -> None:
    if data.startswith(b"version https://git-lfs.github.com/spec/v1\n"):
        raise ManifestError(
            f"{artifact.path} resolved to a Git LFS pointer, not the binary. "
            "Install Git LFS and use --local-repo, or use an artifact URL that returns the binary."
        )
    if min_bytes > 0 and len(data) < min_bytes:
        raise ManifestError(
            f"{artifact.path} is only {len(data)} bytes; refusing to checksum what does not look like a binary. "
            "Use --min-bytes 0 only if you know this is expected."
        )


def apply_filters(
    artifacts: Iterable[Artifact],
    arches: set[str],
    qb_versions: set[str],
    libtorrent_versions: set[str],
) -> list[Artifact]:
    result = []
    for artifact in artifacts:
        if arches and artifact.arch not in arches:
            continue
        if qb_versions and artifact.qb_version not in qb_versions:
            continue
        if libtorrent_versions and artifact.libtorrent_version not in libtorrent_versions:
            continue
        result.append(artifact)
    return sorted(result, key=artifact_sort_key)


def read_manifest(path: pathlib.Path) -> list[Artifact]:
    artifacts: list[Artifact] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 6:
            raise ManifestError(f"{path}:{lineno}: expected at least 6 tab-separated fields")
        qb_version, libtorrent_version, arch, source, url, sha256 = fields[:6]
        if source != "static":
            continue
        if arch not in {"amd64", "arm64"}:
            raise ManifestError(f"{path}:{lineno}: unsupported manifest arch {arch!r}")
        artifacts.append(
            Artifact(
                qb_version=qb_version,
                libtorrent_version=libtorrent_version,
                arch=arch,
                repo_arch=arch,
                path=url,
                url=url,
                sha256=sha256,
            )
        )
    return artifacts


def verify_manifest(path: pathlib.Path, token: str | None, cache_dir: pathlib.Path | None, min_bytes: int) -> int:
    artifacts = read_manifest(path)
    if not artifacts:
        eprint(f"No static artifacts found in {path}")
        return 1
    failures = 0
    for idx, artifact in enumerate(artifacts, start=1):
        if not artifact.url:
            eprint(f"[{idx}/{len(artifacts)}] SKIP {artifact.qb_version}/{artifact.libtorrent_version}/{artifact.arch}: no URL")
            failures += 1
            continue
        if not re.fullmatch(r"[0-9a-f]{64}", artifact.sha256):
            eprint(f"[{idx}/{len(artifacts)}] FAIL {artifact.url}: invalid/missing sha256 in manifest")
            failures += 1
            continue
        try:
            data = fetch_artifact_bytes(artifact.url, token, cache_dir)
            validate_artifact_bytes(artifact, data, min_bytes=min_bytes)
            got = hashlib.sha256(data).hexdigest()
        except Exception as exc:  # noqa: BLE001 - this is a CLI diagnostic command.
            eprint(f"[{idx}/{len(artifacts)}] FAIL {artifact.url}: {exc}")
            failures += 1
            continue
        if got == artifact.sha256:
            eprint(f"[{idx}/{len(artifacts)}] OK   {artifact.url}")
        else:
            eprint(f"[{idx}/{len(artifacts)}] FAIL {artifact.url}: expected {artifact.sha256}, got {got}")
            failures += 1
    return 1 if failures else 0


def write_manifest(
    output: pathlib.Path,
    artifacts: Sequence[Artifact],
    *,
    owner: str,
    repo: str,
    discovery_ref: str,
    url_ref: str,
    local_repo: pathlib.Path | None,
    dry_run: bool,
) -> None:
    now = _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat()
    lines = [
        MANIFEST_HEADER,
        "#\n",
        f"# Generated by tools/generate_qbittorrent_manifest.py v{TOOL_VERSION}\n",
        f"# Generated at: {now}\n",
        f"# Repository: {owner}/{repo}\n",
        f"# Discovery ref: {discovery_ref}\n",
        f"# Raw URL ref: {url_ref}\n",
    ]
    if local_repo is not None:
        lines.append(f"# Local repo: {local_repo}\n")
    lines.extend(
        [
            "#\n",
            "# Static qBittorrent binaries are downloaded as root during installation.\n",
            "# Keep sha256 populated; do not use --allow-unverified-downloads in production.\n",
            "#\n",
        ]
    )
    for artifact in artifacts:
        lines.append(artifact.manifest_row())
    content = "".join(lines)

    if dry_run or str(output) == "-":
        sys.stdout.write(content)
        return

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(output.parent),
        prefix=f".{output.name}.",
        suffix=".tmp",
        delete=False,
    ) as tmp:
        tmp.write(content)
        tmp_path = pathlib.Path(tmp.name)
    os.replace(tmp_path, output)
    eprint(f"Wrote {len(artifacts)} entries to {output}")


def parse_csv(values: Sequence[str] | None) -> set[str]:
    result: set[str] = set()
    if not values:
        return result
    for value in values:
        for part in value.split(","):
            part = part.strip()
            if part:
                result.add(part)
    return result


def infer_repo_root() -> pathlib.Path:
    # The script usually lives in Dedicated-Seedbox/tools.
    return pathlib.Path(__file__).resolve().parents[1]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate Dedicated-Seedbox/manifests/qbittorrent.tsv with SHA-256 checksums.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--owner", default=DEFAULT_OWNER, help="GitHub owner to inspect")
    parser.add_argument("--repo", default=DEFAULT_REPO, help="GitHub repository to inspect")
    parser.add_argument("--ref", default=DEFAULT_REF, help="branch, tag, or commit to inspect")
    parser.add_argument(
        "--pin-url-ref",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="resolve --ref to a commit SHA and use that SHA in raw artifact URLs",
    )
    parser.add_argument(
        "--artifact-root",
        default=DEFAULT_ARTIFACT_ROOT,
        help="repository path containing qBittorrent architecture folders",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=pathlib.Path,
        default=infer_repo_root() / DEFAULT_OUTPUT,
        help="manifest path to write, or '-' for stdout",
    )
    parser.add_argument(
        "--local-repo",
        type=pathlib.Path,
        help="read artifacts from a local Dedicated-Seedbox checkout instead of GitHub raw downloads",
    )
    parser.add_argument(
        "--cache-dir",
        type=pathlib.Path,
        default=pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache"))
        / "seedbox-qbittorrent-manifest",
        help="cache downloaded artifacts by URL",
    )
    parser.add_argument("--no-cache", action="store_true", help="disable download cache")
    parser.add_argument(
        "--github-token",
        default=os.environ.get("GITHUB_TOKEN"),
        help="GitHub token; defaults to GITHUB_TOKEN environment variable",
    )
    parser.add_argument(
        "--arch",
        action="append",
        help="include only normalized architecture(s), e.g. amd64,arm64; may be repeated",
    )
    parser.add_argument(
        "--qb-version",
        action="append",
        help="include only qBittorrent version(s), e.g. 5.0.3; may be repeated",
    )
    parser.add_argument(
        "--libtorrent-version",
        action="append",
        help="include only libtorrent version(s), e.g. v2.0.11; may be repeated",
    )
    parser.add_argument(
        "--min-bytes",
        type=int,
        default=512 * 1024,
        help="minimum artifact size accepted as a real binary; use 0 to disable",
    )
    parser.add_argument("--dry-run", action="store_true", help="print manifest to stdout without writing")
    parser.add_argument(
        "--verify",
        type=pathlib.Path,
        metavar="MANIFEST",
        help="verify an existing manifest instead of generating a new one",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {TOOL_VERSION}")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        cache_dir = None if args.no_cache else args.cache_dir
        if args.verify:
            return verify_manifest(args.verify, args.github_token, cache_dir, args.min_bytes)

        requested_arches = parse_csv(args.arch)
        invalid_arches = requested_arches - {"amd64", "arm64"}
        if invalid_arches:
            die(f"unsupported --arch value(s): {', '.join(sorted(invalid_arches))}", code=2)
        qb_versions = parse_csv(args.qb_version)
        libtorrent_versions = parse_csv(args.libtorrent_version)

        discovery_ref = args.ref
        if args.local_repo:
            local_repo = args.local_repo.resolve()
            if not local_repo.exists():
                raise ManifestError(f"--local-repo does not exist: {local_repo}")
            if args.pin_url_ref:
                try:
                    url_ref = resolve_ref(args.owner, args.repo, args.ref, args.github_token)
                except ManifestError:
                    # Local generation should remain usable offline; fall back to the requested ref.
                    eprint("warning: could not resolve --ref to a commit SHA; using the provided ref in URLs")
                    url_ref = args.ref
            else:
                url_ref = args.ref
            artifacts = discover_local_artifacts(local_repo, args.owner, args.repo, url_ref, args.artifact_root)
        else:
            local_repo = None
            if args.pin_url_ref:
                url_ref = resolve_ref(args.owner, args.repo, args.ref, args.github_token)
            else:
                url_ref = args.ref
            artifacts = discover_remote_artifacts(
                args.owner,
                args.repo,
                discovery_ref,
                url_ref,
                args.github_token,
                args.artifact_root,
            )

        artifacts = apply_filters(artifacts, requested_arches, qb_versions, libtorrent_versions)
        if not artifacts:
            raise ManifestError("no qBittorrent static artifacts matched the requested filters")

        if args.local_repo:
            # Local artifacts already contain checksums.
            for artifact in artifacts:
                local_file = args.local_repo.resolve() / pathlib.Path(*artifact.path.split("/"))
                validate_artifact_bytes(artifact, local_file.read_bytes(), min_bytes=args.min_bytes)
            checked = artifacts
        else:
            checked = checksum_remote_artifacts(artifacts, args.github_token, cache_dir, args.min_bytes)

        write_manifest(
            args.output,
            checked,
            owner=args.owner,
            repo=args.repo,
            discovery_ref=discovery_ref,
            url_ref=url_ref,
            local_repo=local_repo,
            dry_run=args.dry_run,
        )
        return 0
    except ManifestError as exc:
        eprint(f"error: {exc}")
        return 1
    except KeyboardInterrupt:
        eprint("interrupted")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
