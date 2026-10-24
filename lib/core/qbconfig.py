#!/usr/bin/env python3
"""Lossless-value QSettings INI migration for seedboxctl qBittorrent upgrades.

Do not use ConfigParser: Qt byte arrays, escapes, case, and percent signs must
remain literal. Unknown keys/comments are retained; only known aliases move.
Alias names follow qBittorrent src/app/upgrade.cpp (4.4.x and 5.3.x).
"""

import argparse
import os
import re
import sys
from pathlib import Path


def version(text):
    match = re.match(r"^v?(\d+)\.(\d+)(?:\.(\d+))?", text)
    if not match:
        raise ValueError("Cannot migrate a config without a known qBittorrent version")
    return tuple(int(part or 0) for part in match.groups())


def key(path):
    section, name = path.split("/", 1)
    return section, name.replace("/", "\\")


# Modern name, legacy Preferences name. Values keep their Qt serialization.
SESSION_ALIASES = """
AddExtensionToIncompleteFiles Downloads/UseIncompleteExtension
AdditionalTrackers Bittorrent/TrackersList
AddTorrentPaused Downloads/StartInPause
AddTrackersEnabled Bittorrent/AddTrackers
AlternativeGlobalDLSpeedLimit Connection/GlobalDLLimitAlt
AlternativeGlobalUPSpeedLimit Connection/GlobalUPLimitAlt
AnnounceIP Connection/InetAddress
AnnounceToAllTrackers Advanced/AnnounceToAllTrackers
AnonymousModeEnabled Advanced/AnonymousMode
BandwidthSchedulerEnabled Scheduler/Enabled
DefaultSavePath Downloads/SavePath
DHTEnabled Bittorrent/DHT
DiskCacheSize Downloads/DiskWriteCacheSize
DiskCacheTTL Downloads/DiskWriteCacheTTL
Encryption Bittorrent/Encryption
FinishedTorrentExportDirectory Downloads/FinishedTorrentExportDir
ForceProxy Connection/ProxyForce
GlobalDLSpeedLimit Connection/GlobalDLLimit
GlobalMaxRatio Bittorrent/MaxRatio
GlobalUPSpeedLimit Connection/GlobalUPLimit
IgnoreLimitsOnLAN Advanced/IgnoreLimitsLAN
IgnoreSlowTorrentsForQueueing Queueing/IgnoreSlowTorrents
IncludeOverheadInLimits Advanced/IncludeOverhead
Interface Connection/Interface
InterfaceAddress Connection/InterfaceAddress
InterfaceName Connection/InterfaceName
IPFilter IPFilter/File
IPFilteringEnabled IPFilter/Enabled
LSDEnabled Bittorrent/LSD
MaxActiveDownloads Queueing/MaxActiveDownloads
MaxActiveTorrents Queueing/MaxActiveTorrents
MaxActiveUploads Queueing/MaxActiveUploads
MaxConnections Bittorrent/MaxConnecs
MaxConnectionsPerTorrent Bittorrent/MaxConnecsPerTorrent
MaxHalfOpenConnections Connection/MaxHalfOpenConnec
MaxRatioAction Bittorrent/MaxRatioAction
MaxUploads Bittorrent/MaxUploads
MaxUploadsPerTorrent Bittorrent/MaxUploadsPerTorrent
OutgoingPortsMax Advanced/OutgoingPortsMax
OutgoingPortsMin Advanced/OutgoingPortsMin
PeXEnabled Bittorrent/PeX
Port Connection/PortRangeMin
Preallocation Downloads/PreAllocation
ProxyPeerConnections Connection/ProxyPeerConnections
QueueingSystemEnabled Queueing/QueueingEnabled
RefreshInterval General/RefreshInterval
SaveResumeDataInterval Downloads/SaveResumeDataInterval
SuperSeedingEnabled Advanced/SuperSeeding
TempPath Downloads/TempPath
TempPathEnabled Downloads/TempPathEnabled
TorrentExportDirectory Downloads/TorrentExportDir
TrackerFilteringEnabled IPFilter/FilterTracker
UseAlternativeGlobalSpeedLimit Connection/alt_speeds_on
UseOSCache Advanced/osCache
UseRandomPort General/UseRandomPort
uTPEnabled Bittorrent/uTP
uTPRateLimited Bittorrent/uTP_rate_limited
"""
ALIASES = [
    (key("BitTorrent/Session/" + modern), key("Preferences/" + old))
    for modern, old in (line.split() for line in SESSION_ALIASES.splitlines() if line)
]
ALIASES += [
    (key(modern), key("Preferences/" + old))
    for modern, old in [
        ("BitTorrent/TrackerEnabled", "Advanced/trackerEnabled"),
        ("Network/PortForwardingEnabled", "Connection/UPnP"),
        ("State/BannedIPs", "IPFilter/BannedIPs"),
        ("Network/Proxy/OnlyForTorrents", "Connection/ProxyOnlyForTorrents"),
        ("Network/Proxy/Type", "Connection/ProxyType"),
    ]
]
ALIASES += [
    (key("Network/Proxy/" + name), key("Preferences/Connection/Proxy/" + name))
    for name in ("Authentication", "IP", "Password", "Port", "Username")
]
MANAGED_TUNING = {
    key("BitTorrent/Session/" + name)
    for name in (
        "AsyncIOThreadsCount",
        "SendBufferLowWatermark",
        "SendBufferWatermark",
        "SendBufferWatermarkFactor",
        "HashingThreadsCount",
        "DiskIOType",
        "ConnectionSpeed",
        "DiskQueueSize",
        "RequestQueueSize",
        "SocketSendBufferSize",
        "SocketReceiveBufferSize",
    )
}


class Document:
    def __init__(self, text):
        self.lines = []
        self.values = {}
        section = "General"
        for line in text.splitlines():
            if line.startswith("\ufeff"):
                line = line[1:]
            stripped = line.strip()
            if stripped.startswith("["):
                if not stripped.endswith("]"):
                    raise ValueError("Malformed qBittorrent config section")
                section = stripped[1:-1]
                self.lines.append(("section", section, None, line))
            elif not stripped or stripped.startswith(("#", ";")):
                self.lines.append(("raw", section, None, line))
            elif "=" in line:
                name, value = line.split("=", 1)
                name = name.strip()
                if not name:
                    raise ValueError("Empty qBittorrent config key")
                self.values[(section, name)] = value.strip()
                self.lines.append(("key", section, name, line))
            else:
                raise ValueError(
                    "Unrecognized qBittorrent config line; refusing to rewrite"
                )

    def render(self, values):
        output, emitted, sections = [], set(), {"General"}

        def flush(section):
            for item, value in values.items():
                if item[0] == section and item not in emitted:
                    output.append(item[1] + "=" + value)
                    emitted.add(item)

        current = "General"
        for kind, section, name, raw in self.lines:
            if kind == "section":
                flush(current)
                output.append(raw)
                current = section
                sections.add(section)
            elif kind == "raw":
                output.append(raw)
            else:
                item = section, name
                if item in values and item not in emitted:
                    original_value = raw.split("=", 1)[1].strip()
                    output.append(
                        raw
                        if original_value == values[item]
                        else name + "=" + values[item]
                    )
                    emitted.add(item)
        flush(current)
        for section, _ in values:
            if section not in sections:
                output.extend(["", "[" + section + "]"])
                sections.add(section)
                flush(section)
        return "\n".join(output) + "\n"


def read_document(path):
    return Document(Path(path).read_text(encoding="utf-8"))


def text_value(raw):
    if len(raw) >= 2 and raw[0] == raw[-1] == '"':
        raw = raw[1:-1]
    escapes = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"'}
    raw = re.sub(
        r'\\(x[0-9a-fA-F]{1,4}|[nrt\\"])',
        lambda m: chr(int(m[1][1:], 16)) if m[1].startswith("x") else escapes[m[1]],
        raw,
    )
    if any(0xD800 <= ord(char) <= 0xDFFF for char in raw):
        raw = raw.encode("utf-16-le", errors="surrogatepass").decode("utf-16-le")
    if raw.startswith("@@"):
        raw = raw[1:]
    return raw


def bool_value(raw):
    value = text_value(raw).lower()
    if value not in ("true", "false", "1", "0"):
        raise ValueError("Cannot safely migrate an invalid boolean setting")
    return value in ("true", "1")


def quote_string(value):
    if value.startswith("@"):
        value = "@" + value
    for old, new in (
        ("\\", "\\\\"),
        ('"', '\\"'),
        ("\n", "\\n"),
        ("\r", "\\r"),
        ("\t", "\\t"),
    ):
        value = value.replace(old, new)
    return '"' + value + '"'


def alias(
    values, modern, old, source_modern, target_modern, to_modern=None, to_old=None
):
    preferred, fallback = (modern, old) if source_modern else (old, modern)
    if preferred not in values and fallback not in values:
        return
    chosen = preferred if preferred in values else fallback
    value = values[chosen]
    if chosen == old and target_modern and to_modern:
        value = to_modern(value)
    elif chosen == modern and not target_modern and to_old:
        value = to_old(value)
    values.pop(old, None)
    values.pop(modern, None)
    values[modern if target_modern else old] = value


def translate(raw, mapping):
    try:
        return mapping[text_value(raw)]
    except KeyError:
        raise ValueError(
            "Cannot safely translate an unsupported enum setting"
        ) from None


def migrate(values, source, target):
    values = dict(values)
    modern_source, modern_target = source >= (4, 4, 0), target >= (4, 4, 0)
    # Normalize legacy names first so subsequent semantic migrations use one key.
    for modern, old in ALIASES:
        alias(values, modern, old, modern_source, True)
    port, random_port = (
        key("BitTorrent/Session/Port"),
        key("BitTorrent/Session/UseRandomPort"),
    )
    if not modern_source and random_port in values and bool_value(values[random_port]):
        values[port] = "0"
    if modern_target:
        values.pop(
            random_port, None
        )  # Modern qBittorrent represents random ports as 0.
    elif port in values:
        values[random_port] = "true" if text_value(values[port]) == "0" else "false"

    proxy = key("Network/Proxy/Type")
    proxy_types = dict(
        zip("012345", ("None", "HTTP", "SOCKS5", "HTTP_PW", "SOCKS5_PW", "SOCKS4"))
    )
    if proxy in values:
        raw = text_value(values[proxy])
        values[proxy] = proxy_types.get(raw, values[proxy])
        if (
            source >= (4, 6, 0)
            and target < (4, 6, 0)
            and text_value(values[proxy]) != "None"
        ):
            raise ValueError(
                "Active proxy profiles cannot be safely downgraded below qBittorrent 4.6; review proxy settings first"
            )
        if not modern_target:
            values[proxy] = translate(
                values[proxy], {v: k for k, v in proxy_types.items()}
            )
        elif source < (4, 6, 0) <= target:
            # Do not rely on Meta/MigrationVersion here: it can be newer than
            # the source binary after a downgrade and otherwise skip this step.
            proxy_type = text_value(values[proxy])
            only_torrents = (
                bool_value(values.get(key("Network/Proxy/OnlyForTorrents"), "false"))
                or proxy_type == "SOCKS4"
            )
            values[key("Network/Proxy/Profiles/BitTorrent")] = "true"
            for profile in ("RSS", "Misc"):
                values[key("Network/Proxy/Profiles/" + profile)] = (
                    "false" if only_torrents else "true"
                )
            values[key("Network/Proxy/AuthEnabled")] = (
                "true" if proxy_type in ("HTTP_PW", "SOCKS5_PW") else "false"
            )
            if proxy_type in ("HTTP_PW", "SOCKS5_PW"):
                values[proxy] = proxy_type[:-3]
            old_lookup = key("BitTorrent/Session/ProxyHostnameLookup")
            if old_lookup in values:
                values[key("Network/Proxy/HostnameLookupEnabled")] = values.pop(
                    old_lookup
                )
            values.pop(key("Network/Proxy/OnlyForTorrents"), None)

    # Other value-type changes relevant to server settings.
    for path, mapping in [
        (
            "Preferences/Scheduler/days",
            dict(
                zip(
                    map(str, range(10)),
                    (
                        "EveryDay",
                        "Weekday",
                        "Weekend",
                        "Monday",
                        "Tuesday",
                        "Wednesday",
                        "Thursday",
                        "Friday",
                        "Saturday",
                        "Sunday",
                    ),
                )
            ),
        ),
        ("Preferences/DynDNS/Service", {"-1": "None", "0": "DynDNS", "1": "NoIP"}),
    ]:
        item = key(path)
        if item in values:
            raw = text_value(values[item])
            if modern_target and raw in mapping:
                values[item] = mapping[raw]
            elif not modern_target and raw in mapping.values():
                values[item] = {v: k for k, v in mapping.items()}[raw]

    layouts = {
        "true": "Original",
        "false": "NoSubfolder",
        "1": "Original",
        "0": "NoSubfolder",
    }
    alias(
        values,
        key("BitTorrent/Session/TorrentContentLayout"),
        key("BitTorrent/Session/CreateTorrentSubfolder"),
        source >= (4, 3, 0),
        target >= (4, 3, 0),
        lambda raw: translate(raw, layouts),
        lambda raw: translate(raw, {"Original": "true", "NoSubfolder": "false"}),
    )

    # These also cover legacy StartInPause/MaxRatioAction via ALIASES.
    alias(
        values,
        key("BitTorrent/Session/AddTorrentStopped"),
        key("BitTorrent/Session/AddTorrentPaused"),
        source >= (5, 0, 0),
        target >= (5, 0, 0),
    )
    actions = dict(
        zip("0123", ("Stop", "Remove", "EnableSuperSeeding", "RemoveWithContent"))
    )
    alias(
        values,
        key("BitTorrent/Session/ShareLimitAction"),
        key("BitTorrent/Session/MaxRatioAction"),
        source >= (5, 0, 0),
        target >= (5, 0, 0),
        lambda raw: translate(raw, actions),
        lambda raw: translate(raw, {v: k for k, v in actions.items()}),
    )
    io_type = key("BitTorrent/Session/DiskIOType")
    if (
        target < (5, 0, 1)
        and text_value(values.get(io_type, "")) == "SimplePreadPwrite"
    ):
        values[io_type] = "Posix"

    web_names = set()
    for section, name in values:
        if section == "WebUI":
            web_names.add(name)
        elif section == "Preferences" and name.startswith("WebUI\\"):
            web_names.add(name[len("WebUI\\") :])
    for name in sorted(web_names):
        # Let qBittorrent export legacy inline TLS material using its native
        # migration before 5.3 moves the resulting CertificatePath/KeyPath.
        if name in (r"HTTPS\Certificate", r"HTTPS\Key"):
            continue
        alias(
            values,
            ("WebUI", name),
            ("Preferences", "WebUI\\" + name),
            source >= (5, 3, 0),
            target >= (5, 3, 0),
        )

    alias(
        values,
        key("Preferences/MailNotification/SMTPEncryptionType"),
        key("Preferences/MailNotification/req_ssl"),
        source >= (5, 3, 0),
        target >= (5, 3, 0),
        lambda raw: "SMTPS" if bool_value(raw) else "None",
        lambda raw: translate(raw, {"SMTPS": "true", "None": "false"}),
    )
    for new, old in (
        ("StoreSearchJobs", "StoreOpenedSearchTabs"),
        ("StoreSearchJobResults", "StoreOpenedSearchTabResults"),
    ):
        alias(
            values,
            key("Search/" + new),
            key("Search/" + old),
            source >= (5, 3, 0),
            target >= (5, 3, 0),
        )

    for old_name, new_name, enabled in [
        ("TorrentExportDirectory", "TorrentBackupDirectory", "TorrentBackupEnabled"),
        (
            "FinishedTorrentExportDirectory",
            "FinishedTorrentBackupDirectory",
            "FinishedTorrentBackupDirectoryEnabled",
        ),
    ]:
        old, new, flag = (
            key("BitTorrent/Session/" + name) for name in (old_name, new_name, enabled)
        )
        if target >= (5, 3, 0) and old in values:
            if source < (5, 3, 0) or new not in values:
                values[new] = values[old]
                values[flag] = "true" if text_value(values[old]) else "false"
            values.pop(old)
        elif target < (5, 3, 0) and new in values:
            values[old] = values[new] if bool_value(values.get(flag, "true")) else ""

    if not modern_target:
        for modern, old in ALIASES:
            alias(values, modern, old, True, False)

    web_section = "WebUI" if target >= (5, 3, 0) else "Preferences"
    web_prefix = "" if web_section == "WebUI" else "WebUI\\"
    https = bool_value(
        values.get((web_section, web_prefix + r"HTTPS\Enabled"), "false")
    )
    if https and source >= (4, 2, 0) > target:
        raise ValueError(
            "HTTPS downgrade below qBittorrent 4.2 requires manual certificate-format review"
        )
    if (
        https
        and source < (4, 2, 0) <= target
        and key("Preferences/WebUI/HTTPS/Certificate") in values
    ):
        raise ValueError(
            "Export the legacy inline HTTPS certificate/key to files before upgrading this config"
        )
    return values


def inspect(document, source):
    # Canonical names make reads independent of the original config family.
    values = migrate(document.values, source, source)
    modern = source >= (4, 4, 0)
    web = source >= (5, 3, 0)
    fields = {
        "webui_enabled": ("WebUI", "Enabled")
        if web
        else ("Preferences", r"WebUI\Enabled"),
        "web_port": ("WebUI", "Port") if web else ("Preferences", r"WebUI\Port"),
        "webui_username": ("WebUI", "Username")
        if web
        else ("Preferences", r"WebUI\Username"),
        "incoming_port": key("BitTorrent/Session/Port")
        if modern
        else key("Preferences/Connection/PortRangeMin"),
        "cache": key("BitTorrent/Session/DiskCacheSize")
        if modern
        else key("Preferences/Downloads/DiskWriteCacheSize"),
        "data": key("BitTorrent/Session/DefaultSavePath")
        if modern
        else key("Preferences/Downloads/SavePath"),
    }
    result = []
    for field, item in fields.items():
        if item not in values:
            continue
        value = text_value(values[item])
        if any(char in value for char in "\r\n\x00"):
            raise ValueError(
                "Config value cannot be safely represented in installer state: " + field
            )
        if field == "webui_enabled":
            value = "1" if bool_value(values[item]) else "0"
        elif field in ("web_port", "incoming_port", "cache"):
            if not re.fullmatch(r"-?\d+", value):
                raise ValueError("Invalid numeric config setting: " + field)
            number = int(value)
            lower, upper = (
                (-1, 2147483647)
                if field == "cache"
                else (0 if field == "incoming_port" else 1, 65535)
            )
            if not lower <= number <= upper:
                raise ValueError("Out-of-range config setting: " + field)
            value = str(number)
        elif field == "data" and (not value.startswith("/") or value.startswith("@")):
            raise ValueError("Default save path is not a supported absolute path")
        elif field == "webui_username" and not value:
            raise ValueError("Empty WebUI username")
        result.append(field + "=" + value)
    return "\n".join(result)


def merge(
    document,
    generated,
    source,
    target,
    overrides,
    retune,
    input_username=None,
    input_data=None,
):
    values = migrate(document.values, source, target)
    template = dict(generated.values)
    modern, web = target >= (4, 4, 0), target >= (5, 3, 0)
    if input_username is not None:
        template[
            ("WebUI", "Username") if web else ("Preferences", r"WebUI\Username")
        ] = quote_string(input_username)
    if input_data is not None:
        template[
            key("BitTorrent/Session/DefaultSavePath")
            if modern
            else key("Preferences/Downloads/SavePath")
        ] = quote_string(input_data.rstrip("/") + "/")
    override_keys = set()
    if retune:
        for item in MANAGED_TUNING:
            values.pop(item, None)
    for field in overrides:
        if field == "web_port":
            override_keys.add(
                ("WebUI", "Port") if web else ("Preferences", r"WebUI\Port")
            )
        elif field == "webui_username":
            override_keys.add(
                ("WebUI", "Username") if web else ("Preferences", r"WebUI\Username")
            )
        elif field == "incoming_port":
            override_keys.add(
                key("BitTorrent/Session/Port")
                if modern
                else key("Preferences/Connection/PortRangeMin")
            )
            if not modern:
                override_keys.add(key("Preferences/General/UseRandomPort"))
        elif field == "cache":
            override_keys.update(
                [
                    key("BitTorrent/Session/DiskCacheSize")
                    if modern
                    else key("Preferences/Downloads/DiskWriteCacheSize"),
                    key("Application/MemoryWorkingSetLimit"),
                ]
            )
    # Retain only the selected password format. A supplied password/hash is the
    # sole authority; stale legacy hashes must not reappear on later migrations.
    for item in list(values):
        section, name = item
        password_names = ("Password", "Password_ha1", "Password_PBKDF2")
        if (section == "WebUI" and name in password_names) or (
            section == "Preferences"
            and name in tuple("WebUI\\" + name for name in password_names)
        ):
            values.pop(item)
    for item, value in template.items():
        # Cache size and process memory limits are different controls. Do not
        # invent a working-set limit from an existing -1/0/positive disk cache.
        if (
            item == key("Application/MemoryWorkingSetLimit")
            and item not in values
            and "cache" not in overrides
        ):
            continue
        if (
            item not in values
            or item in override_keys
            or (retune and item in MANAGED_TUNING)
        ):
            values[item] = value
    # Settings unsupported by an older target stay in the snapshot and as inert
    # keys, rather than being discarded. Warn instead of promising full fidelity.
    if target < source:
        print(
            "Downgrade: known keys were translated; newer-only settings may be ignored by the target. Keep the pre-upgrade snapshot.",
            file=sys.stderr,
        )
    return document.render(values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("inspect", "merge"))
    parser.add_argument("config")
    parser.add_argument("source_version")
    parser.add_argument("--target-version")
    parser.add_argument("--override", action="append", default=[])
    parser.add_argument("--retune", action="store_true")
    args = parser.parse_args()
    document = read_document(args.config)
    source = version(args.source_version)
    if args.operation == "inspect":
        print(inspect(document, source))
    else:
        print(
            merge(
                document,
                Document(sys.stdin.read()),
                source,
                version(args.target_version),
                args.override,
                args.retune,
                os.environ.get("QB_CONFIG_INPUT_USERNAME"),
                os.environ.get("QB_CONFIG_INPUT_DATA"),
            ),
            end="",
        )


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError) as error:
        print("qBittorrent config migration refused: " + str(error), file=sys.stderr)
        sys.exit(2)
