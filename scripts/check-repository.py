#!/usr/bin/env python3
"""Check only Git-tracked source files or an explicit source export."""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


SCRIPT_ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {
    ".c", ".cc", ".conf", ".cpp", ".h", ".html", ".js", ".json", ".kt",
    ".m", ".md", ".plist", ".py", ".rb", ".sh", ".swift", ".toml", ".txt",
    ".xml", ".yml", ".yaml",
}
MEDIA_SUFFIXES = {
    ".aac", ".avif", ".gif", ".jpeg", ".jpg", ".m4a", ".m4v", ".mov",
    ".mp3", ".mp4", ".ogg", ".otf", ".png", ".svg", ".ttf", ".wav",
    ".webp", ".woff", ".woff2",
}
PRIVATE_COMPONENTS = {
    ".local", ".private-audit", "device-state", "installers", "known_hosts",
    "private", "ssh-material",
}
SENSITIVE_SUFFIXES = {
    ".app", ".dSYM", ".ipa", ".mobileprovision", ".p12", ".p8", ".pem",
    ".provisionprofile",
}
SECRET_PATTERNS = [
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bsk-(?:proj|live)-[A-Za-z0-9_-]{20,}\b"),
]
LOCAL_PATH_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_./-])/(?:" + "Users" + r"|home)/[^/\s\"']+(?:/|$)"
)
MARKDOWN_LINK = re.compile(
    r"!?\[[^\]]*\]\(\s*(?:<(?P<angle>[^>\n]+)>|(?P<bare>(?:\\.|[^()\s]|\([^()\n]*\))+))"
)
class LinkCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.targets: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        wanted = {"a": {"href"}, "img": {"src"}, "source": {"src"},
                  "video": {"src", "poster"}, "audio": {"src"}, "iframe": {"src"}}
        keys = wanted.get(tag.lower(), set())
        for key, value in attrs:
            if key in keys and value:
                self.targets.append(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=Path,
        help="explicit source-export directory containing OPEN_SOURCE_EXPORT_REPORT.json",
    )
    return parser.parse_args()


def safe_relative_path(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if path.is_absolute() or not value or ".." in path.parts or "\\" in value:
        raise ValueError(f"unsafe path in export report: {value!r}")
    return path


def tracked_paths(root: Path) -> list[PurePosixPath]:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--cached", "-z"],
            check=True, capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError("default mode requires a Git checkout; pass --root for an explicit source export") from exc
    raw_paths = [item for item in result.stdout.split(b"\0") if item]
    return [safe_relative_path(item.decode("utf-8")) for item in raw_paths]


def export_paths(root: Path) -> list[PurePosixPath]:
    report_path = root / "OPEN_SOURCE_EXPORT_REPORT.json"
    if report_path.is_symlink() or not report_path.is_file():
        raise RuntimeError("--root must point to an export containing OPEN_SOURCE_EXPORT_REPORT.json")
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
        files = report["included_files"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        raise RuntimeError("export report is unreadable or has no included_files list") from exc
    if not isinstance(files, list) or any(not isinstance(item, str) for item in files):
        raise RuntimeError("export report included_files must be a list of relative paths")
    paths = [safe_relative_path(item) for item in files]
    paths.append(PurePosixPath("OPEN_SOURCE_EXPORT_REPORT.json"))
    if len(paths) != len(set(paths)):
        raise RuntimeError("export report includes a duplicate path")

    actual: set[PurePosixPath] = set()
    for current, directories, filenames in os.walk(root, followlinks=False):
        base = Path(current)
        for directory in list(directories):
            entry = base / directory
            if entry.is_symlink():
                raise RuntimeError(f"source export contains a symlink: {entry.relative_to(root)}")
        for filename in filenames:
            entry = base / filename
            if entry.is_symlink():
                raise RuntimeError(f"source export contains a symlink: {entry.relative_to(root)}")
            actual.add(PurePosixPath(entry.relative_to(root).as_posix()))
    expected = set(paths)
    unexpected = sorted(actual - expected)
    missing = sorted(expected - actual)
    if unexpected:
        raise RuntimeError("unlisted files in source export: " + ", ".join(map(str, unexpected[:8])))
    if missing:
        raise RuntimeError("listed export files are missing: " + ", ".join(map(str, missing[:8])))
    return paths


def reject_private_paths(root: Path, paths: list[PurePosixPath], errors: list[str]) -> None:
    for relative in paths:
        lowered_parts = {part.lower() for part in relative.parts}
        if lowered_parts & PRIVATE_COMPONENTS:
            errors.append(f"private or workstation path is included: {relative}")
        if any(part == ".env" or part.startswith(".env.") for part in lowered_parts):
            errors.append(f"environment file is included: {relative}")
        if any(Path(part).suffix in SENSITIVE_SUFFIXES for part in relative.parts) or relative.name == ".DS_Store":
            errors.append(f"private or generated artifact is included: {relative}")
        media_name = relative.name.lower()
        is_gta_media = any(marker in media_name for marker in ("gta6", "gta-vi", "grand-theft-auto", "rockstar"))
        if is_gta_media and relative.suffix.lower() in MEDIA_SUFFIXES | {".zip", ".7z", ".rar"}:
            errors.append(f"Rockstar media payload must stay outside the source tree: {relative}")


def readable_text(path: Path) -> str | None:
    if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {"LICENSE", "NOTICE"}:
        return None
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if len(data) > 2_000_000 or b"\0" in data[:4096]:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def check_sensitive_content(root: Path, paths: list[PurePosixPath], errors: list[str]) -> None:
    for relative in paths:
        content = readable_text(root / Path(relative.as_posix()))
        if content is None:
            continue
        for pattern in SECRET_PATTERNS:
            if pattern.search(content):
                errors.append(f"possible credential or private key in {relative}")
                break
        if LOCAL_PATH_PATTERN.search(content):
            errors.append(f"workstation home path appears in {relative}")


def markdown_anchors(content: str) -> set[str]:
    anchors = {match.group(1) for match in re.finditer(r"\bid=[\"']([^\"']+)[\"']", content)}
    anchors.update(match.group(1) for match in re.finditer(r"\bname=[\"']([^\"']+)[\"']", content))
    seen: dict[str, int] = {}
    for heading in re.finditer(r"^#{1,6}\s+(.+?)\s*#*\s*$", content, re.M):
        value = re.sub(r"`([^`]*)`", r"\1", heading.group(1))
        value = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", value)
        slug = re.sub(r"[^\w\- ]", "", value.lower()).strip().replace(" ", "-")
        ordinal = seen.get(slug, 0)
        anchors.add(slug if ordinal == 0 else f"{slug}-{ordinal}")
        seen[slug] = ordinal + 1
    return anchors


def clean_markdown(content: str) -> str:
    return re.sub(r"```.*?```|~~~.*?~~~|`[^`]*`", "", content, flags=re.S)


def link_targets(path: Path, content: str) -> list[str]:
    if path.suffix.lower() == ".md":
        stripped = clean_markdown(content)
        targets = [match.group("angle") or match.group("bare") for match in MARKDOWN_LINK.finditer(stripped)]
    else:
        parser = LinkCollector()
        parser.feed(content)
        targets = parser.targets
    if path.suffix.lower() in {".md", ".html", ".htm"}:
        parser = LinkCollector()
        parser.feed(clean_markdown(content) if path.suffix.lower() == ".md" else content)
        targets.extend(parser.targets)
    return targets


def check_target(root: Path, source: Path, target: str, anchors_cache: dict[Path, set[str]], errors: list[str]) -> None:
    target = target.strip().replace("\\ ", " ")
    if not target or target.startswith("//"):
        return
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or target.startswith("#"):
        if target.startswith("#"):
            target_path = source
            fragment = unquote(target[1:])
        else:
            return
    else:
        path_text = unquote(parsed.path)
        if not path_text:
            target_path = source
        else:
            target_path = (source.parent / path_text).resolve()
            try:
                target_path.relative_to(root)
            except ValueError:
                errors.append(f"local link escapes checked tree in {source.relative_to(root)}: {target}")
                return
        fragment = unquote(parsed.fragment)
    if not target_path.exists():
        errors.append(f"broken local link in {source.relative_to(root)}: {target}")
        return
    if fragment and target_path.is_file() and target_path.suffix.lower() in {".md", ".html", ".htm"}:
        anchors = anchors_cache.get(target_path)
        if anchors is None:
            content = readable_text(target_path) or ""
            anchors = markdown_anchors(content)
            anchors_cache[target_path] = anchors
        if fragment not in anchors:
            errors.append(f"missing local anchor in {source.relative_to(root)}: {target}")


def check_links(root: Path, paths: list[PurePosixPath], errors: list[str]) -> None:
    anchors_cache: dict[Path, set[str]] = {}
    for relative in paths:
        source = root / Path(relative.as_posix())
        content = readable_text(source)
        if content is None or source.suffix.lower() not in {".md", ".html", ".htm"}:
            continue
        for target in link_targets(source, content):
            check_target(root, source, target, anchors_cache, errors)


def check_license_and_attribution(root: Path, paths: list[PurePosixPath], errors: list[str]) -> None:
    included = {path.as_posix() for path in paths}
    required = {"LICENSE", "NOTICE", "THIRD_PARTY.md"}
    missing = sorted(required - included)
    if missing:
        errors.append("required license/attribution files are absent: " + ", ".join(missing))
        return
    license_text = (root / "LICENSE").read_text(encoding="utf-8", errors="replace")
    notice_text = (root / "NOTICE").read_text(encoding="utf-8", errors="replace")
    third_party_text = (root / "THIRD_PARTY.md").read_text(encoding="utf-8", errors="replace")
    if "MIT License" not in license_text or "Wizard-authored code" not in third_party_text:
        errors.append("license boundary must identify MIT as applying to Wizard-authored code")
    if "Rockstar" not in notice_text or "Rockstar" not in third_party_text:
        errors.append("Rockstar attribution must remain separate in NOTICE and THIRD_PARTY.md")
    if re.search(r"Rockstar.{0,120}(?:licensed|licence|license) under MIT", notice_text, re.I | re.S):
        errors.append("NOTICE must not apply the MIT license to Rockstar media")

    manifest_path = "assets/media/MANIFEST.json"
    attribution_path = "assets/media/ATTRIBUTION.md"
    if manifest_path in included or attribution_path in included:
        if manifest_path not in included or attribution_path not in included:
            errors.append("media release assets require both assets/media/MANIFEST.json and ATTRIBUTION.md")
            return
        try:
            manifest = json.loads((root / manifest_path).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"media manifest is not valid JSON: {exc}")
            return
        attribution = (root / attribution_path).read_text(encoding="utf-8", errors="replace").lower()
        if not isinstance(manifest, dict):
            errors.append("media manifest must be a JSON object")
        elif manifest.get("schema_version") != 1:
            errors.append("media manifest schema_version must be 1")
        if ("rockstar" not in attribution or "mit" not in attribution or
                not any(phrase in attribution for phrase in ("not covered", "not licensed", "excluded from"))):
            errors.append("media attribution must state Rockstar attribution and its separate MIT boundary")
        copyright_record = manifest.get("copyright") if isinstance(manifest, dict) else None
        if not isinstance(copyright_record, dict):
            errors.append("media manifest must include a separate copyright record")
        else:
            owner = str(copyright_record.get("owner", "")).lower()
            scope = str(copyright_record.get("scope", "")).lower()
            if "rockstar" not in owner or "not covered" not in scope or "mit" not in scope:
                errors.append("media manifest copyright scope must identify Rockstar and exclude the Wizard MIT license")
        release_tag = manifest.get("release_tag", "") if isinstance(manifest, dict) else ""
        if not isinstance(release_tag, str) or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", release_tag):
            errors.append("media manifest must identify a versioned GitHub release tag")
        entries = manifest.get("release_assets") if isinstance(manifest, dict) else None
        if not isinstance(entries, list) or not entries:
            errors.append("media manifest must list release packs under a non-empty `release_assets` array")
        else:
            seen_ids: set[str] = set()
            for index, item in enumerate(entries):
                if not isinstance(item, dict):
                    errors.append(f"media release asset {index + 1} must be an object")
                    continue
                asset_id = item.get("id")
                asset_name = item.get("name")
                url = item.get("download_url")
                byte_count = item.get("bytes")
                digest = item.get("sha256")
                file_count = item.get("files")
                if not isinstance(asset_id, str) or not asset_id.strip() or asset_id in seen_ids:
                    errors.append(f"media release asset {index + 1} needs a unique id")
                elif isinstance(asset_id, str):
                    seen_ids.add(asset_id)
                if not isinstance(asset_name, str) or not asset_name.strip() or Path(asset_name).name != asset_name:
                    errors.append(f"media release asset {index + 1} needs a plain filename")
                if (not isinstance(release_tag, str) or not isinstance(url, str) or
                        not re.fullmatch(r"https://github\.com/rexchen1803/wizard/releases/download/" + re.escape(release_tag) + r"/[^/]+", url)):
                    errors.append(f"media release asset {index + 1} needs a matching project release URL")
                elif isinstance(asset_name, str) and url.rsplit("/", 1)[-1] != asset_name:
                    errors.append(f"media release asset {index + 1} URL filename does not match its name")
                if not isinstance(byte_count, int) or isinstance(byte_count, bool) or byte_count <= 0:
                    errors.append(f"media release asset {index + 1} needs a positive byte size")
                if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                    errors.append(f"media release asset {index + 1} needs a lowercase SHA-256")
                if not isinstance(file_count, int) or isinstance(file_count, bool) or file_count <= 0:
                    errors.append(f"media release asset {index + 1} needs a positive file count")
                for count_key in ("image_count", "video_count", "subtitle_count"):
                    count = item.get(count_key)
                    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
                        errors.append(f"media release asset {index + 1} needs a non-negative {count_key}")


def main() -> int:
    args = parse_args()
    root = (args.root or SCRIPT_ROOT).resolve()
    if not root.is_dir():
        print(f"ERROR: not a directory: {root}", file=sys.stderr)
        return 2
    try:
        paths = export_paths(root) if args.root else tracked_paths(root)
    except (RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    errors: list[str] = []
    for relative in paths:
        entry = root / Path(relative.as_posix())
        if entry.is_symlink():
            errors.append(f"tracked source is a symlink: {relative}")
        elif not entry.is_file():
            errors.append(f"tracked source is missing or not a regular file: {relative}")
    reject_private_paths(root, paths, errors)
    check_sensitive_content(root, paths, errors)
    check_links(root, paths, errors)
    check_license_and_attribution(root, paths, errors)
    if errors:
        print("Repository checks failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"Repository checks passed ({len(paths)} tracked/export files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
