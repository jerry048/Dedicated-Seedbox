# qBittorrent-nox static

## Static builds with modified libtorrent settings

The libtorrent tuning patches are maintained in [`jerry048/Patch`](https://github.com/jerry048/Patch).

Builds use [userdocs' qbittorrent-nox-static script](https://github.com/userdocs/qbittorrent-nox-static).

The binaries support dedicated hosts and shared/rootless accounts.

## Available versions

Both `x86_64` (amd64) and `ARM64` (aarch64) use the same version matrix:

| qBittorrent                       | libtorrent versions                   |
| --------------------------------- | ------------------------------------- |
| 4.1.9.1                           | 1.1.14 (legacy folder name: `1_1_14`) |
| 4.2.5, 4.3.9                      | 1.2.20                                |
| 4.4.5, 4.5.5, 4.6.7, 5.0.5, 5.1.4 | 1.2.20, **2.0.15**                    |
| **5.2.4**                         | **1.2.20, 2.0.15**                    |
| **5.3.0**                         | **1.2.20, 2.1.2**                     |

Static builds made with the pinned inputs below use Docker Desktop's Linux engine,
userdocs' static-build script and the Jerry048 patches. Their disk-queue default
is **250 MiB**; request-queue ceilings remain **10,000 blocks per peer**.
Build-only alignment patches prevent older qBittorrent defaults from replacing
the patched libtorrent disk queue, socket backlog, connection limit and port-mapping
defaults. Explicit settings in existing profiles still take precedence.

### Build inputs

- Builder: [`userdocs/qbittorrent-nox-static@546b0b6`](https://github.com/userdocs/qbittorrent-nox-static/commit/546b0b60d613dec875f34fc190a1123ca799783b).
- Libtorrent patches: [`jerry048/Patch@d928969`](https://github.com/jerry048/Patch/tree/d928969c184d9f99de528151d0759c726ff7d2de/patches).
- Build dependencies: Qt **6.8.3**, Boost **1.86.0**, OpenSSL **3.5.9**,
  and zlib **1.3.2**. Builds are fully static, with LTO and native-CPU-only
  optimizations disabled for portability and manageable build memory use.
- qBittorrent 4.6.7 requires C++17; the builder's C++ version map must include
  `cxx_version_map["qbittorrent:4.6.999"]=17`.

Use the builder's local patch layout under
`qbt-build/patches/qbittorrent/VERSION/patch`; place the matching libtorrent
patch under `qbt-build/patches/libtorrent/VERSION/patch`. Pass the exact tags
with `-qt release-QB_VERSION -lt vLIBTORRENT_VERSION`. The same
qBittorrent patch supports both listed libtorrent variants for that release.

The installer manifest at [`manifests/qbittorrent.tsv`](../../manifests/qbittorrent.tsv)
records SHA-256 checksums and commit-pinned download URLs. The binaries are
checked for the correct architecture, static linkage, qBittorrent/libtorrent
versions and exposed WebAPI defaults before being added to the repository.

**Security:** The supplied qBittorrent patches retain the existing disabled
WebUI CSRF-protection default. Enable CSRF protection when appropriate for your
deployment.
