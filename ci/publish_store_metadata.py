#!/usr/bin/env python3
"""Sync Umete's iOS App Store listing with the files in AppStoreMetadata/.

Each language is a folder named with its App Store Connect locale (en-US, ja), holding
one text file per field. A field without a file is left as it is in App
Store Connect, so a language can set only what it needs.

  push  Update the App Store version being prepared (and the app's name and subtitle)
        to match the files. With --dry-run, only print what would change.
  pull  Write the current listing into the files, to start from what's live.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

APP_STORE_CONNECT_BASE = "https://api.appstoreconnect.apple.com/v1"

# File name → attribute, and App Store Connect's character limits.
VERSION_FIELDS = {
    "description.txt": ("description", 4000),
    "keywords.txt": ("keywords", 100),
    "promotional_text.txt": ("promotionalText", 170),
    "whats_new.txt": ("whatsNew", 4000),
    "support_url.txt": ("supportUrl", None),
    "marketing_url.txt": ("marketingUrl", None),
}
APP_INFO_FIELDS = {
    "name.txt": ("name", 30),
    "subtitle.txt": ("subtitle", 30),
    "privacy_policy_url.txt": ("privacyPolicyUrl", None),
}
# App Store versions whose metadata can still be edited.
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}
# App infos that are live or in review can't take new names or subtitles.
LOCKED_APP_INFO_STATES = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "WAITING_FOR_REVIEW", "IN_REVIEW"}


# App Store Connect API tokens: an ES256 JWT signed with the API key, using openssl so
# the script needs nothing beyond Python's standard library.
def encode_base64_url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def convert_der_signature_to_jose(der_signature: bytes) -> bytes:
    if len(der_signature) < 8 or der_signature[0] != 0x30:
        raise SystemExit("Unexpected ECDSA DER signature format")
    index = 2 if der_signature[1] < 0x80 else 3
    coordinates = []
    for name in ("r", "s"):
        if der_signature[index] != 0x02:
            raise SystemExit(f"Unexpected ECDSA signature: missing {name}")
        length = der_signature[index + 1]
        coordinates.append(der_signature[index + 2 : index + 2 + length])
        index += 2 + length

    def normalize(value: bytes) -> bytes:
        value = value.lstrip(b"\x00") or b"\x00"
        if len(value) > 32:
            raise SystemExit("ECDSA coordinate exceeds 32 bytes")
        return value.rjust(32, b"\x00")

    return b"".join(normalize(value) for value in coordinates)


def private_key_text(value: str) -> str:
    """The .p8 key, from the PEM text or, as Umete's secrets store it, base64 of it."""
    value = value.strip()
    if value.startswith("-----BEGIN"):
        return value
    try:
        return base64.b64decode(value, validate=False).decode("utf-8").strip()
    except (ValueError, UnicodeDecodeError) as error:
        raise SystemExit("APP_STORE_CONNECT_PRIVATE_KEY_BASE64 is not a base64-encoded .p8 key") from error


def create_app_store_connect_token(key_id: str, issuer_id: str, private_key: str) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = (
        f"{encode_base64_url(json.dumps(header, separators=(',', ':')).encode())}."
        f"{encode_base64_url(json.dumps(payload, separators=(',', ':')).encode())}"
    ).encode("ascii")
    with tempfile.TemporaryDirectory() as directory:
        key_path = Path(directory) / "AuthKey.p8"
        signature_path = Path(directory) / "signature.der"
        key_path.write_text(private_key_text(private_key) + "\n", encoding="utf-8")
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(key_path), "-out", str(signature_path)],
            input=signing_input, capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise SystemExit(f"openssl failed to sign the App Store Connect token: {result.stderr.decode(errors='replace')}")
        signature = convert_der_signature_to_jose(signature_path.read_bytes())
    return f"{signing_input.decode('ascii')}.{encode_base64_url(signature)}"


def request_json(url: str, *, token: str, method: str = "GET", payload: dict | None = None) -> dict:
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} returned {error.code}: {body}") from error


def read_locale_files(metadata_dir: Path) -> dict[str, dict[str, str]]:
    """{locale: {file name: text}} for every language folder."""
    locales = {}
    if not metadata_dir.is_dir():
        return locales
    for folder in sorted(path for path in metadata_dir.iterdir() if path.is_dir()):
        fields = {}
        for name in [*VERSION_FIELDS, *APP_INFO_FIELDS]:
            path = folder / name
            if path.exists():
                fields[name] = path.read_text(encoding="utf-8").strip()
        if fields:
            locales[folder.name] = fields
    return locales


def validate(locales: dict[str, dict[str, str]]) -> list[str]:
    problems = []
    for locale, fields in locales.items():
        for name, text in fields.items():
            attribute, limit = {**VERSION_FIELDS, **APP_INFO_FIELDS}[name]
            if limit is not None and len(text) > limit:
                problems.append(f"{locale}/{name}: {len(text)} characters, over the {limit} limit")
            if name.endswith("_url.txt") and text and not text.startswith("https://"):
                problems.append(f"{locale}/{name}: must be an https:// URL")
            if name == "keywords.txt" and ", " in text:
                problems.append(f"{locale}/{name}: separate keywords with commas only; spaces count toward the limit")
    return problems


def find_app_id(token: str, bundle_id: str) -> str:
    query = urllib.parse.urlencode({"filter[bundleId]": bundle_id, "limit": 1})
    apps = request_json(f"{APP_STORE_CONNECT_BASE}/apps?{query}", token=token)["data"]
    if not apps:
        raise SystemExit(f"No App Store Connect app for bundle ID {bundle_id}")
    return apps[0]["id"]


def version_state(version: dict) -> str:
    attributes = version["attributes"]
    return attributes.get("appVersionState") or attributes.get("appStoreState") or ""


def find_editable_version(token: str, app_id: str, version_string: str | None) -> dict:
    query = urllib.parse.urlencode({"filter[platform]": "IOS", "limit": 50})
    versions = request_json(f"{APP_STORE_CONNECT_BASE}/apps/{app_id}/appStoreVersions?{query}", token=token)["data"]
    editable = [version for version in versions if version_state(version) in EDITABLE_VERSION_STATES]
    if version_string:
        editable = [version for version in editable if version["attributes"]["versionString"] == version_string]
    if not editable:
        wanted = f"version {version_string}" if version_string else "a version"
        raise SystemExit(
            f"No App Store version open for editing ({wanted}). Create the next version in "
            "App Store Connect first; only versions being prepared or rejected can change."
        )
    return editable[0]


def find_app_info(token: str, app_id: str, *, editable: bool) -> dict:
    infos = request_json(f"{APP_STORE_CONNECT_BASE}/apps/{app_id}/appInfos", token=token)["data"]
    if editable:
        infos = [info for info in infos if info["attributes"].get("appStoreState") not in LOCKED_APP_INFO_STATES]
    if not infos:
        raise SystemExit("No app info open for editing; the name and subtitle change with a new version.")
    return infos[0]


def localizations(token: str, url: str) -> dict[str, dict]:
    """{locale: localization} from a localizations URL."""
    data = request_json(f"{url}?limit=200", token=token)["data"]
    return {item["attributes"]["locale"]: item for item in data}


def plan_changes(
    desired: dict[str, dict[str, str]],
    current: dict[str, dict],
    fields: dict[str, tuple[str, int | None]],
) -> list[tuple[str, dict, dict | None]]:
    """(locale, changed attributes, existing localization or None to create) for each
    language whose files differ from App Store Connect."""
    changes = []
    for locale, files in desired.items():
        wanted = {fields[name][0]: text for name, text in files.items() if name in fields}
        if not wanted:
            continue
        existing = current.get(locale)
        existing_attributes = existing["attributes"] if existing else {}
        changed = {key: value for key, value in wanted.items() if (existing_attributes.get(key) or "") != value}
        if changed:
            changes.append((locale, changed, existing))
    return changes


def apply_changes(
    token: str,
    changes: list[tuple[str, dict, dict | None]],
    *,
    resource: str,
    parent_relationship: str,
    parent_type: str,
    parent_id: str,
    dry_run: bool,
) -> None:
    for locale, attributes, existing in changes:
        verb = "Update" if existing else "Add"
        print(f"{verb} {resource} {locale}: {', '.join(sorted(attributes))}")
        for key, value in sorted(attributes.items()):
            before = (existing or {}).get("attributes", {}).get(key) or ""
            print(f"  {key}: {summarize(before)} → {summarize(value)}")
        if dry_run:
            continue
        write_localization(token, resource, locale, dict(attributes), existing, parent_relationship, parent_type, parent_id)


UNEDITABLE_ATTRIBUTE = re.compile(r"Attribute '(\w+)' cannot be edited at this time")


def write_localization(token, resource, locale, attributes, existing, parent_relationship, parent_type, parent_id):
    """Creates or updates one localization. An attribute App Store Connect won't take
    right now (What's New on an app's first version, which has nothing to be new
    against) is dropped with a note, and the rest still goes through."""
    while attributes:
        try:
            if existing:
                request_json(
                    f"{APP_STORE_CONNECT_BASE}/{resource}/{existing['id']}",
                    token=token,
                    method="PATCH",
                    payload={"data": {"type": resource, "id": existing["id"], "attributes": attributes}},
                )
            else:
                request_json(
                    f"{APP_STORE_CONNECT_BASE}/{resource}",
                    token=token,
                    method="POST",
                    payload={
                        "data": {
                            "type": resource,
                            "attributes": {"locale": locale, **attributes},
                            "relationships": {parent_relationship: {"data": {"type": parent_type, "id": parent_id}}},
                        }
                    },
                )
            return
        except RuntimeError as error:
            match = UNEDITABLE_ATTRIBUTE.search(str(error))
            if not match or match.group(1) not in attributes:
                raise
            print(f"  {match.group(1)}: App Store Connect won't take it for this version; skipped")
            del attributes[match.group(1)]


def summarize(text: str) -> str:
    flat = " ".join(text.split())
    return json.dumps(flat if len(flat) <= 70 else flat[:67] + "…", ensure_ascii=False) if flat else "(empty)"


def push(token: str, app_id: str, metadata_dir: Path, version_string: str | None, dry_run: bool) -> None:
    desired = read_locale_files(metadata_dir)
    problems = validate(desired)
    if problems:
        raise SystemExit("Metadata problems:\n" + "\n".join(f"- {problem}" for problem in problems))

    version = find_editable_version(token, app_id, version_string)
    print(f"App Store version {version['attributes']['versionString']} ({version_state(version)})")
    version_changes = plan_changes(
        desired,
        localizations(token, f"{APP_STORE_CONNECT_BASE}/appStoreVersions/{version['id']}/appStoreVersionLocalizations"),
        VERSION_FIELDS,
    )
    apply_changes(
        token, version_changes, resource="appStoreVersionLocalizations",
        parent_relationship="appStoreVersion", parent_type="appStoreVersions", parent_id=version["id"], dry_run=dry_run,
    )

    app_info_changes = []
    if any(name in APP_INFO_FIELDS for files in desired.values() for name in files):
        app_info = find_app_info(token, app_id, editable=True)
        app_info_changes = plan_changes(
            desired,
            localizations(token, f"{APP_STORE_CONNECT_BASE}/appInfos/{app_info['id']}/appInfoLocalizations"),
            APP_INFO_FIELDS,
        )
        apply_changes(
            token, app_info_changes, resource="appInfoLocalizations",
            parent_relationship="appInfo", parent_type="appInfos", parent_id=app_info["id"], dry_run=dry_run,
        )

    if not version_changes and not app_info_changes:
        print("Everything already matches.")
    elif dry_run:
        print("Dry run: nothing was changed.")


def pull(token: str, app_id: str, metadata_dir: Path) -> None:
    """Writes the newest version's listing, live or not, and the current app info."""
    query = urllib.parse.urlencode({"filter[platform]": "IOS", "limit": 1})
    versions = request_json(f"{APP_STORE_CONNECT_BASE}/apps/{app_id}/appStoreVersions?{query}", token=token)["data"]
    if not versions:
        raise SystemExit("The app has no App Store versions yet.")
    version = versions[0]
    sources = [
        (localizations(token, f"{APP_STORE_CONNECT_BASE}/appStoreVersions/{version['id']}/appStoreVersionLocalizations"), VERSION_FIELDS),
    ]
    app_info = find_app_info(token, app_id, editable=False)
    sources.append((localizations(token, f"{APP_STORE_CONNECT_BASE}/appInfos/{app_info['id']}/appInfoLocalizations"), APP_INFO_FIELDS))
    for current, fields in sources:
        for locale, localization in current.items():
            folder = metadata_dir / locale
            folder.mkdir(parents=True, exist_ok=True)
            for name, (attribute, _) in fields.items():
                value = localization["attributes"].get(attribute)
                if value:
                    (folder / name).write_text(value.strip() + "\n", encoding="utf-8")
    print(f"Wrote version {version['attributes']['versionString']}'s listing to {metadata_dir}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["push", "pull"])
    parser.add_argument("--metadata-dir", type=Path, default=Path("AppStoreMetadata"))
    parser.add_argument("--version", help="The App Store version to update; defaults to the one being prepared.")
    parser.add_argument("--dry-run", action="store_true", help="Show what push would change without changing it.")
    parser.add_argument("--validate-only", action="store_true", help="Check the files' lengths and URLs, offline.")
    arguments = parser.parse_args(argv)

    if arguments.validate_only:
        problems = validate(read_locale_files(arguments.metadata_dir))
        for problem in problems:
            print(f"- {problem}")
        print("Metadata is valid." if not problems else f"{len(problems)} problem(s).")
        return 1 if problems else 0

    def require(name: str) -> str:
        value = os.environ.get(name, "").strip()
        if not value:
            raise SystemExit(f"Missing required environment variable: {name}")
        return value

    token = create_app_store_connect_token(
        require("APP_STORE_CONNECT_KEY_ID"),
        require("APP_STORE_CONNECT_ISSUER_ID"),
        require("APP_STORE_CONNECT_PRIVATE_KEY_BASE64"),
    )
    app_id = find_app_id(token, require("BUNDLE_ID"))
    if arguments.mode == "pull":
        pull(token, app_id, arguments.metadata_dir)
    else:
        push(token, app_id, arguments.metadata_dir, arguments.version or None, arguments.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
