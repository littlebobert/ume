#!/usr/bin/env python3
from __future__ import annotations

import base64
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import publish_store_metadata as metadata

BASE = metadata.APP_STORE_CONNECT_BASE


def localization(identifier: str, locale: str, **attributes) -> dict:
    return {"id": identifier, "attributes": {"locale": locale, **attributes}}


class StoreMetadataTests(unittest.TestCase):
    def write_files(self, root: Path, files: dict[str, str]) -> None:
        for relative, text in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text + "\n", encoding="utf-8")

    def test_accepts_the_key_as_pem_or_base64(self) -> None:
        pem = "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----"
        self.assertEqual(metadata.private_key_text(pem), pem)
        self.assertEqual(metadata.private_key_text(base64.b64encode(pem.encode()).decode()), pem)

    def test_reads_only_the_fields_a_language_sets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_files(root, {"ko/subtitle.txt": "알림을 가볍게", "en-GB/keywords.txt": "spam,focus"})
            self.assertEqual(
                metadata.read_locale_files(root),
                {"en-GB": {"keywords.txt": "spam,focus"}, "ko": {"subtitle.txt": "알림을 가볍게"}},
            )
        self.assertEqual(metadata.read_locale_files(Path("/nonexistent")), {})

    def test_validation_catches_limits_urls_and_spaced_keywords(self) -> None:
        problems = metadata.validate({
            "en-US": {
                "subtitle.txt": "x" * 31,
                "support_url.txt": "http://kaketa.jp",
                "keywords.txt": "spam, focus",
            }
        })
        self.assertEqual(len(problems), 3)
        self.assertEqual(metadata.validate({"ko": {"name.txt": "Kaketa", "keywords.txt": "스팸,집중 모드"}}), [])

    def test_plans_only_changed_fields_and_new_languages(self) -> None:
        current = {"en-US": localization("loc-1", "en-US", keywords="spam,focus", description="Old")}
        desired = {
            "en-US": {"keywords.txt": "spam,focus", "description.txt": "New"},
            "ko": {"keywords.txt": "스팸"},
        }
        changes = metadata.plan_changes(desired, current, metadata.VERSION_FIELDS)
        self.assertEqual(
            [(locale, attributes, existing and existing["id"]) for locale, attributes, existing in changes],
            [("en-US", {"description": "New"}, "loc-1"), ("ko", {"keywords": "스팸"}, None)],
        )

    def test_push_updates_existing_and_creates_missing_localizations(self) -> None:
        version = {"id": "ver-1", "attributes": {"versionString": "0.2", "appVersionState": "PREPARE_FOR_SUBMISSION"}}
        live = {"id": "ver-0", "attributes": {"versionString": "0.1", "appVersionState": "READY_FOR_DISTRIBUTION"}}
        responses = {
            f"{BASE}/apps/app-1/appStoreVersions?filter%5Bplatform%5D=IOS&limit=50": {"data": [version, live]},
            f"{BASE}/appStoreVersions/ver-1/appStoreVersionLocalizations?limit=200": {
                "data": [localization("loc-en", "en-US", whatsNew="Old")]
            },
            f"{BASE}/apps/app-1/appInfos": {"data": [
                {"id": "info-live", "attributes": {"appStoreState": "READY_FOR_DISTRIBUTION"}},
                {"id": "info-next", "attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}},
            ]},
            f"{BASE}/appInfos/info-next/appInfoLocalizations?limit=200": {"data": []},
        }
        writes = []

        def fake_request(url, *, token, method="GET", payload=None):
            if method == "GET":
                return responses[url]
            writes.append((method, url, payload))
            return {}

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_files(root, {"en-US/whats_new.txt": "New", "ko/subtitle.txt": "알림을 가볍게"})
            with patch.object(metadata, "request_json", side_effect=fake_request):
                metadata.push("token", "app-1", root, None, dry_run=False)

        self.assertEqual(writes[0][:2], ("PATCH", f"{BASE}/appStoreVersionLocalizations/loc-en"))
        self.assertEqual(writes[0][2]["data"]["attributes"], {"whatsNew": "New"})
        self.assertEqual(writes[1][:2], ("POST", f"{BASE}/appInfoLocalizations"))
        self.assertEqual(writes[1][2]["data"]["attributes"], {"locale": "ko", "subtitle": "알림을 가볍게"})
        self.assertEqual(writes[1][2]["data"]["relationships"]["appInfo"]["data"]["id"], "info-next")
        self.assertEqual(len(writes), 2)

    def test_dry_run_writes_nothing(self) -> None:
        version = {"id": "ver-1", "attributes": {"versionString": "0.2", "appStoreState": "PREPARE_FOR_SUBMISSION"}}
        responses = {
            f"{BASE}/apps/app-1/appStoreVersions?filter%5Bplatform%5D=IOS&limit=50": {"data": [version]},
            f"{BASE}/appStoreVersions/ver-1/appStoreVersionLocalizations?limit=200": {"data": []},
        }

        def fake_request(url, *, token, method="GET", payload=None):
            self.assertEqual(method, "GET")
            return responses[url]

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_files(root, {"ko/keywords.txt": "스팸"})
            with patch.object(metadata, "request_json", side_effect=fake_request):
                metadata.push("token", "app-1", root, None, dry_run=True)

    def test_refuses_when_no_version_is_being_prepared(self) -> None:
        live = {"id": "ver-0", "attributes": {"versionString": "0.1", "appVersionState": "READY_FOR_DISTRIBUTION"}}
        with patch.object(metadata, "request_json", return_value={"data": [live]}):
            with self.assertRaises(SystemExit):
                metadata.find_editable_version("token", "app-1", None)


if __name__ == "__main__":
    unittest.main()


class WriteLocalizationTests(unittest.TestCase):
    def test_skips_an_attribute_the_store_wont_take_and_keeps_the_rest(self):
        calls = []

        def fake_request(url, *, token, method="GET", payload=None):
            attributes = payload["data"]["attributes"]
            calls.append(dict(attributes))
            if "whatsNew" in attributes:
                raise RuntimeError(
                    'PATCH ' + url + ' returned 409: {"errors":[{"code":"STATE_ERROR",'
                    '"detail":"Attribute \'whatsNew\' cannot be edited at this time"}]}'
                )
            return {}

        original = metadata.request_json
        metadata.request_json = fake_request
        try:
            metadata.write_localization(
                "token", "appStoreVersionLocalizations", "en-US",
                {"description": "New", "whatsNew": "First release."},
                {"id": "loc1", "attributes": {}}, "appStoreVersion", "appStoreVersions", "v1",
            )
        finally:
            metadata.request_json = original
        self.assertEqual(calls, [{"description": "New", "whatsNew": "First release."}, {"description": "New"}])

    def test_other_errors_still_raise(self):
        def fake_request(url, *, token, method="GET", payload=None):
            raise RuntimeError("POST x returned 500: boom")

        original = metadata.request_json
        metadata.request_json = fake_request
        try:
            with self.assertRaises(RuntimeError):
                metadata.write_localization("t", "appInfoLocalizations", "ja", {"name": "Kaketa"}, None, "appInfo", "appInfos", "i1")
        finally:
            metadata.request_json = original

