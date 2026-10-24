#!/usr/bin/env python2.7
"""Check local Deluge RPC without disclosing or changing stored credentials."""

import argparse
import json
import os
import pwd
import stat
import sys

from deluge.ui.client import client
from twisted.internet import reactor


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rpc-port", type=int, required=True)
    parser.add_argument(
        "--deluge-version", choices=("1.3.15", "2.2.0"), default="1.3.15"
    )
    args = parser.parse_args()
    if os.getuid() == 0:
        return 1
    account = pwd.getpwuid(os.getuid())
    path = os.path.join(
        account.pw_dir,
        ".config",
        "deluge",
        "hostlist.conf.1.2" if args.deluge_version == "1.3.15" else "hostlist.conf",
    )
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            return 1
        data = stream.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        return 1
    decoder = json.JSONDecoder()
    _, offset = decoder.raw_decode(data.decode("utf-8").lstrip())
    hosts, _ = decoder.raw_decode(data.decode("utf-8").lstrip()[offset:].lstrip())
    matches = [
        entry
        for entry in hosts["hosts"]
        if isinstance(entry, list)
        and len(entry) == 5
        and entry[1] == "127.0.0.1"
        and entry[2] == args.rpc_port
        and entry[3]
        == (account.pw_name if args.deluge_version == "1.3.15" else "localclient")
    ]
    if len(matches) != 1:
        return 1
    username, password = matches[0][3:5]
    result = [1]

    def finish(value=None):
        result[0] = 0 if value == args.deluge_version else 1
        client.disconnect()
        if reactor.running:
            reactor.stop()

    reactor.callLater(6, finish)
    deferred = client.connect("127.0.0.1", args.rpc_port, username, password)
    deferred.addCallback(
        lambda unused: (
            client.daemon.info()
            if args.deluge_version == "1.3.15"
            else client.daemon.get_version()
        )
    )
    deferred.addCallbacks(finish, lambda failure: finish())
    reactor.run()
    return result[0]


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        sys.exit(1)
