#!/usr/bin/env python3
"""Pack and restore /opt without interpreting or printing its file contents."""

import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile
import tempfile


MAX_BYTES = 1024 * 1024 * 1024


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def mode(name, directory=False):
    path = PurePosixPath(name)
    if directory:
        return 0o700 if ".git" in path.parts else 0o755
    if (".git" in path.parts or path.name in ("environment", "geolite_config")
            or path.name.startswith(".env")
            or path.suffix.lower() in (".env", ".ini", ".json", ".yaml", ".yml", ".toml", ".conf", ".key", ".pem")):
        return 0o600
    return 0o755 if path.suffix.lower() in (".sh", ".py", ".pl") else 0o644


def clean_name(name):
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or ".." in path.parts
            or any(ord(c) < 32 or ord(c) == 127 for c in name)
            or str(path) != name.rstrip("/")):
        raise ValueError("unsafe payload path")
    return str(path)


def pack(source, vault):
    source, vault = Path(source), Path(vault)
    if source.is_symlink() or not source.is_dir():
        raise ValueError("source must be a real directory")
    if vault.resolve().is_relative_to(source.resolve()):
        raise ValueError("output must be outside the source")
    paths = sorted(source.rglob("*"))
    if not paths:
        raise ValueError("empty source")
    total = 0
    for path in paths:
        info = path.lstat()
        clean_name(path.relative_to(source).as_posix())
        if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            raise ValueError("links and special files are not supported")
        total += info.st_size if stat.S_ISREG(info.st_mode) else 0
    if total > MAX_BYTES:
        raise ValueError("uncompressed payload exceeds 1 GiB")
    with tarfile.open(vault / "payload.tar.gz", "w:gz", dereference=True) as archive:
        for path in paths:
            name = path.relative_to(source).as_posix()
            member = archive.gettarinfo(str(path), arcname=name)
            member.uid = member.gid = 0
            member.uname = member.gname = "root"
            member.mode = mode(name, member.isdir())
            if member.isfile():
                with path.open("rb") as stream:
                    archive.addfile(member, stream)
            else:
                archive.addfile(member)
    (vault / "payload.sha256").write_text(digest(vault / "payload.tar.gz") + "  payload.tar.gz\n")
    print(f"Packed {sum(p.is_file() for p in paths)} files; original bytes: {total}")


def verify(vault):
    vault = Path(vault)
    for name in ("payload.tar.gz", "payload.sha256"):
        p = vault / name
        if p.is_symlink() or not p.is_file():
            raise ValueError("missing payload file")
    if (vault / "payload.sha256").stat().st_size != 81:
        raise ValueError("invalid payload checksum format")
    checksum = (vault / "payload.sha256").read_text()
    if not re.fullmatch(r"[a-f0-9]{64}  payload\.tar\.gz\n", checksum):
        raise ValueError("invalid payload checksum format")
    if digest(vault / "payload.tar.gz") != checksum[:64]:
        raise ValueError("payload checksum mismatch")


def checked_members(archive):
    members = {}
    total = 0
    for member in archive:
        name = clean_name(member.name)
        if name in members or not (member.isfile() or member.isdir()) or member.issparse():
            raise ValueError("duplicate, link or special payload entry")
        total += member.size
        if total > MAX_BYTES or len(members) >= 100000:
            raise ValueError("payload exceeds extraction limits")
        members[name] = member
    if not members:
        raise ValueError("empty payload")
    for name in members:
        for parent in PurePosixPath(name).parents:
            if str(parent) != "." and (str(parent) not in members or not members[str(parent)].isdir()):
                raise ValueError("missing or invalid parent directory")
    return members


def check_target(target, members):
    target = Path(target).absolute()
    for p in (target, *target.parents):
        if p.is_symlink() or (p.exists() and not p.is_dir()):
            raise ValueError("destination parent is not a real directory")
    for name, member in members.items():
        p = target / name
        if p.is_symlink():
            raise ValueError("destination contains a symbolic link")
        if p.exists():
            info = p.lstat()
            if member.isdir() != stat.S_ISDIR(info.st_mode):
                raise ValueError("destination file type conflicts with payload")
            if member.isfile() and (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1):
                raise ValueError("destination contains a hard link or special file")
    return target


def restore(vault, target, backup_root):
    verify(vault)
    with tarfile.open(Path(vault) / "payload.tar.gz", "r:gz") as archive:
        members = checked_members(archive)
        target = check_target(target, members)
        # Verify and decompress everything before modifying the destination.
        with tempfile.TemporaryDirectory(prefix="opt-restore-") as tmp:
            staging = Path(tmp) / "files"
            staging.mkdir(mode=0o700)
            for name, member in sorted(members.items(), key=lambda item: (len(PurePosixPath(item[0]).parts), item[0])):
                dest = staging / name
                if member.isdir():
                    dest.mkdir()
                else:
                    with archive.extractfile(member) as src, dest.open("xb") as dst:
                        shutil.copyfileobj(src, dst)
                    if dest.stat().st_size != member.size:
                        raise ValueError("incomplete payload file")
                dest.chmod(mode(name, member.isdir()))
            target = check_target(target, members)
            backup_root = Path(backup_root)
            for p in (backup_root, *backup_root.absolute().parents):
                if p.is_symlink():
                    raise ValueError("backup directory contains a symbolic link")
            backup_root.mkdir(mode=0o700, parents=True, exist_ok=True)
            backup = Path(tempfile.mkdtemp(prefix="opt-before-", dir=backup_root))
            existing = [name for name in members if (target / name).exists()]
            with tarfile.open(backup / "previous.tar.gz", "w:gz", dereference=False) as old:
                for name in existing:
                    old.add(target / name, arcname=name, recursive=False)
            (backup / "previous.tar.gz").chmod(0o600)
            # The rollback list contains names only, never file contents.
            (backup / "new-paths.txt").write_text("".join(name + "\n" for name in members if name not in existing))
            changed = []
            created_dirs = []
            changed_dirs = []
            try:
                target.mkdir(parents=True, exist_ok=True)
                for name, member in sorted(members.items(), key=lambda item: (len(PurePosixPath(item[0]).parts), item[0])):
                    dest = target / name
                    if member.isdir():
                        if not dest.exists():
                            dest.mkdir(mode=mode(name, True))
                            created_dirs.append(dest)
                        else:
                            changed_dirs.append(name)
                        if os.geteuid() == 0:
                            os.chown(dest, 0, 0)
                        dest.chmod(mode(name, True))
                        continue
                    fd, temporary = tempfile.mkstemp(prefix=".opt-vault-", dir=dest.parent)
                    try:
                        with os.fdopen(fd, "wb") as stream, (staging / name).open("rb") as src:
                            shutil.copyfileobj(src, stream)
                            stream.flush()
                            os.fsync(stream.fileno())
                        os.chmod(temporary, mode(name))
                        if os.geteuid() == 0:
                            os.chown(temporary, 0, 0)
                        os.replace(temporary, dest)
                        changed.append(name)
                    finally:
                        if os.path.exists(temporary):
                            os.unlink(temporary)
                for name, member in members.items():
                    if member.isfile() and digest(target / name) != digest(staging / name):
                        raise ValueError("restored file verification failed")
            except BaseException:
                with tarfile.open(backup / "previous.tar.gz", "r:gz") as old:
                    for name in reversed(changed):
                        dest = target / name
                        if name in existing:
                            member = old.getmember(name)
                            dest.unlink()
                            with old.extractfile(member) as src, dest.open("xb") as dst:
                                shutil.copyfileobj(src, dst)
                            os.chmod(dest, member.mode)
                            if os.geteuid() == 0:
                                os.chown(dest, member.uid, member.gid)
                            os.utime(dest, (member.mtime, member.mtime))
                        else:
                            dest.unlink()
                for dest in reversed(created_dirs):
                    dest.rmdir()
                with tarfile.open(backup / "previous.tar.gz", "r:gz") as old:
                    for name in reversed(changed_dirs):
                        member = old.getmember(name)
                        dest = target / name
                        if os.geteuid() == 0:
                            os.chown(dest, member.uid, member.gid)
                        os.chmod(dest, member.mode)
                        os.utime(dest, (member.mtime, member.mtime))
                raise
            print(f"Restored {sum(m.isfile() for m in members.values())} files; backup: {backup}")


def main():
    command, *args = sys.argv[1:]
    {"pack": pack, "verify": verify, "restore": restore}[command](*args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError):
        # Exceptions from parsers or the OS must not echo secret data.
        print("Opt payload operation failed; check paths, checksum, free space and permissions", file=sys.stderr)
        sys.exit(1)
