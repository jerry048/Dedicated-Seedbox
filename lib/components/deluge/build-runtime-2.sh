#!/usr/bin/env bash
# Deluge 2.2.0: pair-specific native Python/Boost/libtorrent, never system pip.
set -Eeuo pipefail
umask 022
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LT_VERSION=2.0.15 JOBS=2 OFFLINE=0 CACHE=/var/cache/seedbox-deluge-2.2.0
while (($#)); do
  case "$1" in
    --libtorrent-version)
      LT_VERSION="${2:?Missing libtorrent version}"
      shift 2
      ;;
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
case "${LT_VERSION}" in 1.2.20 | 2.0.15) ;; *)
  echo 'Deluge 2.2.0 supports libtorrent 1.2.20 or 2.0.15.' >&2
  exit 2
  ;;
esac
[[ "${JOBS}" =~ ^[1-9][0-9]?$ && ${EUID} == 0 ]] || exit 2
case "$(uname -m)" in x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; *) exit 2 ;; esac
source /etc/os-release
case "${ID}:${VERSION_ID}" in debian:*) [[ "${VERSION_ID%%.*}" -ge 12 ]] ;; ubuntu:*) [[ "${VERSION_ID%%.*}" -ge 22 ]] ;; *) false ;; esac || exit 2
PREFIX="/opt/deluge-2.2.0-lt-${LT_VERSION}"
LOCKS=("${HERE}/sources-2.2.0-common.lock" "${HERE}/sources-2.2.0-${ARCH}.lock")
for file in "${LOCKS[@]}" "${HERE}/patches-2.2.0.lock" "${HERE}/libtorrent-1.2.20.patch" "${HERE}/libtorrent-2.0.15.patch" "${HERE}/deluge-2.2.0-crypto.patch"; do
  [[ -f "${file}" && ! -L "${file}" ]] || exit 1
done
(cd -- "${HERE}" && sha256sum --strict -c patches-2.2.0.lock)
exec 9>"/run/lock/seedbox-deluge-2.2.0-${LT_VERSION}.lock"
flock -n 9 || {
  echo 'Another build of this runtime is active.' >&2
  exit 1
}
FINGERPRINT="$({
  cat "${LOCKS[@]}" "${HERE}/patches-2.2.0.lock" "${HERE}/libtorrent-1.2.20.patch" "${HERE}/libtorrent-2.0.15.patch" "${HERE}/deluge-2.2.0-crypto.patch" "${BASH_SOURCE[0]}" "${HERE}/runtime-check-2.py" /etc/os-release
  printf '%s\n' "${ARCH}" "${LT_VERSION}"
} | sha256sum | cut -d' ' -f1)"
if [[ -e "${PREFIX}" || -L "${PREFIX}" ]]; then
  [[ -d "${PREFIX}" && ! -L "${PREFIX}" && "$(stat -c '%u:%a' "${PREFIX}")" == 0:755 ]] || exit 1
  if [[ -f "${PREFIX}/runtime.id" && ! -L "${PREFIX}/runtime.id" && "$(cat "${PREFIX}/runtime.id")" == "${FINGERPRINT}" ]]; then
    env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "${PREFIX}/bin/python3" -I "${HERE}/runtime-check-2.py" --libtorrent-version "${LT_VERSION}"
    exit
  fi
  printf 'Refusing to overwrite an unknown, incomplete, or different runtime: %s\n' "${PREFIX}" >&2
  echo 'Stop affected instances and retain/move the old runtime aside before rebuilding.' >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl cmake patch \
  pkg-config libssl-dev zlib1g-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncurses-dev liblzma-dev libgdbm-dev uuid-dev python3 perl xz-utils
if ((OFFLINE == 0)); then
  [[ ! -L "${CACHE}" ]] || exit 1
  install -d -m 0755 -o root -g root "${CACHE}"
fi
[[ -d "${CACHE}" ]] || exit 1
WORK="$(mktemp -d /var/tmp/seedbox-deluge2-build.XXXXXX)"
trap 'rc=$?; if ((rc)); then printf "Build failed; private evidence retained at %s\n" "${WORK}" >&2; else rm -rf -- "${WORK}"; fi' EXIT
mkdir "${WORK}/sources"
while read -r digest filename url; do
  [[ -n "${digest}" && "${digest}" != \#* ]] || continue
  [[ "${digest}" =~ ^[0-9a-f]{64}$ && "${filename}" != */* && "${url}" == https://* ]] || exit 1
  if [[ ! -e "${CACHE}/${filename}" && ${OFFLINE} == 0 ]]; then
    temporary="$(mktemp "${CACHE}/download.XXXXXX")"
    curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 600 --retry 3 "${url}" -o "${temporary}"
    printf '%s  %s\n' "${digest}" "${temporary}" | sha256sum -c -
    mv -T -- "${temporary}" "${CACHE}/${filename}"
  fi
  [[ -f "${CACHE}/${filename}" && ! -L "${CACHE}/${filename}" ]] || exit 1
  cp -- "${CACHE}/${filename}" "${WORK}/sources/${filename}"
  printf '%s  %s\n' "${digest}" "${WORK}/sources/${filename}" | sha256sum -c -
done < <(cat "${LOCKS[@]}")
cp -- "${HERE}/patches-2.2.0.lock" "${HERE}/libtorrent-1.2.20.patch" "${HERE}/libtorrent-2.0.15.patch" "${HERE}/deluge-2.2.0-crypto.patch" "${WORK}/sources/"
(cd -- "${WORK}/sources" && sha256sum --strict -c patches-2.2.0.lock)
CACHE="${WORK}/sources"
install -d -m 0755 -o root -g root "${PREFIX}"
install -d -m 0700 "${WORK}/home"
export HOME="${WORK}/home" PYTHONNOUSERSITE=1 PIP_CONFIG_FILE=/dev/null PIP_NO_INDEX=1 PIP_DISABLE_PIP_VERSION_CHECK=1
unset PYTHONPATH PYTHONHOME LD_LIBRARY_PATH
export PATH="${PREFIX}/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LDFLAGS="-Wl,-rpath,${PREFIX}/lib" CFLAGS='-O2 -std=gnu11' CXXFLAGS='-O2 -std=c++14'
extract() { tar --extract --file "${CACHE}/$1" --directory "${WORK}" --no-same-owner --no-same-permissions; }
echo 'Building private CPython 3.11.17 against the host OpenSSL 3'
extract Python-3.11.17.tar.xz
cd "${WORK}/Python-3.11.17"
./configure --prefix="${PREFIX}" --enable-shared --with-ensurepip=install
make -j"${JOBS}"
make install
PYTHON="${PREFIX}/bin/python3"
"${PYTHON}" -I -m pip install --no-index --no-deps --no-cache-dir "${CACHE}"/*.whl
"${PYTHON}" -I -m pip check
SITE="$("${PYTHON}" -I -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
patch --directory "${SITE}" --batch --forward --fuzz=0 --dry-run -p1 <"${CACHE}/deluge-2.2.0-crypto.patch"
patch --directory "${SITE}" --batch --forward --fuzz=0 -p1 <"${CACHE}/deluge-2.2.0-crypto.patch"
echo 'Building private Boost 1.83.0 with Python 3.11 bindings'
extract boost_1_83_0.tar.bz2
cd "${WORK}/boost_1_83_0"
./bootstrap.sh --prefix="${PREFIX}" --with-libraries=python,system,chrono,random --with-python="${PYTHON}"
./b2 -j"${JOBS}" --layout=system variant=release link=shared threading=multi \
  cxxflags='-std=c++14 -fPIC' "linkflags=${LDFLAGS}" install
echo "Building patched libtorrent ${LT_VERSION} and native Python bindings"
extract "libtorrent-rasterbar-${LT_VERSION}.tar.gz"
cd "${WORK}/libtorrent-rasterbar-${LT_VERSION}"
patch --batch --forward --fuzz=0 --dry-run -p1 <"${CACHE}/libtorrent-${LT_VERSION}.patch"
patch --batch --forward --fuzz=0 -p1 <"${CACHE}/libtorrent-${LT_VERSION}.patch"
cmake -S . -B "${WORK}/lt-build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_CXX_STANDARD=14 -DCMAKE_INSTALL_RPATH="${PREFIX}/lib" \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_POLICY_DEFAULT_CMP0167=OLD -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT="${PREFIX}" \
  -DBOOST_LIBRARYDIR="${PREFIX}/lib" -DPython3_ROOT_DIR="${PREFIX}" -DPython3_EXECUTABLE="${PYTHON}" \
  -Dpython-bindings=ON -Dpython-egg-info=OFF -Ddeprecated-functions=ON \
  -Dbuild_tests=OFF -Dbuild_examples=OFF -Dbuild_tools=OFF -DBUILD_SHARED_LIBS=ON
cmake --build "${WORK}/lt-build" --parallel "${JOBS}"
cmake --install "${WORK}/lt-build"
install -d -m 0755 "${PREFIX}/plugins"
install -m 0644 "${CACHE}/ltConfig-2.0.0.egg" "${PREFIX}/plugins/"
env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "${PYTHON}" -I "${HERE}/runtime-check-2.py" --libtorrent-version "${LT_VERSION}"
cp -- "${LOCKS[@]}" "${CACHE}/patches-2.2.0.lock" "${CACHE}/libtorrent-1.2.20.patch" "${CACHE}/libtorrent-2.0.15.patch" "${CACHE}/deluge-2.2.0-crypto.patch" "${PREFIX}/"
printf '%s\n' "${FINGERPRINT}" >"${PREFIX}/runtime.id"
printf 'Deluge 2.2.0 / libtorrent %s installed at %s; system Python is unchanged.\n' "${LT_VERSION}" "${PREFIX}"
