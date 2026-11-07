#!/usr/bin/env python3
"""Upload iPhone Duo screenshots and place them in every locale."""

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
GROUP = "IPHONE_DUO_PROFILE"
ORDER = ["words", "review", "editor", "widgets", "rules", "support"]
FOLDER = "docs/app-store/duo"
SCREENSHOTS_PATH = "docs/app-store/screenshots.json"

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
    for attempt in range(40):
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


def create_placement(image_id, localization_id):
    status, payload = request(
        "POST",
        "/v1/appAssetLibraryPlacements",
        {
            "data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": GROUP},
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


def order(localization_id, placement_ids):
    status, payload = request(
        "POST",
        "/v1/appAssetLibraryPlacementOrderingRequests",
        {
            "data": {
                "type": "appAssetLibraryPlacementOrderingRequests",
                "attributes": {"placementGroup": GROUP},
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
    screenshots = json.load(open(SCREENSHOTS_PATH, encoding="utf-8"))
    images = screenshots.setdefault("images", {}).setdefault("duo", {})
    existing_ids = {}

    for slug in ORDER:
        known = images.get(slug)
        if known:
            status, payload = request("GET", f"/v1/appAssetLibraryImages/{known}")
            if status == 200:
                existing_ids[slug] = known
                print(f"reuse {slug} -> {known}")
                continue
        path = f"{FOLDER}/{slug}.jpg"
        image_id = reserve_image(path, f"iPhone Duo {slug.capitalize()} — marketing")
        print(f"uploaded {path} -> {image_id}")
        attributes = wait_for_image(image_id)
        print(f"  ready {attributes.get('specId')} {attributes.get('imageAsset')}")
        images[slug] = image_id
        existing_ids[slug] = image_id

    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]
    placements = screenshots.setdefault("placements", {})

    for locale, localization_id in version_localizations.items():
        current = existing_placements(localization_id)
        ids = []
        for slug in ORDER:
            image_id = existing_ids[slug]
            placement_id = current.get((GROUP, image_id)) or create_placement(
                image_id, localization_id
            )
            ids.append(placement_id)
        order(localization_id, ids)
        placements.setdefault(locale, {})["duo"] = ids
        print(f"{locale}: {len(ids)} Duo placements ordered")

    with open(SCREENSHOTS_PATH, "w", encoding="utf-8") as handle:
        json.dump(screenshots, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote", SCREENSHOTS_PATH)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
