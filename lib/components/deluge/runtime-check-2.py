#!/usr/bin/env python3
"""Validate one private Deluge 2.2.0/libtorrent ABI before service activation."""

import argparse
import ssl
import sys
import tempfile
from pathlib import Path

import deluge.common
import deluge.configmanager
import deluge.crypto_utils
import libtorrent
from deluge.core import core
from deluge.ui.web import server

parser = argparse.ArgumentParser()
parser.add_argument("--libtorrent-version", choices=("1.2.20", "2.0.15"), required=True)
args = parser.parse_args()
assert sys.version_info[:3] == (3, 11, 17), sys.version
assert sys.prefix == "/opt/deluge-2.2.0-lt-" + args.libtorrent_version, sys.prefix
assert deluge.common.get_version() == "2.2.0"
assert libtorrent.version.startswith(args.libtorrent_version), libtorrent.version
assert ssl.OPENSSL_VERSION.startswith("OpenSSL 3."), ssl.OPENSSL_VERSION
settings = libtorrent.default_settings()
expected = {
    "max_queued_disk_bytes": 262144000,
    "listen_queue_size": 3000,
    "connections_limit": 500000,
    "connection_speed": 500,
    "checking_mem_usage": 8192,
    "max_allowed_in_request_queue": 10000,
    "enable_upnp": False,
    "enable_natpmp": False,
    "enable_dht": False,
    "enable_lsd": False,
}
if args.libtorrent_version == "1.2.20":
    expected.update(cache_size=-1, cache_size_volatile=128, file_pool_size=5000)
else:
    expected.update(file_pool_size=100, hashing_threads=2, aio_threads=4)
for key, value in expected.items():
    assert settings[key] == value, (key, settings[key], value)
with tempfile.TemporaryDirectory(prefix="seedbox-deluge2-tls-") as temporary:
    deluge.configmanager.set_config_dir(temporary)
    deluge.crypto_utils.check_ssl_keys()
    ssl_dir = Path(temporary) / "ssl"
    deluge.crypto_utils.get_context_factory(
        str(ssl_dir / "daemon.cert"), str(ssl_dir / "daemon.pkey")
    ).getContext()
print(
    "PASS: Deluge 2.2.0 / private Python 3.11.17 / patched libtorrent "
    + libtorrent.version
)
