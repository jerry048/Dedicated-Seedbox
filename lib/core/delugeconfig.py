#!/usr/bin/env python3
"""Read, create, snapshot and purge versioned Deluge settings as their owner."""

import argparse
import hashlib
import json
import os
import pwd
import secrets
import stat
import sys
import tempfile
from pathlib import Path

FILES = ("core.conf", "web.conf", "hostlist.conf.1.2", "auth", "ltconfig.conf")
DELUGE_VERSION = "1.3.15"
LT_VERSION = "1.1.14"
MAX_FILE = 4 * 1024 * 1024


def password_input():
    raw = sys.stdin.buffer.read(4097)
    if len(raw) > 4096:
        raise ValueError("Password input exceeds 4096 bytes")
    if raw.endswith(b"\n"):
        raw = raw[:-1]
        if raw.endswith(b"\r"):
            raw = raw[:-1]
    password = raw.decode("utf-8")
    if not password or any(c in password for c in "\r\n\0"):
        raise ValueError("Use a nonempty, single-line UTF-8 WebUI password")
    return password


def directory(path, create=False):
    if create:
        try:
            path.mkdir(mode=0o700)
        except FileExistsError:
            pass
    info = path.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o022
    ):
        raise ValueError("Unsafe or differently owned directory: " + str(path))


def write(path, value, config=True, file_version=1):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    with os.fdopen(os.open(str(path), flags, 0o600), "w", encoding="utf-8") as stream:
        if config:
            # Deluge stores a version header followed by a second JSON object.
            stream.write(json.dumps({"file": file_version, "format": 1}) + "\n")
            json.dump(value, stream, ensure_ascii=True, indent=2)
            stream.write("\n")
        else:
            stream.write(value)


def read_file(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError("Unsafe settings file: " + str(path))
        data = stream.read(MAX_FILE + 1)
    if len(data) > MAX_FILE:
        raise ValueError("Settings file exceeds the size limit: " + str(path))
    return data


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate settings key")
        result[key] = value
    return result


def decode_config(data, file_version=1):
    decoder = json.JSONDecoder(object_pairs_hook=unique_pairs)
    text = data.decode("utf-8").lstrip()
    header, offset = decoder.raw_decode(text)
    text = text[offset:].lstrip()
    settings, offset = decoder.raw_decode(text)
    if header != {"file": file_version, "format": 1} or text[offset:].strip():
        raise ValueError("Invalid Deluge settings framing/version")
    if not isinstance(settings, dict):
        raise TypeError("Invalid Deluge settings object")
    return settings


def owner_paths():
    if os.getuid() == 0:
        raise ValueError("Manage settings as the non-root instance owner")
    account = pwd.getpwuid(os.getuid())
    home = Path(account.pw_dir)
    directory(home)
    parent = home / ".config"
    profile = parent / "deluge"
    for path in (parent, profile):
        if path.exists() or path.is_symlink():
            directory(path)
    if profile.exists() and profile.stat().st_mode & 0o077:
        raise ValueError("Deluge profile must be private to its owner")
    return account, home, profile


def preflight(home, profile):
    for name in {*FILES, "hostlist.conf", "hostlist.conf.1.2"}:
        path = profile / name
        if path.exists() or path.is_symlink():
            raise ValueError(
                "Existing Deluge settings are kept; use upgrade or migrate manually"
            )
    for path in (
        home / "deluge",
        *(
            home / "deluge" / name
            for name in ("completed", "download", "torrent", "watch")
        ),
        profile / "plugins",
    ):
        if path.exists() or path.is_symlink():
            directory(path)


def read_settings(profile):
    raw = {name: read_file(profile / name) for name in FILES}
    settings = {
        name: decode_config(
            value,
            3
            if name == "hostlist.conf"
            else 2
            if DELUGE_VERSION == "2.2.0" and name == "web.conf"
            else 1,
        )
        for name, value in raw.items()
        if name != "auth"
    }
    if not raw["auth"] or b"\0" in raw["auth"]:
        raise ValueError("Invalid Deluge credential file")
    core, web = settings["core.conf"], settings["web.conf"]
    ports = core.get("listen_ports")
    if (
        core.get("random_port") is not False
        or not isinstance(ports, list)
        or len(ports) != 2
        or ports[0] != ports[1]
    ):
        raise ValueError("Managed Deluge instances require one fixed incoming port")
    result = {
        "web_port": web.get("port", 8112),
        "rpc_port": core.get("daemon_port", 58846),
        "incoming_port": ports[0],
    }
    for value in result.values():
        if type(value) is not int or not 1024 <= value <= 65535:
            raise ValueError("Invalid recorded Deluge port")
    if len(set(result.values())) != 3:
        raise ValueError("WebUI, RPC and incoming ports must differ")
    blocks = core.get("cache_size", 512)
    ltconfig = settings["ltconfig.conf"]
    if "ltConfig" in core.get("enabled_plugins", []) and ltconfig.get("apply_on_start"):
        blocks = ltconfig.get("settings", {}).get("cache_size", blocks)
    if type(blocks) is not int or not -1 <= blocks <= 67108864:
        raise ValueError("Invalid Deluge cache size")
    result["cache_blocks"] = blocks if LT_VERSION != "2.0.15" else "n/a"
    result["cache_mib"] = (
        "n/a"
        if LT_VERSION == "2.0.15"
        else "auto"
        if blocks == -1
        else (blocks + 63) // 64
    )
    data = core.get("download_location")
    if (
        not isinstance(data, str)
        or not data.startswith("/")
        or any(ord(c) < 32 or ord(c) == 127 for c in data)
    ):
        raise ValueError("Invalid Deluge download path")
    data.encode("utf-8")
    result["data"] = data
    return raw, result


def snapshot(profile):
    raw, _ = read_settings(profile)
    target = Path(tempfile.mkdtemp(prefix=".pre-upgrade-", dir=profile))
    manifest = {}
    for name, data in raw.items():
        with os.fdopen(
            os.open(
                target / name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
            ),
            "wb",
        ) as stream:
            stream.write(data)
        manifest[name] = hashlib.sha256(data).hexdigest()
    write(target / "manifest.json", json.dumps(manifest), config=False)
    print(target)


def restore(profile, source):
    source = Path(source)
    if source.parent != profile or not source.name.startswith(".pre-upgrade-"):
        raise ValueError("Invalid settings snapshot path")
    directory(source)
    manifest = json.loads(
        read_file(source / "manifest.json"), object_pairs_hook=unique_pairs
    )
    if set(manifest) != set(FILES):
        raise ValueError("Invalid settings snapshot manifest")
    raw = {name: read_file(source / name) for name in FILES}
    for name, data in raw.items():
        if hashlib.sha256(data).hexdigest() != manifest[name]:
            raise ValueError("Settings snapshot identity changed")
        target = profile / name
        if target.exists() or target.is_symlink():
            read_file(target)
    for name, data in raw.items():
        descriptor, temporary = tempfile.mkstemp(prefix=".restore-", dir=profile)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(data)
            os.replace(temporary, profile / name)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def purge(profile):
    paths = [
        profile / name
        for name in FILES
        if (profile / name).exists() or (profile / name).is_symlink()
    ]
    for path in paths:
        read_file(path)
    for path in paths:
        path.unlink()
    print(
        "Removed active Deluge settings only; downloads, session data and recovery snapshots are kept"
    )


def create(args, account, home, profile):
    for port in (args.web_port, args.rpc_port, args.incoming_port):
        if port is None or not 1024 <= port <= 65535:
            raise ValueError("Ports must be in 1024..65535")
    if len({args.web_port, args.rpc_port, args.incoming_port}) != 3:
        raise ValueError("WebUI, RPC and incoming ports must differ")
    if args.cache_mib is None or not 1 <= args.cache_mib <= 1048576:
        raise ValueError("Invalid cache size")
    password = password_input()
    preflight(home, profile)
    directory(home / ".config", create=True)
    directory(profile, create=True)
    data = home / "deluge"
    directory(data, create=True)
    for name in ("completed", "download", "torrent", "watch"):
        directory(data / name, create=True)
    directory(profile / "plugins", create=True)
    plugin_name = (
        "ltConfig-0.3.1-py2.7.egg"
        if DELUGE_VERSION == "1.3.15"
        else "ltConfig-2.0.0.egg"
    )
    prefix = (
        "/opt/deluge-1.3.15"
        if DELUGE_VERSION == "1.3.15"
        else "/opt/deluge-2.2.0-lt-" + LT_VERSION
    )
    plugin = profile / "plugins" / plugin_name
    source = Path(prefix) / "plugins" / plugin_name
    if plugin.exists() or plugin.is_symlink():
        if read_file(plugin) != source.read_bytes():
            raise ValueError("Existing ltConfig plugin differs; it was not overwritten")
    else:
        with os.fdopen(
            os.open(
                plugin, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
            ),
            "wb",
        ) as stream:
            stream.write(source.read_bytes())
    rpc_password = secrets.token_hex(32)
    host_id = secrets.token_hex(20)
    salt = secrets.token_hex(20)
    cache_blocks = args.cache_mib * 64  # libtorrent 1.1 uses 16 KiB blocks.
    core = {
        "allow_remote": False,
        "daemon_port": args.rpc_port,
        "download_location": str(data / "download"),
        "move_completed_path": str(data / "completed"),
        "torrentfiles_location": str(data / "torrent"),
        "autoadd_location": str(data / "watch"),
        "plugins_location": str(profile / "plugins"),
        "enabled_plugins": ["ltConfig"],
        "autoadd_enable": True,
        "copy_torrent_file": True,
        "del_copy_torrent_file": False,
        "move_completed": False,
        "cache_size": cache_blocks,
        "cache_expiry": 300,
        "random_port": False,
        "listen_ports": [args.incoming_port, args.incoming_port],
        "listen_interface": "",
        "dht": False,
        "lsd": False,
        "utpex": False,
        "upnp": False,
        "natpmp": False,
        "new_release_check": False,
        "send_info": False,
        "max_active_limit": -1,
        "max_active_downloading": -1,
        "max_active_seeding": -1,
        "max_connections_global": -1,
        "max_connections_per_torrent": -1,
        "max_upload_slots_global": -1,
        "max_upload_slots_per_torrent": -1,
        "max_connections_per_second": -1,
        "max_half_open_connections": -1,
        "max_upload_speed": -1.0,
        "max_download_speed": -1.0,
        "share_ratio_limit": -1.0,
        "seed_time_limit": -1,
        "seed_time_ratio_limit": -1.0,
        "stop_seed_at_ratio": False,
        "remove_seed_at_ratio": False,
        "stop_seed_ratio": 2.0,
        "dont_count_slow_torrents": True,
        "ignore_limits_on_local_network": True,
        "rate_limit_ip_overhead": True,
        "enc_in_policy": 1,
        "enc_out_policy": 1,
        "enc_level": 2,
        "enc_prefer_rc4": False,
        "peer_tos": "0xB8",
        "random_outgoing_ports": True,
        "outgoing_ports": [0, 0],
    }
    ltconfig = {
        "default_cache_min_age": 10,
        "connection_speed": 500,
        "connections_limit": 500000,
        "guided_read_cache": True,
        "max_rejects": 100,
        "inactivity_timeout": 120,
        "active_seeds": -1,
        "max_failcount": 20,
        "allowed_fast_set_size": 0,
        "max_allowed_in_request_queue": 10000,
        "enable_incoming_utp": False,
        "unchoke_slots_limit": -1,
        "peer_timeout": 120,
        "peer_connect_timeout": 30,
        "handshake_timeout": 30,
        "request_timeout": 5,
        "allow_multiple_connections_per_ip": True,
        "use_parole_mode": False,
        "piece_timeout": 5,
        "tick_interval": 100,
        "active_limit": -1,
        "connect_seed_every_n_download": 50,
        "file_pool_size": 5000,
        "cache_expiry": 300,
        "seed_choking_algorithm": 1,
        "max_out_request_queue": 10000,
        "send_buffer_watermark": 10485760,
        "send_buffer_watermark_factor": 200,
        "active_tracker_limit": 1600,
        "send_buffer_low_watermark": 3145728,
        "mixed_mode_algorithm": 0,
        "max_queued_disk_bytes": 262144000,
        "min_reconnect_time": 2,
        "aio_threads": 4,
        "write_cache_line_size": 256,
        "torrent_connect_boost": 100,
        "listen_queue_size": 3000,
        "cache_buffer_chunk_size": 256,
        "suggest_mode": 1,
        "request_queue_time": 5,
        "strict_end_game_mode": False,
        "use_disk_cache_pool": True,
        "predictive_piece_announce": 10,
        "prefer_rc4": False,
        "whole_pieces_threshold": 5,
        "read_cache_line_size": 128,
        "initial_picker_threshold": 10,
        "enable_outgoing_utp": False,
        "cache_size": cache_blocks,
        "low_prio_disk": False,
    }
    if DELUGE_VERSION == "2.2.0":
        # Exclude libtorrent 1.1-only and deprecated cache controls.
        for key in ("autoadd_enable", "autoadd_location", "enc_prefer_rc4"):
            core.pop(key, None)
        core.update(
            max_connections_global=500000,
            max_connections_per_second=500,
            listen_use_sys_port=False,
            listen_reuse_port=False,
        )
        ltconfig = modern_preset(LT_VERSION, cache_blocks)
        if LT_VERSION == "2.0.15":
            core.pop("cache_size", None)
            core.pop("cache_expiry", None)
    write(profile / "core.conf", core)
    write(profile / "ltconfig.conf", {"apply_on_start": True, "settings": ltconfig})
    # Deluge 2 initializes its default host before reading the saved hostlist.
    # Its get_localhost_auth() requires this exact local-only account name.
    rpc_user = account.pw_name if DELUGE_VERSION == "1.3.15" else "localclient"
    write(profile / "auth", rpc_user + ":" + rpc_password + ":10\n", False)
    write(
        profile
        / ("hostlist.conf.1.2" if DELUGE_VERSION == "1.3.15" else "hostlist.conf"),
        {"hosts": [[host_id, "127.0.0.1", args.rpc_port, rpc_user, rpc_password]]},
        file_version=1 if DELUGE_VERSION == "1.3.15" else 3,
    )
    write(
        profile / "web.conf",
        {
            "interface": "0.0.0.0",
            "port": args.web_port,
            "https": False,
            "pwd_salt": salt,
            "pwd_sha1": hashlib.sha1((salt + password).encode("utf-8")).hexdigest(),
            "sessions": {},
            "session_timeout": 3600,
            "default_daemon": host_id,
            "first_login": False,
            "base": "/",
        },
        file_version=1 if DELUGE_VERSION == "1.3.15" else 2,
    )
    print("Created private Deluge configuration: " + str(profile))


def modern_preset(version, cache_blocks):
    # Match the active version-specific qBittorrent libtorrent patches. Explicit
    # runtime overrides cover settings Deluge itself would otherwise replace.
    values = {
        "allow_multiple_connections_per_ip": True,
        "use_parole_mode": False,
        "strict_end_game_mode": False,
        "enable_outgoing_utp": False,
        "enable_incoming_utp": False,
        "smooth_connects": False,
        "enable_upnp": False,
        "enable_natpmp": False,
        "enable_lsd": False,
        "enable_dht": False,
        "piece_timeout": 5,
        "request_timeout": 5,
        "request_queue_time": 5,
        "max_allowed_in_request_queue": 10000,
        "max_out_request_queue": 10000,
        "whole_pieces_threshold": 5,
        "file_pool_size": 5000 if version == "1.2.20" else 100,
        "max_failcount": 20,
        "min_reconnect_time": 2,
        "peer_connect_timeout": 30,
        "connection_speed": 500,
        "inactivity_timeout": 120,
        "initial_picker_threshold": 10,
        "allowed_fast_set_size": 0,
        "suggest_mode": 1,
        "max_queued_disk_bytes": 262144000,
        "handshake_timeout": 30,
        "send_buffer_low_watermark": 3145728,
        "send_buffer_watermark": 10485760,
        "send_buffer_watermark_factor": 200,
        "seed_choking_algorithm": 1,
        "active_downloads": -1,
        "active_seeds": -1,
        "active_limit": -1,
        "active_tracker_limit": 1600,
        "max_rejects": 100,
        "max_peer_recv_buffer_size": 67108864,
        "tick_interval": 100,
        "unchoke_slots_limit": -1,
        "connections_limit": 500000,
        "mixed_mode_algorithm": 0,
        "listen_queue_size": 3000,
        "torrent_connect_boost": 100,
        "checking_mem_usage": 8192,
        "predictive_piece_announce": 10,
        "connect_seed_every_n_download": 50,
        "send_not_sent_low_watermark": 131072,
        "max_concurrent_http_announces": 75,
        "peer_dscp": 184,
    }
    if version == "1.2.20":
        values.update(
            cache_size=cache_blocks,
            cache_size_volatile=128,
            read_cache_line_size=128,
            write_cache_line_size=256,
        )
    else:
        values.update(hashing_threads=2, aio_threads=4)
    return values


def main():
    global FILES, DELUGE_VERSION, LT_VERSION
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "action",
        choices=(
            "create",
            "preflight",
            "read",
            "snapshot",
            "restore",
            "purge",
            "password",
        ),
    )
    parser.add_argument("--web-port", type=int)
    parser.add_argument("--rpc-port", type=int)
    parser.add_argument("--incoming-port", type=int)
    parser.add_argument("--cache-mib", type=int)
    parser.add_argument("--snapshot")
    parser.add_argument(
        "--deluge-version", choices=("1.3.15", "2.2.0"), default="1.3.15"
    )
    parser.add_argument("--libtorrent-version")
    args = parser.parse_args()
    DELUGE_VERSION = args.deluge_version
    LT_VERSION = args.libtorrent_version or (
        "1.1.14" if DELUGE_VERSION == "1.3.15" else "2.0.15"
    )
    if (DELUGE_VERSION, LT_VERSION) not in (
        ("1.3.15", "1.1.14"),
        ("2.2.0", "1.2.20"),
        ("2.2.0", "2.0.15"),
    ):
        raise ValueError("Unsupported Deluge/libtorrent pair")
    if DELUGE_VERSION == "2.2.0":
        FILES = ("core.conf", "web.conf", "hostlist.conf", "auth", "ltconfig.conf")
    if args.action == "password":
        password_input()
        return
    account, home, profile = owner_paths()
    if args.action == "create":
        create(args, account, home, profile)
    elif args.action == "preflight":
        preflight(home, profile)
    elif args.action == "read":
        _, values = read_settings(profile)
        for key, value in values.items():
            print(str(key) + "=" + str(value))
    elif args.action == "snapshot":
        snapshot(profile)
    elif args.action == "restore":
        if not args.snapshot:
            raise ValueError("A settings snapshot is required")
        restore(profile, args.snapshot)
    else:
        purge(profile)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        sys.exit(str(error))
