#!/usr/bin/env python3
"""Readiness means authenticated WebUI access and a working daemon RPC link."""

import argparse
import gzip
import http.cookiejar
import json
import os
import pwd
import sys
import urllib.error
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--web-port", type=int, required=True)
    parser.add_argument(
        "--deluge-version", choices=("1.3.15", "2.2.0"), default="1.3.15"
    )
    args = parser.parse_args()
    password = sys.stdin.buffer.read(4097).rstrip(b"\r\n").decode("utf-8")
    profile = Path(pwd.getpwuid(os.getuid()).pw_dir) / ".config" / "deluge"
    text = (
        profile
        / ("hostlist.conf.1.2" if args.deluge_version == "1.3.15" else "hostlist.conf")
    ).read_text()
    decoder = json.JSONDecoder()
    _, end = decoder.raw_decode(text)
    hosts, _ = decoder.raw_decode(text[end:].lstrip())
    host_id = hosts["hosts"][0][0]
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
    )

    def rpc(method, params):
        data = json.dumps({"method": method, "params": params, "id": 1}).encode()
        request = urllib.request.Request(
            "http://127.0.0.1:" + str(args.web_port) + "/json",
            data=data,
            headers={"Content-Type": "application/json"},
        )
        with opener.open(request, timeout=2) as response:
            payload = response.read(1048576)
            if response.headers.get("Content-Encoding", "").lower() == "gzip":
                payload = gzip.decompress(payload)
            result = json.loads(payload.decode("utf-8"))
        if result.get("error"):
            raise ValueError("Deluge RPC is not ready")
        return result["result"]

    if rpc("auth.login", [password]) is not True:
        return 1
    rpc("web.connect", [host_id])
    if rpc("web.connected", []) is not True:
        return 1
    method = "daemon.info" if args.deluge_version == "1.3.15" else "daemon.get_version"
    return 0 if rpc(method, []) == args.deluge_version else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, IndexError, urllib.error.URLError):
        sys.exit(1)
