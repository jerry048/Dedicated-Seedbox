# qBittorrent-nox static
#### Static build with modified libtorrent settings

The patches used in compile can be found [here](https://github.com/jerry048/Patch)

The script used to compile the build is [userdocs' qbittorrent-nox-static script](https://github.com/userdocs/qbittorrent-nox-static)

Could be used in both Dedicated Seedbox & Shared Seedbox

## Available versions

Both `x86_64` (amd64) and `ARM64` (aarch64) use the same version matrix:

| qBittorrent | libtorrent versions |
| --- | --- |
| 4.1.9.1 | 1.1.14 (legacy folder name: `1_1_14`) |
| 4.2.5, 4.3.9 | 1.2.20 |
| 4.4.5, 4.5.5, 4.6.7, 5.0.5, 5.1.4 | 1.2.20, **2.0.15** |
| **5.2.4** | **1.2.20, 2.0.15** |
| **5.3.0** | **1.2.20, 2.1.2** |

5.2.4 replaces 5.2.2. All former 2.0.13 builds are replaced by 2.0.15;
5.3.0 uses 2.1.2, which it supports upstream, rather than backporting the 2.1 API
changes into older qBittorrent releases. Existing older 1.2.20 builds are retained.

The updated binaries are built with Docker Desktop's Linux engine using
userdocs' static-build script and the Jerry048 patches. Their disk-queue default
is **250 MiB**; request-queue ceilings remain **10,000 blocks per peer**.
Build-only alignment patches prevent older qBittorrent defaults from replacing
the new libtorrent disk queue, socket backlog, connection limit and port-mapping
defaults. Explicit settings in existing profiles still take precedence.

### Build inputs

- Builder: [`userdocs/qbittorrent-nox-static@546b0b6`](https://github.com/userdocs/qbittorrent-nox-static/commit/546b0b60d613dec875f34fc190a1123ca799783b).
- Libtorrent patches: [`jerry048/Patch@d928969`](https://github.com/jerry048/Patch/tree/d928969c184d9f99de528151d0759c726ff7d2de/patches).
- Updated-build dependencies: Qt **6.8.3**, Boost **1.86.0**, OpenSSL **3.5.9**,
  and zlib **1.3.2**. Builds are fully static, with LTO and native-CPU-only
  optimizations disabled for portability and manageable build memory use.
- Build-script correction: extend `cxx_version_map["qbittorrent:4.5.999"]=17`
  to `cxx_version_map["qbittorrent:4.6.999"]=17`, matching 4.6.7's actual C++17
  requirement instead of the builder's contradictory C++20 floor/C++17 ceiling.

Use the builder's local patch layout under
`qbt-build/patches/qbittorrent/<version>/patch`; place the matching libtorrent
patch under `qbt-build/patches/libtorrent/<version>/patch`. Pass the exact tags
with `-qt release-<qBittorrent-version> -lt v<libtorrent-version>`. The same
qBittorrent patch supports both listed libtorrent variants for that release.

The installer manifest at [`manifests/qbittorrent.tsv`](../../manifests/qbittorrent.tsv)
records SHA-256 checksums and commit-pinned download URLs. The binaries are
checked for the correct architecture, static linkage, qBittorrent/libtorrent
versions and exposed WebAPI defaults before being added to the repository.

**Security:** The supplied qBittorrent patches retain the existing disabled
WebUI CSRF-protection default. Enable CSRF protection when appropriate for your
deployment.

