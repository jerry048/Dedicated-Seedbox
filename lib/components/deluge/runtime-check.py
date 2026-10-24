#!/usr/bin/env python2.7
"""Fail before service activation if the private legacy ABI is incomplete."""

from __future__ import print_function

import ssl
import sys

import deluge.common
import cryptography
import libtorrent
import OpenSSL
import pip
import setuptools
import twisted
import wheel
from deluge.core import core
from deluge.ui.web import server
from service_identity import VerificationError

assert sys.version_info[:3] == (2, 7, 18), sys.version
assert sys.prefix == "/opt/deluge-1.3.15", sys.prefix
assert deluge.common.get_version() == "1.3.15"
assert libtorrent.version.startswith("1.1.14"), libtorrent.version
# Version strings alone cannot distinguish stock and patched libtorrent builds.
defaults = libtorrent.default_settings()
for key, expected in {
    "max_queued_disk_bytes": 262144000,
    "listen_queue_size": 3000,
    "connections_limit": 500000,
    "checking_mem_usage": 8192,
    "cache_size_volatile": 128,
    "cache_size": -1,
    "smooth_connects": False,
    "max_allowed_in_request_queue": 10000,
    "max_out_request_queue": 10000,
    "connection_speed": 500,
    "enable_upnp": False,
    "enable_natpmp": False,
    "enable_lsd": False,
    "enable_dht": False,
}.items():
    assert defaults[key] == expected, (key, defaults[key], expected)
assert twisted.__version__ == "20.3.0", twisted.__version__
assert OpenSSL.__version__ == "21.0.0", OpenSSL.__version__
assert cryptography.__version__ == "3.3.2", cryptography.__version__
assert pip.__version__ == "20.3.4", pip.__version__
assert setuptools.__version__ == "44.1.1", setuptools.__version__
assert wheel.__version__ == "0.37.1", wheel.__version__
assert "1.1.1w" in ssl.OPENSSL_VERSION, ssl.OPENSSL_VERSION
print("PASS: Deluge 1.3.15 / Python 2.7.18 / patched libtorrent " + libtorrent.version)
