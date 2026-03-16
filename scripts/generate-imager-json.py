#!/usr/bin/env python3
"""Generate Raspberry Pi Imager repository JSON entries for OpenScan builds."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import os
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


DEPLOY_EXTENSIONS: tuple[str, ...] = (".img", ".img.xz", ".img.gz", ".img.zip", ".zip")
BUILD_ID_PATTERN = re.compile(r"^(?:image_)?(?P<date>\d{4}-\d{2}-\d{2})-(?P<name>.+)$")
SEMVER_IN_NAME = re.compile(r"_v(?P<version>\d+\.\d+\.\d+(?:[-+][\w.]+)?)", re.IGNORECASE)
DEFAULT_GITHUB_REPOSITORY = os.environ.get("GITHUB_REPOSITORY", "OpenScan-org/OpenScan3")
DEFAULT_RELEASE_BASE_URL = os.environ.get(
    "OPENSCAN_RELEASE_BASE_URL",
    f"https://github.com/{DEFAULT_GITHUB_REPOSITORY}/releases/download",
)


@dataclass
class Variant:
    suffix: str
    name: str
    description: str
    devices: List[str]
    capabilities: List[str]
    init_format: str
    icon: Optional[str]
    website: Optional[str]
    architecture: Optional[str]
    is_develop: bool = False

    def matches(self, build_id: str) -> bool:
        suffix_pattern = rf"_{re.escape(self.suffix)}(?:-[\w.-]+)*$"
        return re.search(suffix_pattern, build_id) is not None

    def develop_variant(self) -> "Variant":
        if self.is_develop:
            raise ValueError("Cannot derive develop variant from an existing develop variant")
        return Variant(
            suffix=f"{self.suffix}_DEVELOP",
            name=f"{self.name} (Develop)",
            description=f"{self.description} (stage6 developer services enabled)",
            devices=self.devices,
            capabilities=self.capabilities,
            init_format=self.init_format,
            icon=self.icon,
            website=self.website,
            architecture=self.architecture,
            is_develop=True,
        )


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
        default=None,
        help=(
            "Optional HTTP(S) base URL where artifacts will be hosted. "
            "Defaults to https://github.com/<repo>/releases/download/<tag> if build names expose a semver tag."
        ),
    )
    parser.add_argument(
        "--release-date",
        default=None,
        help="ISO date (YYYY-MM-DD) to force as release_date for every entry.",
    )
    parser.add_argument(
        "--sublist-output",
        default="imager/os-sublist-openscan.json",
        help=(
            "Path for emitting an os-sublist JSON matching Raspberry Pi's example schema. "
            "Pass an empty string to disable."
        ),
    )
    parser.add_argument(
        "--skip-missing",
        action="store_true",
        help="Skip variants that have no matching artifact instead of stopping with an error.",
    )
    parser.add_argument(
        "--local-manifest",
        action="store_true",
        help=(
            "Emit an additional os_list_local.rpi-imager-manifest referencing file:// URIs "
            "for the located artifacts. Imager can load this to enable customization for local images."
        ),
    )
    parser.add_argument(
        "--local-output",
        default="imager/os_list_local.rpi-imager-manifest",
        help="Path for the optional local manifest (default: %(default)s)",
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
            website=entry.get("website"),
            architecture=entry.get("architecture"),
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
    extract_size, extract_sha256 = resolve_extract_metadata(artifact)
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
    if variant.website:
        entry["website"] = variant.website
    if variant.architecture:
        entry["architecture"] = variant.architecture
    if extract_size is not None:
        entry["extract_size"] = extract_size
    if extract_sha256 is not None:
        entry["extract_sha256"] = extract_sha256
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


def locate_uncompressed_image(artifact: Path) -> Optional[Path]:
    if artifact.suffix == ".img":
        return artifact
    base = canonical_build_id(artifact)
    candidate = artifact.with_name(f"{base}.img")
    if candidate.exists():
        return candidate
    return None


def resolve_extract_metadata(artifact: Path) -> tuple[Optional[int], Optional[str]]:
    uncompressed = locate_uncompressed_image(artifact)
    if not uncompressed:
        return None, None
    return uncompressed.stat().st_size, sha256sum(uncompressed)


def infer_release_tag(artifacts: List[Path]) -> Optional[str]:
    for path in artifacts:
        match = SEMVER_IN_NAME.search(path.name)
        if match:
            version = match.group("version")
            return f"v{version.lstrip('vV')}"
    return None


def derive_url_prefix(explicit_prefix: Optional[str], artifacts: List[Path]) -> str:
    if explicit_prefix is not None:
        return explicit_prefix
    release_tag = infer_release_tag(artifacts)
    if release_tag:
        return f"{DEFAULT_RELEASE_BASE_URL.rstrip('/')}/{release_tag}"
    return ""


SUBLIST_FIELDS: tuple[str, ...] = (
    "name",
    "description",
    "url",
    "icon",
    "website",
    "release_date",
    "extract_size",
    "extract_sha256",
    "image_download_size",
    "image_download_sha256",
    "devices",
    "init_format",
    "architecture",
)


def build_sublist_entries(os_entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    sub_entries: List[Dict[str, Any]] = []
    for entry in os_entries:
        sub_entry: Dict[str, Any] = {}
        for field in SUBLIST_FIELDS:
            if field in entry:
                sub_entry[field] = entry[field]
        sub_entries.append(sub_entry)
    return sub_entries


def main() -> None:
    args = parse_args()
    variants_path = Path(args.variants)
    deploy_dir = Path(args.deploy_dir)
    output_path = Path(args.output)
    release_date_override: Optional[str] = args.release_date
    sublist_output_path = Path(args.sublist_output) if args.sublist_output else None

    imager_meta, category_meta, variants = load_variants(variants_path)
    artifacts = list(iter_artifacts(deploy_dir))
    url_prefix = derive_url_prefix(args.url_prefix, artifacts)

    os_entries: List[Dict[str, Any]] = []
    artifact_paths: List[Path] = []
    skip_missing = args.skip_missing or args.local_manifest
    for variant in variants:
        try:
            artifact, release_date = select_latest_artifact(variant, artifacts)
        except FileNotFoundError:
            if skip_missing:
                continue
            raise
        if release_date_override:
            release_date = release_date_override
        os_entry = build_os_entry(variant, artifact, release_date, url_prefix)
        os_entries.append(os_entry)
        artifact_paths.append(artifact)

        develop_variant = variant.develop_variant()
        try:
            dev_artifact, dev_release_date = select_latest_artifact(develop_variant, artifacts)
        except FileNotFoundError:
            if skip_missing:
                continue
            raise
        if release_date_override:
            dev_release_date = release_date_override
        dev_entry = build_os_entry(develop_variant, dev_artifact, dev_release_date, url_prefix)
        os_entries.append(dev_entry)
        artifact_paths.append(dev_artifact)

    if not os_entries:
        raise FileNotFoundError(
            "No matching artifacts found. Provide build outputs in --deploy-dir or disable --skip-missing."
        )

    repo = {
        "imager": imager_meta,
        "os_list": assemble_os_list(category_meta, os_entries),
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(repo, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote Raspberry Pi Imager repository JSON to {output_path}")

    if sublist_output_path:
        sublist_output_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"os_list": build_sublist_entries(os_entries)}
        sublist_output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote Raspberry Pi Imager os-sublist JSON to {sublist_output_path}")

    if args.local_manifest:
        local_entries: List[Dict[str, Any]] = []
        for entry, artifact in zip(os_entries, artifact_paths):
            local_entry = deepcopy(entry)
            local_entry["url"] = artifact.resolve().as_uri()
            local_entries.append(local_entry)
        local_repo = {
            "imager": imager_meta,
            "os_list": assemble_os_list(category_meta, local_entries),
        }
        local_output_path = Path(args.local_output)
        local_output_path.parent.mkdir(parents=True, exist_ok=True)
        local_output_path.write_text(json.dumps(local_repo, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote Raspberry Pi Imager local manifest to {local_output_path}")


if __name__ == "__main__":
    main()
