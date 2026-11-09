#!/usr/bin/env python3
"""Scoped helper for Agent Memory notes.

This helper is intentionally narrow. It performs local filesystem reads, lists,
validation, exclusive creates, and digest-guarded updates inside an explicit
existing memory root. It does not infer HOME, create a vault, call subprocesses,
use Git, access the network, launch apps, delete, move, restore, or bulk edit.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

ROOT_MAX_BYTES = 4096
CONTENT_MAX_BYTES = 512 * 1024
LIST_MAX_ITEMS = 500
LIST_MAX_EXAMINED = 1000
NOTE_TYPES = {"plan", "handoff", "decision", "research", "review", "context"}
PROJECT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._ -]{0,119}$")
FILE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._ -]{0,119}\.md$")
HEX_RE = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class Identity:
    dev: int
    ino: int
    mode: int
    nlink: int
    size: int

    @classmethod
    def from_stat(cls, st: os.stat_result) -> "Identity":
        return cls(st.st_dev, st.st_ino, st.st_mode, st.st_nlink, st.st_size)

    def same_inode(self, st: os.stat_result) -> bool:
        return self.dev == st.st_dev and self.ino == st.st_ino


@dataclass
class RootHandle:
    fd: int
    path: str
    identity: Identity


class MemoryErrorJson(Exception):
    def __init__(self, status: str, reason: str, *, path: Optional[str] = None):
        super().__init__(reason)
        self.status = status
        self.reason = reason
        self.path = path


def receipt(status: str, *, path: Optional[str] = None, digest: Optional[str] = None, reason: Optional[str] = None, items: Optional[List[str]] = None) -> None:
    payload: Dict[str, Any] = {"status": status}
    if path is not None:
        payload["path"] = path
    if digest is not None:
        payload["digest"] = digest
    if reason is not None:
        payload["reason"] = reason[:500]
    if items is not None:
        payload["items"] = items[:LIST_MAX_ITEMS]
    print(json.dumps(payload, sort_keys=True))


def fail(status: str, reason: str, *, path: Optional[str] = None) -> None:
    raise MemoryErrorJson(status, reason, path=path)


def display_path(root: str, rel: str) -> str:
    return root.rstrip("/") + "/" + rel


def require_os_support() -> None:
    needed_dir_fd = [os.open, os.stat, os.mkdir, os.unlink]
    missing = [func.__name__ for func in needed_dir_fd if func not in os.supports_dir_fd]
    needed_follow = [os.stat]
    missing_follow = [func.__name__ for func in needed_follow if func not in os.supports_follow_symlinks]
    if not hasattr(os, "O_NOFOLLOW"):
        missing.append("O_NOFOLLOW")
    if not hasattr(os, "O_NONBLOCK"):
        missing.append("O_NONBLOCK")
    if os.rename not in os.supports_dir_fd:
        missing.append("rename_dir_fd")
    if os.link not in os.supports_dir_fd or os.link not in os.supports_follow_symlinks:
        missing.append("link_dir_fd_no_follow")
    if missing or missing_follow:
        detail = ", ".join(sorted(set(missing + [name + "_no_follow" for name in missing_follow])))
        fail("blocked", "host lacks required no-follow descriptor-relative filesystem support: " + detail)


def validate_project(project: str) -> str:
    if not PROJECT_RE.fullmatch(project) or "/" in project or project.startswith("."):
        fail("blocked", "invalid project name", path=project)
    return project


def validate_type(note_type: str) -> str:
    if not isinstance(note_type, str) or note_type not in NOTE_TYPES:
        fail("blocked", "invalid memory type", path=str(note_type))
    return note_type


def validate_file_name(file_name: str) -> str:
    if not FILE_RE.fullmatch(file_name) or file_name.startswith(".") or "/" in file_name or ".." in file_name:
        fail("blocked", "invalid note filename", path=file_name)
    return file_name


def split_note_path(path: str) -> Tuple[str, str, str]:
    if path.startswith("/") or "\x00" in path:
        fail("blocked", "absolute or NUL-containing paths are rejected", path=path)
    parts = path.split("/")
    if len(parts) != 3 or any(part in {"", ".", ".."} or part.startswith(".") for part in parts):
        fail("blocked", "path must be PROJECT/TYPE/FILE.md with no hidden or traversal components", path=path)
    return validate_project(parts[0]), validate_type(parts[1]), validate_file_name(parts[2])


def relative_path(project: str, note_type: str, file_name: str) -> str:
    return "/".join([validate_project(project), validate_type(note_type), validate_file_name(file_name)])


def root_components(root: str) -> Tuple[str, ...]:
    if not root or len(root.encode("utf-8")) > ROOT_MAX_BYTES or root.startswith("~"):
        fail("blocked", "--root must be an explicit existing filesystem path")
    if not os.path.isabs(root):
        fail("blocked", "--root must be absolute")
    parts = tuple(part for part in root.split("/") if part)
    if not parts:
        fail("blocked", "memory root must not be the filesystem root", path=root)
    if any(part in {"", ".", ".."} for part in parts):
        fail("blocked", "memory root contains dot or traversal components", path=root)
    return parts


def open_root(root: str) -> RootHandle:
    require_os_support()
    parts = root_components(root)
    fd = os.open("/", os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW)
    current_path = "/"
    try:
        for part in parts:
            try:
                st = os.stat(part, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                fail("blocked", "memory root does not exist", path=root)
            if stat.S_ISLNK(st.st_mode):
                fail("blocked", "memory root contains a symlink component", path=current_path + part)
            if not stat.S_ISDIR(st.st_mode):
                fail("blocked", "memory root component is not a directory", path=current_path + part)
            next_fd = os.open(part, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW, dir_fd=fd)
            next_st = os.fstat(next_fd)
            if not Identity.from_stat(st).same_inode(next_st):
                os.close(next_fd)
                fail("blocked", "memory root component changed while opening", path=current_path + part)
            os.close(fd)
            fd = next_fd
            current_path = current_path.rstrip("/") + "/" + part + "/"
        root_st = os.fstat(fd)
        if not stat.S_ISDIR(root_st.st_mode):
            fail("blocked", "memory root is not a directory", path=root)
        return RootHandle(fd=fd, path=root, identity=Identity.from_stat(root_st))
    except Exception:
        with contextlib.suppress(OSError):
            os.close(fd)
        raise


def close_root(root: RootHandle) -> None:
    os.close(root.fd)


def same_directory_identity(expected: Identity, actual: Identity) -> bool:
    return (
        expected.dev == actual.dev
        and expected.ino == actual.ino
        and stat.S_ISDIR(expected.mode)
        and stat.S_ISDIR(actual.mode)
    )


def recheck_type_chain(root: RootHandle, project: str, note_type: str, pident: Identity, tident: Identity) -> None:
    reopened = open_root(root.path)
    try:
        if not same_directory_identity(root.identity, Identity.from_stat(os.fstat(reopened.fd))):
            fail("blocked", "memory root changed during operation", path=root.path)
        pfd, current_pident = open_child_dir(reopened.fd, project)
        try:
            tfd, current_tident = open_child_dir(pfd, note_type)
        finally:
            os.close(pfd)
        try:
            if not same_directory_identity(pident, current_pident) or not same_directory_identity(tident, current_tident):
                fail("blocked", "project/type directory chain changed during operation", path=f"{root.path}/{project}/{note_type}")
        finally:
            os.close(tfd)
    finally:
        close_root(reopened)


def stat_child(parent_fd: int, name: str) -> os.stat_result:
    return os.stat(name, dir_fd=parent_fd, follow_symlinks=False)


def open_child_dir(parent_fd: int, name: str, *, create: bool = False) -> Tuple[int, Identity]:
    if create:
        try:
            os.mkdir(name, 0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass
        except OSError as exc:
            fail("blocked", f"cannot create directory safely: {exc.strerror}", path=name)
    try:
        st = stat_child(parent_fd, name)
    except OSError as exc:
        fail("blocked", f"cannot stat directory safely: {exc.strerror}", path=name)
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
        fail("blocked", "path component is not a plain directory", path=name)
    fd = os.open(name, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW, dir_fd=parent_fd)
    opened = os.fstat(fd)
    ident = Identity.from_stat(st)
    if not ident.same_inode(opened):
        os.close(fd)
        fail("blocked", "directory changed while opening", path=name)
    return fd, Identity.from_stat(opened)


def open_type_dir(root: RootHandle, project: str, note_type: str, *, create: bool = False) -> Tuple[int, Identity, Identity]:
    pfd, pident = open_child_dir(root.fd, project, create=create)
    try:
        tfd, tident = open_child_dir(pfd, note_type, create=create)
    finally:
        os.close(pfd)
    return tfd, pident, tident


def stat_note_in_dir(dir_fd: int, file_name: str, rel: str) -> Tuple[os.stat_result, Identity]:
    try:
        st = stat_child(dir_fd, file_name)
    except FileNotFoundError:
        raise
    except OSError as exc:
        fail("blocked", f"cannot stat note safely: {exc.strerror}", path=rel)
    if stat.S_ISLNK(st.st_mode):
        fail("blocked", "note target is a symlink", path=rel)
    if not stat.S_ISREG(st.st_mode):
        fail("blocked", "note target is not a regular file", path=rel)
    if st.st_nlink != 1:
        fail("blocked", "hard-linked notes are rejected", path=rel)
    if st.st_size > CONTENT_MAX_BYTES:
        fail("blocked", "note exceeds size limit", path=rel)
    return st, Identity.from_stat(st)


def open_note_from_dir(dir_fd: int, file_name: str, rel: str) -> Tuple[int, Identity]:
    st, ident = stat_note_in_dir(dir_fd, file_name, rel)
    fd = os.open(file_name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dir_fd)
    opened = os.fstat(fd)
    if not ident.same_inode(opened):
        os.close(fd)
        fail("blocked", "note changed while opening", path=rel)
    if not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1 or opened.st_size != st.st_size:
        os.close(fd)
        fail("blocked", "note identity changed while opening", path=rel)
    return fd, Identity.from_stat(opened)


def open_note(root: RootHandle, project: str, note_type: str, file_name: str) -> Tuple[int, Identity]:
    rel = f"{project}/{note_type}/{file_name}"
    tfd, _, _ = open_type_dir(root, project, note_type)
    try:
        return open_note_from_dir(tfd, file_name, rel)
    finally:
        os.close(tfd)


def read_all_fd(fd: int, max_bytes: int = CONTENT_MAX_BYTES) -> bytes:
    chunks: List[bytes] = []
    total = 0
    while True:
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            fail("blocked", "content exceeds size limit")
        chunks.append(chunk)
    return b"".join(chunks)


def write_all_fd(fd: int, data: bytes) -> None:
    view = memoryview(data)
    written = 0
    while written < len(data):
        count = os.write(fd, view[written:])
        if count <= 0:
            fail("blocked", "short write while writing temporary note")
        written += count


def read_seek_fd(fd: int) -> bytes:
    os.lseek(fd, 0, os.SEEK_SET)
    return read_all_fd(fd)


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_utf8_content(data: bytes) -> None:
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        fail("blocked", "note content must be UTF-8")


def read_stdin_content() -> bytes:
    data = sys.stdin.buffer.read(CONTENT_MAX_BYTES + 1)
    if len(data) > CONTENT_MAX_BYTES:
        fail("blocked", "stdin content exceeds size limit")
    return data


@contextlib.contextmanager
def locked_dir(fd: int) -> Iterable[None]:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
    except OSError as exc:
        fail("blocked", f"cannot acquire cooperative directory lock: {exc.strerror}")
    try:
        yield
    finally:
        with contextlib.suppress(OSError):
            fcntl.flock(fd, fcntl.LOCK_UN)


def cleanup_temp(dir_fd: int, tmp_name: str) -> Optional[str]:
    try:
        os.unlink(tmp_name, dir_fd=dir_fd)
        return None
    except FileNotFoundError:
        return None
    except OSError as exc:
        return f"temporary cleanup failed for {tmp_name}: {exc.strerror}"


def create_verified_temp(dir_fd: int, data: bytes) -> str:
    tmp_name = f"__am_tmp_{os.getpid()}_{next(tempfile._get_candidate_names())}.tmp"  # noqa: SLF001
    tmp_fd: Optional[int] = None
    owned = False
    try:
        tmp_fd = os.open(tmp_name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
        owned = True
        write_all_fd(tmp_fd, data)
        os.fsync(tmp_fd)
        actual = read_seek_fd(tmp_fd)
        if actual != data:
            fail("blocked", "temporary content verification failed")
        os.close(tmp_fd)
        tmp_fd = None
        return tmp_name
    except Exception:
        if tmp_fd is not None:
            with contextlib.suppress(OSError):
                os.close(tmp_fd)
        if owned:
            cleanup_reason = cleanup_temp(dir_fd, tmp_name)
            if cleanup_reason:
                fail("blocked", cleanup_reason)
        raise


def verify_after_write(root_path: str, rel: str, expected: bytes) -> None:
    path = display_path(root_path, rel)
    try:
        root = open_root(root_path)
        try:
            project, note_type, file_name = split_note_path(rel)
            fd, _ = open_note(root, project, note_type, file_name)
            try:
                actual = read_all_fd(fd)
            finally:
                os.close(fd)
        finally:
            close_root(root)
    except MemoryErrorJson as exc:
        fail("unverified", "read-back failed after publication: " + exc.reason, path=path)
    except OSError as exc:
        fail("unverified", "read-back failed after publication: " + str(exc), path=path)
    if actual != expected:
        fail("unverified", "read-back content did not match approved bytes", path=path)
    receipt("saved", path=path, digest=digest_bytes(actual))


def ensure_absent(dir_fd: int, file_name: str, rel: str) -> None:
    try:
        stat_child(dir_fd, file_name)
    except FileNotFoundError:
        return
    except OSError as exc:
        fail("blocked", f"cannot check target collision safely: {exc.strerror}", path=rel)
    fail("blocked", "target note already exists", path=rel)


def cmd_read(args: argparse.Namespace) -> None:
    project, note_type, file_name = split_note_path(args.path)
    root = open_root(args.root)
    try:
        fd, ident = open_note(root, project, note_type, file_name)
        try:
            data = read_all_fd(fd)
        finally:
            os.close(fd)
    finally:
        close_root(root)
    sys.stdout.buffer.write(data)
    sys.stderr.write(json.dumps({"status": "ok", "path": display_path(args.root, args.path), "digest": digest_bytes(data), "bytes": ident.size}, sort_keys=True) + "\n")


def cmd_validate(args: argparse.Namespace) -> None:
    project, note_type, file_name = split_note_path(args.path)
    root = open_root(args.root)
    try:
        fd, _ = open_note(root, project, note_type, file_name)
        try:
            data = read_all_fd(fd)
        finally:
            os.close(fd)
    finally:
        close_root(root)
    validate_utf8_content(data)
    receipt("ok", path=display_path(args.root, args.path), digest=digest_bytes(data))


def cmd_list(args: argparse.Namespace) -> None:
    project = validate_project(args.project)
    note_type = validate_type(args.type) if args.type else None
    root = open_root(args.root)
    items: List[str] = []
    omitted = 0
    examined = 0
    try:
        pfd, _ = open_child_dir(root.fd, project)
        try:
            types: Sequence[str] = [note_type] if note_type else tuple(sorted(NOTE_TYPES))
            for typ in types:
                try:
                    typ_stat = stat_child(pfd, typ)
                except FileNotFoundError:
                    continue
                except OSError as exc:
                    fail("blocked", f"cannot inspect type directory safely: {exc.strerror}", path=f"{project}/{typ}")
                if stat.S_ISLNK(typ_stat.st_mode) or not stat.S_ISDIR(typ_stat.st_mode):
                    fail("blocked", "type path is not a plain directory", path=f"{project}/{typ}")
                tfd = os.open(typ, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW, dir_fd=pfd)
                try:
                    opened = os.fstat(tfd)
                    if not Identity.from_stat(typ_stat).same_inode(opened):
                        fail("blocked", "type directory changed while opening", path=f"{project}/{typ}")
                    try:
                        scan = os.scandir(tfd)
                    except TypeError:
                        fail("blocked", "host lacks descriptor-based scandir support", path=f"{project}/{typ}")
                    with scan:
                        for entry in scan:
                            examined += 1
                            if examined > LIST_MAX_EXAMINED or len(items) >= LIST_MAX_ITEMS:
                                omitted += 1
                                break
                            name = entry.name
                            if not FILE_RE.fullmatch(name) or name.startswith("."):
                                continue
                            rel = f"{project}/{typ}/{name}"
                            stat_note_in_dir(tfd, name, rel)
                            items.append(rel)
                    if omitted:
                        break
                finally:
                    os.close(tfd)
        finally:
            os.close(pfd)
    finally:
        close_root(root)
    reason = f"listing truncated after {len(items)} items and {examined} examined entries; omitted at least {omitted}" if omitted else None
    receipt("ok", items=items, reason=reason)


def cmd_create(args: argparse.Namespace) -> None:
    rel = relative_path(args.project, args.type, args.file)
    rooted = display_path(args.root, rel)
    data = read_stdin_content()
    validate_utf8_content(data)
    root = open_root(args.root)
    try:
        tfd, pident, tident = open_type_dir(root, args.project, args.type, create=True)
        try:
            with locked_dir(tfd):
                recheck_type_chain(root, args.project, args.type, pident, tident)
                ensure_absent(tfd, args.file, rooted)
                tmp_name = create_verified_temp(tfd, data)
                try:
                    recheck_type_chain(root, args.project, args.type, pident, tident)
                    ensure_absent(tfd, args.file, rooted)
                    os.link(tmp_name, args.file, src_dir_fd=tfd, dst_dir_fd=tfd, follow_symlinks=False)
                except MemoryErrorJson as exc:
                    cleanup_reason = cleanup_temp(tfd, tmp_name)
                    if cleanup_reason:
                        fail(exc.status, exc.reason + "; " + cleanup_reason, path=exc.path)
                    raise
                except FileExistsError:
                    cleanup_reason = cleanup_temp(tfd, tmp_name)
                    reason = "target note already exists"
                    if cleanup_reason:
                        reason += "; " + cleanup_reason
                    fail("blocked", reason, path=rooted)
                except Exception as exc:
                    cleanup_reason = cleanup_temp(tfd, tmp_name)
                    reason = f"publication outcome uncertain after link attempt: {exc}"
                    if cleanup_reason:
                        reason += "; " + cleanup_reason
                    fail("unverified", reason, path=rooted)
                cleanup_reason = cleanup_temp(tfd, tmp_name)
                if cleanup_reason:
                    fail("unverified", "target was published but " + cleanup_reason, path=rooted)
                try:
                    os.fsync(tfd)
                except OSError as exc:
                    fail("unverified", f"target was published but directory sync failed: {exc.strerror}", path=rooted)
        finally:
            os.close(tfd)
    finally:
        close_root(root)
    verify_after_write(args.root, rel, data)


def same_identity(a: Identity, b: Identity) -> bool:
    return a.dev == b.dev and a.ino == b.ino and a.mode == b.mode and a.nlink == b.nlink and a.size == b.size


def cmd_update(args: argparse.Namespace) -> None:
    if not HEX_RE.fullmatch(args.expected_digest):
        fail("blocked", "expected digest must be lowercase sha256 hex", path=args.path)
    project, note_type, file_name = split_note_path(args.path)
    rooted = display_path(args.root, args.path)
    data = read_stdin_content()
    validate_utf8_content(data)
    root = open_root(args.root)
    try:
        tfd, pident, tident = open_type_dir(root, project, note_type)
        try:
            with locked_dir(tfd):
                recheck_type_chain(root, project, note_type, pident, tident)
                fd, first_ident = open_note_from_dir(tfd, file_name, rooted)
                try:
                    current = read_all_fd(fd)
                finally:
                    os.close(fd)
                current_digest = digest_bytes(current)
                if current_digest != args.expected_digest:
                    fail("blocked", "target digest changed before update", path=rooted)
                tmp_name = create_verified_temp(tfd, data)
                try:
                    recheck_type_chain(root, project, note_type, pident, tident)
                    fd2, second_ident = open_note_from_dir(tfd, file_name, rooted)
                    try:
                        current2 = read_all_fd(fd2)
                    finally:
                        os.close(fd2)
                    if not same_identity(first_ident, second_ident) or digest_bytes(current2) != args.expected_digest:
                        cleanup_reason = cleanup_temp(tfd, tmp_name)
                        tmp_name = ""
                        reason = "target changed immediately before replacement"
                        if cleanup_reason:
                            reason += "; " + cleanup_reason
                        fail("blocked", reason, path=rooted)
                    os.rename(tmp_name, file_name, src_dir_fd=tfd, dst_dir_fd=tfd)
                    tmp_name = ""
                    try:
                        os.fsync(tfd)
                    except OSError as exc:
                        fail("unverified", f"target was replaced but directory sync failed: {exc.strerror}", path=rooted)
                except MemoryErrorJson as exc:
                    if tmp_name:
                        cleanup_reason = cleanup_temp(tfd, tmp_name)
                        if cleanup_reason:
                            fail(exc.status, exc.reason + "; " + cleanup_reason, path=exc.path)
                    raise
                except Exception as exc:
                    cleanup_reason = cleanup_temp(tfd, tmp_name) if tmp_name else None
                    reason = f"replacement failed before confirmed publication: {exc}"
                    if cleanup_reason:
                        reason += "; " + cleanup_reason
                    fail("blocked", reason, path=rooted)
        finally:
            os.close(tfd)
    finally:
        close_root(root)
    verify_after_write(args.root, args.path, data)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Scoped Agent Memory filesystem helper")
    parser.add_argument("--root", required=True, help="absolute path to an existing memory root")
    sub = parser.add_subparsers(dest="command", required=True)

    read_p = sub.add_parser("read")
    read_p.add_argument("--path", required=True)
    read_p.set_defaults(func=cmd_read)

    validate_p = sub.add_parser("validate")
    validate_p.add_argument("--path", required=True)
    validate_p.set_defaults(func=cmd_validate)

    list_p = sub.add_parser("list")
    list_p.add_argument("--project", required=True)
    list_p.add_argument("--type")
    list_p.set_defaults(func=cmd_list)

    create_p = sub.add_parser("create")
    create_p.add_argument("--project", required=True)
    create_p.add_argument("--type", required=True)
    create_p.add_argument("--file", required=True)
    create_p.set_defaults(func=cmd_create)

    update_p = sub.add_parser("update")
    update_p.add_argument("--path", required=True)
    update_p.add_argument("--expected-digest", required=True)
    update_p.set_defaults(func=cmd_update)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if getattr(args, "type", None) is not None:
            validate_type(args.type)
        args.func(args)
        return 0
    except MemoryErrorJson as exc:
        receipt(exc.status, path=exc.path, reason=exc.reason)
        return 2 if exc.status == "blocked" else 3
    except BrokenPipeError:
        return 1
    except OSError as exc:
        receipt("blocked", reason=f"filesystem error: {exc.strerror or exc.__class__.__name__}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
