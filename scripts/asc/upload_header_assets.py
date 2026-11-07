#!/usr/bin/env python3
"""Upload the product page header and apply it to every locale."""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
ASSET_LIBRARY_ID = "6831894963"
IMAGE_PATH = "docs/app-store/product-page-header.png"
STATE_PATH = "docs/app-store/creative.json"
PLACEMENTS = [
    ("PRODUCT_PAGE_HEADER_ASSET", "DEFAULT_PROFILE"),
    ("APP_STORE_SEARCH_RESULTS_ASSET", "DEFAULT_PROFILE"),
]

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


def reserve_image(path):
    data = open(path, "rb").read()
    body = {
        "data": {
            "type": "appAssetLibraryImages",
            "attributes": {
                "fileName": os.path.basename(path),
                "fileSize": len(data),
                "category": "CREATIVE_ASSETS",
                "referenceName": "Flipabulary product page header",
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
        raise RuntimeError(f"Reserve header failed: {status} {payload}")
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
        raise RuntimeError(f"Commit header failed: {status} {payload}")
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
        attributes = item["attributes"]
        image = item.get("relationships", {}).get("image", {}).get("data", {}).get("id")
        if image:
            key = (attributes["placementType"], attributes["placementGroup"], image)
            result[key] = item["id"]
    return result


def create_placement(image_id, localization_id, placement_type, group):
    status, payload = request(
        "POST",
        "/v1/appAssetLibraryPlacements",
        {
            "data": {
                "type": "appAssetLibraryPlacements",
                "attributes": {"placementType": placement_type, "placementGroup": group},
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
        raise RuntimeError(f"Placement {placement_type} failed: {status} {payload}")
    return payload["data"]["id"]


def main():
    state = {}
    if os.path.exists(STATE_PATH):
        state = json.load(open(STATE_PATH, encoding="utf-8"))

    image_id = state.get("imageId")
    if image_id:
        status, payload = request("GET", f"/v1/appAssetLibraryImages/{image_id}")
        if status != 200:
            image_id = None
    if not image_id:
        image_id = reserve_image(IMAGE_PATH)
        print("uploaded header ->", image_id)
    else:
        print("reusing header ->", image_id)

    attributes = wait_for_image(image_id)
    print("ready", attributes.get("specId"), attributes.get("imageAsset"))

    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]
    placement_ids = state.setdefault("placements", {})

    for locale, localization_id in version_localizations.items():
        current = existing_placements(localization_id)
        locale_ids = placement_ids.setdefault(locale, {})
        for placement_type, group in PLACEMENTS:
            key = (placement_type, group, image_id)
            placement_id = current.get(key) or create_placement(
                image_id, localization_id, placement_type, group
            )
            locale_ids[placement_type] = placement_id
            print(f"{locale} {placement_type}: {placement_id}")

    state["imageId"] = image_id
    state["specId"] = attributes.get("specId")
    with open(STATE_PATH, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote", STATE_PATH)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
