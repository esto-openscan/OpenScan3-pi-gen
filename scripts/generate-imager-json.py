#!/usr/bin/env python3
"""Generate Raspberry Pi Imager repository JSON entries for OpenScan builds."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


DEPLOY_EXTENSIONS: tuple[str, ...] = (".img", ".img.xz", ".img.gz", ".img.zip", ".zip")
BUILD_ID_PATTERN = re.compile(r"^(?:image_)?(?P<date>\d{4}-\d{2}-\d{2})-(?P<name>.+)$")


@dataclass
class Variant:
    suffix: str
    name: str
    description: str
    devices: List[str]
    capabilities: List[str]
    init_format: str
    icon: Optional[str]

    def matches(self, build_id: str) -> bool:
        suffix_pattern = rf"_{re.escape(self.suffix)}(?:-[\w.-]+)*$"
        return re.search(suffix_pattern, build_id) is not None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variants",
        default="imager/os-variants.json",
        help="Path to variant metadata (default: %(default)s)",
    )
    parser.add_argument(
        "--deploy-dir",
        default="pi-gen/deploy",
        help="Directory with pi-gen build artifacts (default: %(default)s)",
    )
    parser.add_argument(
        "--output",
        default="imager/repo.json",
        help="Output path for Raspberry Pi Imager repository JSON (default: %(default)s)",
    )
    parser.add_argument(
        "--url-prefix",
        default="",
        help="Optional HTTP(S) base URL where artifacts will be hosted. The filename is appended to this prefix.",
    )
    parser.add_argument(
        "--release-date",
        default=None,
        help="ISO date (YYYY-MM-DD) to force as release_date for every entry.",
    )
    return parser.parse_args()


def load_variants(path: Path) -> tuple[Dict[str, Any], Optional[Dict[str, Any]], List[Variant]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    variants = [
        Variant(
            suffix=entry["suffix"],
            name=entry["name"],
            description=entry["description"],
            devices=entry["devices"],
            capabilities=entry.get("capabilities", []),
            init_format=entry.get("init_format", "cloudinit-rpi"),
            icon=entry.get("icon"),
        )
        for entry in data["variants"]
    ]
    category = data.get("category")
    return data["imager"], category, variants


def iter_artifacts(deploy_dir: Path) -> Iterable[Path]:
    for ext in DEPLOY_EXTENSIONS:
        yield from deploy_dir.glob(f"*{ext}")


def canonical_build_id(artifact: Path) -> str:
    name = artifact.name
    for suffix in (".xz", ".gz", ".zip"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
    if name.endswith(".img"):
        name = name[:-4]
    return name


def extract_release_date(build_id: str) -> str:
    match = BUILD_ID_PATTERN.match(build_id)
    if not match:
        raise ValueError(f"Cannot parse release date from '{build_id}'")
    return match.group("date")


def sha256sum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_os_entry(
    variant: Variant,
    artifact: Path,
    release_date: str,
    url_prefix: str,
) -> Dict[str, Any]:
    download_url = f"{url_prefix.rstrip('/')}/{artifact.name}" if url_prefix else artifact.name
    entry: Dict[str, Any] = {
        "name": variant.name,
        "description": variant.description,
        "url": download_url,
        "release_date": release_date,
        "devices": variant.devices,
        "capabilities": variant.capabilities,
        "init_format": variant.init_format,
        "image_download_size": artifact.stat().st_size,
        "image_download_sha256": sha256sum(artifact),
    }
    if variant.icon:
        entry["icon"] = variant.icon
    return entry


def infer_release_date(build_id: str, artifact: Path) -> str:
    try:
        return extract_release_date(build_id)
    except ValueError:
        timestamp = datetime.fromtimestamp(artifact.stat().st_mtime, tz=timezone.utc)
        return timestamp.date().isoformat()


def select_latest_artifact(variant: Variant, artifacts: List[Path]) -> tuple[Path, str]:
    matching: list[tuple[str, Path]] = []
    for path in artifacts:
        build_id = canonical_build_id(path)
        if variant.matches(build_id):
            release_date = infer_release_date(build_id, path)
            matching.append((release_date, path))
    if not matching:
        raise FileNotFoundError(f"No artifact found for variant '{variant.suffix}'")
    matching.sort(key=lambda item: item[0])
    release_date, artifact = matching[-1]
    return artifact, release_date


def assemble_os_list(
    category: Optional[Dict[str, Any]],
    os_entries: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    if category:
        category_entry: Dict[str, Any] = {
            "name": category["name"],
            "subitems": os_entries,
        }
        if description := category.get("description"):
            category_entry["description"] = description
        if icon := category.get("icon"):
            category_entry["icon"] = icon
        return [category_entry]
    return os_entries


def main() -> None:
    args = parse_args()
    variants_path = Path(args.variants)
    deploy_dir = Path(args.deploy_dir)
    output_path = Path(args.output)
    release_date_override: Optional[str] = args.release_date

    imager_meta, category_meta, variants = load_variants(variants_path)
    artifacts = list(iter_artifacts(deploy_dir))

    os_entries: List[Dict[str, Any]] = []
    for variant in variants:
        artifact, release_date = select_latest_artifact(variant, artifacts)
        if release_date_override:
            release_date = release_date_override
        os_entry = build_os_entry(variant, artifact, release_date, args.url_prefix)
        os_entries.append(os_entry)

    repo = {
        "imager": imager_meta,
        "os_list": assemble_os_list(category_meta, os_entries),
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(repo, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote Raspberry Pi Imager repository JSON to {output_path}")


if __name__ == "__main__":
    main()
