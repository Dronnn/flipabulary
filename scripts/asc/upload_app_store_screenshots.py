#!/usr/bin/env python3
"""Upload marketing screenshots to the App Asset Library and place them.

Usage:
  python3 scripts/asc/upload_app_store_screenshots.py --primary
  python3 scripts/asc/upload_app_store_screenshots.py --all
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6831894963"
ASSET_LIBRARY_ID = "6831894963"
ORDER = ["words", "review", "editor", "widgets", "rules", "support"]
GROUPS = {
    "iphone": ("IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE", "docs/app-store/iphone"),
    "ipad": ("IPAD_13_PROFILE", "docs/app-store/ipad"),
}

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
        with urllib.request.urlopen(req, timeout=180) as response:
            payload = response.read().decode()
            return response.status, json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        payload = error.read().decode()
        return error.code, json.loads(payload) if payload else {}


def upload_operations(operations, data):
    for op in operations:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op.get("offset", 0): op.get("offset", 0) + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"], headers=headers)
        with urllib.request.urlopen(req, timeout=180) as response:
            response.read()


def reserve_image(path, reference_name):
    data = open(path, "rb").read()
    body = {
        "data": {
            "type": "appAssetLibraryImages",
            "attributes": {
                "fileName": os.path.basename(path),
                "fileSize": len(data),
                "category": "APP_SCREENSHOTS_AND_PREVIEWS",
                "referenceName": reference_name,
            },
            "relationships": {
                "assetLibrary": {
                    "data": {"type": "appAssetLibraries", "id": ASSET_LIBRARY_ID}
                }
            },
        }
    }
    status, payload = request("POST", "/v1/appAssetLibraryImages", body)
    if status != 201:
        raise RuntimeError(f"Reserve {path} failed: {status} {payload}")
    image_id = payload["data"]["id"]
    upload_operations(payload["data"]["attributes"]["uploadOperations"], data)
    status, payload = request(
        "PATCH",
        f"/v1/appAssetLibraryImages/{image_id}",
        {
            "data": {
                "type": "appAssetLibraryImages",
                "id": image_id,
                "attributes": {"uploaded": True},
            }
        },
    )
    if status not in (200, 204):
        raise RuntimeError(f"Commit {path} failed: {status} {payload}")
    return image_id


def wait_for_image(image_id):
    for attempt in range(30):
        status, payload = request("GET", f"/v1/appAssetLibraryImages/{image_id}")
        if status != 200:
            raise RuntimeError(f"Read image failed: {status} {payload}")
        attributes = payload["data"]["attributes"]
        state = attributes.get("state")
        if state == "PREPARE_FOR_SUBMISSION":
            return attributes
        if state == "FAILED":
            raise RuntimeError(f"Image failed: {attributes.get('stateDetails')}")
        time.sleep(2 + attempt)
    raise RuntimeError(f"Image {image_id} did not finish processing")


def existing_placements(localization_id):
    status, payload = request(
        "GET",
        f"/v1/appStoreVersionLocalizations/{localization_id}/placements?limit=200",
    )
    if status != 200:
        return {}
    return {
        (item["attributes"]["placementGroup"], item["relationships"]["image"]["data"]["id"]): item["id"]
        for item in payload.get("data", [])
    }


def create_placement(image_id, localization_id, group):
    status, payload = request(
        "POST",
        "/v1/appAssetLibraryPlacements",
        {
            "data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {
                    "placementType": "APP_SCREENSHOT",
                    "placementGroup": group,
                },
                "relationships": {
                    "image": {
                        "data": {"type": "appAssetLibraryImages", "id": image_id}
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
    all_locales = "--all" in sys.argv
    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]
    locales = list(version_localizations) if all_locales else ["en-US"]

    images = {}
    for device, (group, folder) in GROUPS.items():
        images[device] = []
        for slug in ORDER:
            path = f"{folder}/{slug}.jpg"
            reference = f"{device.capitalize()} {slug} — marketing"
            image_id = reserve_image(path, reference)
            print(f"uploaded {path} -> {image_id}")
            attributes = wait_for_image(image_id)
            print(f"  ready {attributes.get('specId')} {attributes.get('imageAsset')}")
            images[device].append((slug, image_id))

    placements = {}
    for locale in locales:
        localization_id = version_localizations[locale]
        placements[locale] = {}
        existing = existing_placements(localization_id)
        for device, (group, _) in GROUPS.items():
            ids = []
            for slug, image_id in images[device]:
                key = (group, image_id)
                placement_id = existing.get(key) or create_placement(image_id, localization_id, group)
                ids.append(placement_id)
            placements[locale][device] = ids
            order(localization_id, group, ids)
            print(f"{locale} {device}: {len(ids)} placements ordered")

    os.makedirs("docs/app-store", exist_ok=True)
    with open("docs/app-store/screenshots.json", "w", encoding="utf-8") as handle:
        json.dump(
            {
                "images": {device: dict(items) for device, items in images.items()},
                "placements": placements,
            },
            handle,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        handle.write("\n")
    print("wrote docs/app-store/screenshots.json")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
