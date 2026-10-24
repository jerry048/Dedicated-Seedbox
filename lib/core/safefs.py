"""Fail-closed filesystem operations for destructive component maintenance."""

import contextlib
import os
import pwd
import re
import shutil
import stat
import sys


MARKER = ".seedbox-managed"
DOCKER_ENTRIES = {
    "aufs",
    "btrfs",
    "buildkit",
    "containerd",
    "containers",
    "distribution",
    "engine-id",
    "image",
    "network",
    "overlay2",
    "overlayfs",
    "plugins",
    "runtimes",
    "swarm",
    "tmp",
    "trust",
    "vfs",
    "volumes",
    "zfs",
    "fuse-overlayfs",
}


def path_check(path, protect=False):
    if (
        not path.startswith("/")
        or path.startswith("//")
        or os.path.normpath(path) != path
        or any(ord(char) < 32 or ord(char) == 127 for char in path)
    ):
        raise ValueError(f"Unsafe absolute path: {path!r}")
    current = "/"
    for part in path.split("/")[1:]:
        current = os.path.join(current, part)
        try:
            mode = os.lstat(current).st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            raise ValueError(f"Symlinked path refused: {current}")
    if protect:
        protected = {
            "/",
            "/etc",
            "/usr",
            "/usr/local",
            "/usr/src",
            "/var",
            "/var/lib",
            "/var/cache",
            "/var/log",
            "/opt",
            "/opt/seedbox",
            "/srv",
            "/mnt",
            "/media",
            "/tmp",
            "/var/tmp",
            "/run",
            "/home",
            "/root",
            "/boot",
            "/dev",
            "/proc",
            "/sys",
        }
        for home in {entry.pw_dir for entry in pwd.getpwall()} | {
            os.environ.get("HOME", "/")
        }:
            if home.startswith("/"):
                protected.update(
                    os.path.normpath(os.path.join(home, suffix))
                    for suffix in (
                        "",
                        ".config",
                        ".local",
                        ".local/share",
                        ".cache",
                        "Downloads",
                    )
                )
        if path in protected or any(
            path.startswith(root + "/") for root in ("/dev", "/proc", "/sys")
        ):
            raise ValueError(f"Broad/system/home directory refused: {path}")


def mount_check(path):
    # Includes bind mounts, even when they have the same device as their parent.
    with open("/proc/self/mountinfo", encoding="utf-8") as stream:
        for line in stream:
            target = re.sub(
                r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), line.split()[4]
            )
            if target == path or target.startswith(path + "/"):
                raise ValueError(f"Mounted path refused (unmount first): {target}")


def privileged_path(path):
    """Reject replaceable privileged trees, including writable ancestors.

    Root-owned sticky ancestors (e.g. /tmp) may contain a root-owned private
    child; sticky semantics prevent a tenant from replacing that child.
    This is not a defence against another privileged writer.
    """
    path_check(path)
    current = "/"
    for part in [""] + path.split("/")[1:]:
        current = os.path.join(current, part)
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            continue
        sticky_parent = (
            current != path
            and stat.S_ISDIR(info.st_mode)
            and info.st_mode & stat.S_ISVTX
        )
        if info.st_uid != 0 or (info.st_mode & 0o022 and not sticky_parent):
            raise ValueError(f"Untrusted privileged path: {current}")


def owner_check(fd, owner):
    if owner is not None and os.fstat(fd).st_uid != pwd.getpwnam(owner).pw_uid:
        raise ValueError(f"Unexpected directory owner (expected {owner})")


@contextlib.contextmanager
def directory_fd(path):
    # Resolve every ancestor with O_NOFOLLOW, not just the final directory.
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.split("/")[1:]:
            if part:
                next_fd = os.open(
                    part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd
                )
                os.close(fd)
                fd = next_fd
        yield fd
    finally:
        os.close(fd)


def marker_text(path, identity):
    if not re.fullmatch(r"vertex:[a-zA-Z0-9][a-zA-Z0-9_.-]*", identity):
        raise ValueError("Invalid directory ownership identity")
    return f"seedbox-managed-v1\n{identity}\n{path}\n".encode()


def marker_check(fd, path, identity):
    marker_fd = os.open(MARKER, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(marker_fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode) or stream.read(
            4096
        ) != marker_text(path, identity):
            raise ValueError(f"Invalid installer ownership marker: {path}")


def prepare_directory(path):
    # Installation may use a mounted data volume; only purge requires unmounting.
    path_check(path, protect=True)
    privileged_path(path)
    if os.path.exists(path):
        with directory_fd(path):
            pass


def directory_check(path, kind, identity=""):
    path_check(path, protect=True)
    if kind in {"managed", "docker"}:
        privileged_path(path)
    mount_check(path)
    if not os.path.exists(path):
        return
    with directory_fd(path) as fd:
        entries = set(os.listdir(fd))
        if kind == "docker" and identity:
            info = os.fstat(fd)
            if f"{info.st_dev}:{info.st_ino}" != identity:
                raise ValueError(
                    f"Docker data directory identity changed; review manually: {path}"
                )
        if kind == "managed":
            marker_check(fd, path, identity)
        elif kind == "docker":
            # Docker 29's containerd image store keeps image/container data
            # under /var/lib/containerd; /var/lib/docker may legitimately have
            # only engine state, networks and volumes. Reject unknown entries,
            # but do not require the legacy containers/ directory.
            if entries - DOCKER_ENTRIES:
                raise ValueError(
                    f"Unrecognized/shared Docker data directory; review manually: {path}"
                )
            for name in entries:
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                mode = info.st_mode
                if stat.S_ISLNK(mode) or (
                    name in {"containers", "volumes"} and not stat.S_ISDIR(mode)
                ):
                    raise ValueError(
                        f"Unexpected Docker data entry type: {path}/{name}"
                    )
        elif kind != "plain":
            raise ValueError("Invalid directory check")


def remove_directory(path, kind, identity=""):
    directory_check(path, kind, identity)
    if not os.path.exists(path):
        return
    if not shutil.rmtree.avoids_symlink_attacks:
        raise ValueError("Symlink-resistant directory removal is unavailable")
    parent, name = os.path.split(path)
    with directory_fd(parent) as fd, directory_fd(path) as target_fd:
        checked = os.fstat(target_fd)
        directory_check(path, kind, identity)
        current = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if (checked.st_dev, checked.st_ino) != (current.st_dev, current.st_ino):
            raise ValueError("Directory identity changed before deletion")
        # Delete only contents of the opened target, not a replacement name.
        # Retain the ownership marker if deleting any application data fails.
        for child in sorted(os.listdir(target_fd), key=lambda entry: entry == MARKER):
            mode = os.stat(child, dir_fd=target_fd, follow_symlinks=False).st_mode
            if stat.S_ISDIR(mode):
                shutil.rmtree(f"/proc/self/fd/{target_fd}/{child}")
            else:
                os.unlink(child, dir_fd=target_fd)
        current = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if (checked.st_dev, checked.st_ino) != (current.st_dev, current.st_ino):
            raise ValueError("Directory identity changed; final directory kept")
        os.rmdir(name, dir_fd=fd)


def files(path, names, remove=False, owner=None):
    path_check(path)
    if not names or any(
        name
        not in {
            "config.toml",
            "autobrr.db",
            "autobrr.db-shm",
            "autobrr.db-wal",
            "config.yml",
        }
        for name in names
    ):
        raise ValueError("Invalid component file list")
    if not os.path.exists(path):
        return
    with directory_fd(path) as fd:
        owner_check(fd, owner)
        # Check all files before removing any of them. Never delete directories.
        for name in names:
            mount_check(os.path.join(path, name))
            try:
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                mode = info.st_mode
            except FileNotFoundError:
                continue
            if not stat.S_ISREG(mode):
                raise ValueError(f"Non-regular component file refused: {path}/{name}")
            if owner is not None and info.st_uid != pwd.getpwnam(owner).pw_uid:
                raise ValueError(f"Unexpected component file owner: {path}/{name}")
        if remove:
            for name in names:
                try:
                    os.unlink(name, dir_fd=fd)
                except FileNotFoundError:
                    pass


def mark_empty(path, identity):
    text = marker_text(path, identity)
    prepare_directory(path)
    with directory_fd(path) as fd:
        entries = os.listdir(fd)
        if entries:
            if MARKER in entries:
                marker_check(fd, path, identity)
            # Never claim that an existing, populated/shared directory is owned.
            return
        marker_fd = os.open(
            MARKER,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=fd,
        )
        with os.fdopen(marker_fd, "wb") as stream:
            stream.write(text)


def main():
    command, path, *extra = sys.argv[1:]
    owner = None
    if len(extra) >= 2 and extra[0] == "--owner":
        owner, *extra = extra[1:]
    if command in {"check-files", "remove-files"}:
        files(path, extra, command == "remove-files", owner)
    elif command == "mark-empty" and len(extra) == 1:
        mark_empty(path, extra[0])
    elif command == "prepare-dir" and not extra:
        prepare_directory(path)
    elif command in {"check-managed", "remove-managed"} and len(extra) == 1:
        action = remove_directory if command.startswith("remove") else directory_check
        action(path, "managed", extra[0])
    elif command in {"check-docker", "remove-docker"} and len(extra) <= 1:
        action = remove_directory if command.startswith("remove") else directory_check
        action(path, "docker", extra[0] if extra else "")
    elif command == "check-dir" and not extra:
        action = remove_directory if command.startswith("remove") else directory_check
        action(path, "plain")
    else:
        raise ValueError("Invalid filesystem safety operation")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Filesystem operation refused/failed: {error}", file=sys.stderr)
        sys.exit(1)
