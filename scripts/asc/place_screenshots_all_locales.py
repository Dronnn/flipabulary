#!/usr/bin/env python3
"""Place the existing App Store screenshots in every localized listing."""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
GROUPS = {
    "iphone": "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
    "ipad": "IPAD_13_PROFILE",
}
ORDER = ["words", "review", "editor", "widgets", "rules", "support"]

TOKEN = subprocess.check_output(
    ["ruby", os.path.expanduser("~/.config/opencode/scripts/asc-jwt.rb")],
    text=True,
).strip()


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            payload = response.read().decode()
            return response.status, json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        payload = error.read().decode()
        return error.code, json.loads(payload) if payload else {}


def existing(localization_id):
    status, payload = request(
        "GET",
        f"/v1/appStoreVersionLocalizations/{localization_id}/placements?limit=200&include=image",
    )
    if status != 200:
        return {}
    result = {}
    for item in payload.get("data", []):
        image = item.get("relationships", {}).get("image", {}).get("data", {}).get("id")
        if image:
            result[(item["attributes"]["placementGroup"], image)] = item["id"]
    return result


def create(image_id, localization_id, group):
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
        raise RuntimeError(f"Placement failed: {status} {payload}")
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
        raise RuntimeError(f"Ordering failed: {status} {payload}")


def main():
    screenshots = json.load(open("docs/app-store/screenshots.json", encoding="utf-8"))
    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]

    images = screenshots["images"]
    placements = screenshots.get("placements", {})
    for locale, localization_id in version_localizations.items():
        if locale in placements:
            continue
        placements[locale] = {}
        current = existing(localization_id)
        for device, group in GROUPS.items():
            ids = []
            for slug in ORDER:
                image_id = images[device][slug]
                placement_id = current.get((group, image_id)) or create(
                    image_id, localization_id, group
                )
                ids.append(placement_id)
            placements[locale][device] = ids
            order(localization_id, group, ids)
            print(f"{locale} {device}: {len(ids)} placements")
        screenshots["placements"] = placements
        with open("docs/app-store/screenshots.json", "w", encoding="utf-8") as handle:
            json.dump(screenshots, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
    print("done")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
