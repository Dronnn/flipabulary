#!/usr/bin/env python3
"""Keep only the required screenshot sizes and remove optional legacy groups."""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
STATE_PATH = "docs/app-store/screenshots-v2.json"
FINAL_PATH = "docs/app-store/screenshots-final.json"
ORDER = ["words", "review", "editor", "widgets", "rules", "stackSettings"]

REQUIRED = {
    "iphone-69": "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
    "iphone-63": "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE",
    "duo": "IPHONE_DUO_PROFILE",
    "ipad-13": "IPAD_13_PROFILE",
}

OPTIONAL = {
    "iphone-65": "IPHONE_FACE_ID_LARGE_PROFILE",
    "iphone-61": "IPHONE_FACE_ID_MEDIUM_PROFILE",
    "iphone-55": "IPHONE_HOME_BUTTON_LARGE_PROFILE",
    "iphone-47": "IPHONE_HOME_BUTTON_MEDIUM_PROFILE",
    "iphone-40": "IPHONE_HOME_BUTTON_40_PROFILE",
    "iphone-35": "IPHONE_HOME_BUTTON_35_PROFILE",
    "ipad-129": "IPAD_129_PROFILE",
    "ipad-11": "IPAD_11_PROFILE",
    "ipad-105": "IPAD_105_PROFILE",
    "ipad-97": "IPAD_97_PROFILE",
}


def mint_token():
    return subprocess.check_output(
        ["ruby", os.path.expanduser("~/.config/opencode/scripts/asc-jwt.rb")],
        text=True,
    ).strip()


TOKEN = mint_token()


def refresh_token():
    global TOKEN
    TOKEN = mint_token()


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    refreshed = False
    for attempt in range(5):
        req = urllib.request.Request(
            BASE + path,
            data=data,
            method=method,
            headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=180) as response:
                payload = response.read().decode()
                return response.status, json.loads(payload) if payload else {}
        except urllib.error.HTTPError as error:
            payload = error.read().decode()
            if error.code == 401 and not refreshed:
                refresh_token()
                refreshed = True
                continue
            if error.code == 429 or 500 <= error.code < 600:
                time.sleep(5 * (attempt + 1))
                continue
            return error.code, json.loads(payload) if payload else {}
    return 599, {"error": "retries exhausted"}


def list_placements(localization_id):
    status, payload = request(
        "GET",
        f"/v1/appStoreVersionLocalizations/{localization_id}/placements?limit=200",
    )
    if status != 200:
        raise RuntimeError(f"List placements failed: {status} {payload}")
    return payload.get("data", [])


def delete_placement(placement_id):
    status, payload = request("DELETE", f"/v1/appAssetLibraryPlacements/{placement_id}")
    if status not in (200, 204):
        raise RuntimeError(f"Delete placement failed: {status} {payload}")


def create_placement(image_id, localization_id, group):
    status, payload = request(
        "POST",
        "/v1/appAssetLibraryPlacements",
        {
            "data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": group},
                "relationships": {
                    "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": localization_id,
                        }
                    },
                },
            }
        },
    )
    if status != 201:
        raise RuntimeError(f"Create placement failed: {status} {payload}")
    return payload["data"]["id"]


def order(localization_id, group, placement_ids):
    status, payload = request(
        "POST",
        "/v1/appAssetLibraryPlacementOrderingRequests",
        {
            "data": {
                "type": "appAssetLibraryPlacementOrderingRequests",
                "attributes": {"placementGroup": group},
                "relationships": {
                    "orderedPlacements": {
                        "data": [
                            {"type": "appAssetLibraryPlacements", "id": placement_id}
                            for placement_id in placement_ids
                        ]
                    },
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": localization_id,
                        }
                    },
                },
            }
        },
    )
    if status != 201:
        raise RuntimeError(f"Order failed: {status} {payload}")


def main():
    state = json.load(open(STATE_PATH, encoding="utf-8"))
    images = state.get("images", {})
    for key in list(REQUIRED) + list(OPTIONAL):
        if len(images.get(key, {})) != len(ORDER):
            raise RuntimeError(f"Missing images for {key}")

    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]
    result = {"placements": {}}

    for locale, localization_id in version_localizations.items():
        refresh_token()
        print(f"=== {locale} ===", flush=True)
        existing = list_placements(localization_id)

        for key, group in OPTIONAL.items():
            for item in existing:
                attributes = item["attributes"]
                if (
                    attributes.get("placementType") == "APP_SCREENSHOT"
                    and attributes.get("placementGroup") == group
                ):
                    delete_placement(item["id"])
            print(f"{locale} {key}: removed", flush=True)

        for key, group in REQUIRED.items():
            for item in existing:
                attributes = item["attributes"]
                if (
                    attributes.get("placementType") == "APP_SCREENSHOT"
                    and attributes.get("placementGroup") == group
                ):
                    delete_placement(item["id"])
            ids = []
            for slug in ORDER:
                ids.append(
                    create_placement(images[key][slug], localization_id, group)
                )
            order(localization_id, group, ids)
            result["placements"].setdefault(locale, {})[key] = ids
            print(f"{locale} {key}: 6 placed", flush=True)

    with open(FINAL_PATH, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    print("done", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr, flush=True)
        sys.exit(1)
