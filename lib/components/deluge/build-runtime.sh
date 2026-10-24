#!/usr/bin/env bash
# All obsolete libraries stay private: never run ldconfig or change system Python.
set -Eeuo pipefail
umask 022
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PREFIX=/opt/deluge-1.3.15
CACHE=/var/cache/seedbox-deluge-1.3.15
JOBS=2
OFFLINE=0
while (($#)); do
  case "$1" in
    --jobs)
      JOBS="${2:?Missing jobs}"
      shift 2
      ;;
    --source-dir)
      CACHE="${2:?Missing source directory}"
      OFFLINE=1
      shift 2
      ;;
    *)
      printf 'Unknown runtime build option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done
[[ "${JOBS}" =~ ^[1-9][0-9]?$ ]] || {
  echo 'Jobs must be between 1 and 99.' >&2
  exit 2
}
[[ ${EUID} == 0 ]] || {
  echo 'Runtime compilation requires root.' >&2
  exit 1
}
case "$(uname -m)" in x86_64 | aarch64) ;; *)
  echo 'Only amd64 and arm64 are supported.' >&2
  exit 1
  ;;
esac
source /etc/os-release
case "${ID}:${VERSION_ID}" in
  debian:*) [[ "${VERSION_ID%%.*}" -ge 12 ]] ;;
  ubuntu:*) [[ "${VERSION_ID%%.*}" -ge 22 ]] ;;
  *) false ;;
esac || {
  echo 'Use Debian 12+ or Ubuntu 22.04+.' >&2
  exit 1
}
# Bundled with the runtime, not fetched from a mutable branch during a build.
[[ -f "${HERE}/patches.lock" && ! -L "${HERE}/patches.lock" && -f "${HERE}/libtorrent-1.1.14.patch" && ! -L "${HERE}/libtorrent-1.1.14.patch" ]] || exit 1
(cd -- "${HERE}" && sha256sum --strict -c patches.lock)
exec 9>/run/lock/seedbox-deluge-runtime.lock
flock -n 9 || {
  echo 'Another Deluge runtime build is active.' >&2
  exit 1
}
FINGERPRINT="$({
  cat "${HERE}/sources.lock" "${HERE}/patches.lock" "${HERE}/libtorrent-1.1.14.patch" "${BASH_SOURCE[0]}" "${HERE}/runtime-check.py" /etc/os-release
  uname -m
} | sha256sum | cut -d' ' -f1)"
if [[ -e "${PREFIX}" || -L "${PREFIX}" ]]; then
  [[ -d "${PREFIX}" && ! -L "${PREFIX}" && "$(stat -c '%u:%a' "${PREFIX}")" == 0:755 ]] || {
    echo 'Unsafe runtime directory.' >&2
    exit 1
  }
  if [[ -f "${PREFIX}/runtime.id" && "$(cat "${PREFIX}/runtime.id")" == "${FINGERPRINT}" ]]; then
    env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH PYTHONNOUSERSITE=1 "${PREFIX}/bin/python2.7" -s "${HERE}/runtime-check.py"
    exit
  fi
  echo "Refusing to overwrite an unknown, incomplete, or different runtime: ${PREFIX}" >&2
  echo 'Move it aside after stopping its services, then rerun the build.' >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl \
  pkg-config zlib1g-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncurses-dev liblzma-dev libgdbm-dev uuid-dev intltool python3 perl xz-utils unzip patch
if ((OFFLINE == 0)); then
  [[ ! -L "${CACHE}" ]] || {
    echo 'Refusing a symlink cache.' >&2
    exit 1
  }
  install -d -m 0755 -o root -g root "${CACHE}"
fi
[[ -d "${CACHE}" ]] || {
  echo 'Source directory does not exist.' >&2
  exit 1
}
while read -r digest filename url; do
  [[ -n "${digest}" && "${digest}" != \#* ]] || continue
  [[ "${digest}" =~ ^[0-9a-f]{64}$ && "${filename}" != */* && "${url}" == https://* ]] || exit 1
  if [[ ! -e "${CACHE}/${filename}" && ${OFFLINE} == 0 ]]; then
    tmp="$(mktemp "${CACHE}/download.XXXXXX")"
    curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 600 --retry 3 "${url}" -o "${tmp}"
    printf '%s  %s\n' "${digest}" "${tmp}" | sha256sum -c -
    mv -T -- "${tmp}" "${CACHE}/${filename}"
  fi
  [[ -f "${CACHE}/${filename}" && ! -L "${CACHE}/${filename}" ]] || {
    echo "Missing or unsafe source: ${filename}" >&2
    exit 1
  }
  printf '%s  %s\n' "${digest}" "${CACHE}/${filename}" | sha256sum -c -
done <"${HERE}/sources.lock"

WORK="$(mktemp -d /var/tmp/seedbox-deluge-build.XXXXXX)"
trap 'rc=$?; if ((rc)); then printf "Runtime build failed; source/build evidence retained at %s\n" "${WORK}" >&2; else rm -rf -- "${WORK}"; fi' EXIT
# Compile only copies checked inside a root-private directory, even when the
# supplied source directory is writable by somebody else.
mkdir "${WORK}/sources"
while read -r digest filename url; do
  [[ -n "${digest}" && "${digest}" != \#* ]] || continue
  cp -- "${CACHE}/${filename}" "${WORK}/sources/${filename}"
  printf '%s  %s\n' "${digest}" "${WORK}/sources/${filename}" | sha256sum -c -
done <"${HERE}/sources.lock"
CACHE="${WORK}/sources"
cp -- "${HERE}/patches.lock" "${HERE}/libtorrent-1.1.14.patch" "${CACHE}/"
(cd -- "${CACHE}" && sha256sum --strict -c patches.lock)
install -d -m 0700 "${WORK}/home"
export HOME="${WORK}/home"
# setuptools' old setup_requires otherwise ignores pip's --no-index switch.
printf '[easy_install]\nindex_url = file:///dev/null\nallow_hosts = none\n' >"${HOME}/.pydistutils.cfg"
install -d -m 0755 -o root -g root "${PREFIX}"
export PATH="${PREFIX}/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH="${PREFIX}/lib:${PREFIX}/openssl/lib"
export CPPFLAGS="-I${PREFIX}/include -I${PREFIX}/openssl/include"
export LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/openssl/lib -Wl,-rpath,${PREFIX}/lib -Wl,-rpath,${PREFIX}/openssl/lib"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/openssl/lib/pkgconfig"
unset PYTHONPATH PYTHONHOME
export PYTHONNOUSERSITE=1
# Python 2.7 defines bool/true/false itself, which is incompatible with C23.
export CFLAGS='-O2 -std=gnu11 -fPIC -fwrapv -fno-strict-aliasing -Wno-implicit-function-declaration -Wno-int-conversion'
export CXXFLAGS='-O2 -fPIC -std=c++11'
export PIP_CONFIG_FILE=/dev/null PIP_NO_INDEX=1 PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_BUILD_ISOLATION=1
extract() {
  tar --extract --file "${CACHE}/$1" --directory "${WORK}" --no-same-owner --no-same-permissions
}
echo 'Building private OpenSSL 1.1.1w'
extract openssl-1.1.1w.tar.gz
cd "${WORK}/openssl-1.1.1w"
./config --prefix="${PREFIX}/openssl" --openssldir="${PREFIX}/openssl/ssl" shared "-Wl,-rpath,${PREFIX}/openssl/lib"
make -j"${JOBS}"
make install_sw
install -d "${PREFIX}/openssl/ssl"
ln -s /etc/ssl/certs "${PREFIX}/openssl/ssl/certs"
ln -s /etc/ssl/certs/ca-certificates.crt "${PREFIX}/openssl/ssl/cert.pem"

echo 'Building private Python 2.7.18'
extract Python-2.7.18.tar.xz
cd "${WORK}/Python-2.7.18"
./configure --prefix="${PREFIX}" --enable-shared --with-ensurepip=install
make -j"${JOBS}"
make install
PYTHON="${PREFIX}/bin/python2.7"
"${PYTHON}" -c 'import ssl, bz2, sqlite3, ctypes; assert "1.1.1w" in ssl.OPENSSL_VERSION; print(ssl.OPENSSL_VERSION)'

echo 'Installing locked Python packages into the private runtime'
"${PYTHON}" -m pip install --no-deps --no-cache-dir \
  "${CACHE}/pip-20.3.4-py2.py3-none-any.whl" \
  "${CACHE}/setuptools-44.1.1-py2.py3-none-any.whl" \
  "${CACHE}/wheel-0.37.1-py2.py3-none-any.whl"
while read -r digest filename url; do
  case "${filename:-}" in
    six-* | pycparser-* | cffi-* | incremental-* | constantly-* | attrs-* | zope.interface-* | Automat-* | idna-* | hyperlink-* | enum34-* | ipaddress-* | cryptography-* | pyOpenSSL-* | pyasn1-* | pyasn1-modules-* | service_identity-* | MarkupSafe-* | Mako-* | chardet-* | pyxdg-* | PyHamcrest-* | Twisted-*)
      "${PYTHON}" -m pip install --no-deps --no-build-isolation --no-cache-dir "${CACHE}/${filename}"
      ;;
  esac
done <"${HERE}/sources.lock"
"${PYTHON}" -m pip check

echo 'Building private Boost 1.69.0'
extract boost_1_69_0.tar.bz2
cd "${WORK}/boost_1_69_0"
./bootstrap.sh --prefix="${PREFIX}" --with-libraries=python,system,chrono,random --with-python="${PYTHON}"
./b2 -j"${JOBS}" --layout=system variant=release link=shared threading=multi \
  cxxflags='-std=c++11 -fPIC' "linkflags=${LDFLAGS}" install

echo 'Building private libtorrent 1.1.14 with qBittorrent tuning patch and Python 2 bindings'
extract libtorrent-rasterbar-1.1.14.tar.gz
cd "${WORK}/libtorrent-rasterbar-1.1.14"
patch --batch --forward --fuzz=0 --dry-run -p1 <"${CACHE}/libtorrent-1.1.14.patch"
patch --batch --forward --fuzz=0 -p1 <"${CACHE}/libtorrent-1.1.14.patch"
PYTHON="${PYTHON}" ./configure --prefix="${PREFIX}" --with-boost="${PREFIX}" \
  --with-boost-libdir="${PREFIX}/lib" --with-boost-python=boost_python27 \
  --with-openssl="${PREFIX}/openssl" --enable-python-binding --disable-static
make -j"${JOBS}"
make install
"${PYTHON}" -c 'import libtorrent; assert libtorrent.version.startswith("1.1.14"); print(libtorrent.version)'

echo 'Installing Deluge 1.3.15'
extract deluge-1.3.15.tar.xz
cd "${WORK}/deluge-1.3.15"
"${PYTHON}" setup.py build
"${PYTHON}" setup.py install --single-version-externally-managed --record "${PREFIX}/deluge-files.txt"
install -d "${PREFIX}/plugins"
install -m 0644 "${CACHE}/ltConfig-0.3.1-py2.7.egg" "${PREFIX}/plugins/"
env -u LD_LIBRARY_PATH "${PYTHON}" -s "${HERE}/runtime-check.py"
cp "${HERE}/sources.lock" "${PREFIX}/sources.lock"
cp "${CACHE}/patches.lock" "${CACHE}/libtorrent-1.1.14.patch" "${PREFIX}/"
printf '%s\n' "${FINGERPRINT}" >"${PREFIX}/runtime.id"
echo "Deluge 1.3.15 runtime installed at ${PREFIX}; system Python is unchanged."
