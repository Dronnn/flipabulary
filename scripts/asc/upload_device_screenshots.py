#!/usr/bin/env python3
"""Upload marketing screenshots for older device classes and place them."""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
ASSET_LIBRARY_ID = "6831894963"
ORDER = ["words", "review", "editor", "widgets", "rules", "support"]
SCREENSHOTS_PATH = "docs/app-store/screenshots.json"

GROUPS = {
    "iphone-65": "IPHONE_FACE_ID_LARGE_PROFILE",
    "iphone-63": "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE",
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
    return 599, {"error": "request retries exhausted"}


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


def list_images():
    result = {}
    path = "/v1/appAssetLibraries/6831894963/images?limit=200"
    while path:
        status, payload = request("GET", path)
        if status != 200:
            raise RuntimeError(f"List images failed: {status} {payload}")
        for item in payload.get("data", []):
            name = item["attributes"].get("referenceName")
            if name:
                result[name] = item
        next_link = payload.get("links", {}).get("next")
        if not next_link:
            break
        path = next_link.replace(BASE, "")
    return result


def wait_for_image(image_id):
    for attempt in range(60):
        status, payload = request("GET", f"/v1/appAssetLibraryImages/{image_id}")
        if status != 200:
            raise RuntimeError(f"Read image failed: {status} {payload}")
        attributes = payload["data"]["attributes"]
        state = attributes.get("state")
        if state == "PREPARE_FOR_SUBMISSION":
            return attributes
        if state == "FAILED":
            raise RuntimeError(f"Image failed: {attributes.get('stateDetails')}")
        time.sleep(min(3 + attempt, 15))
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
            key = (item["attributes"]["placementGroup"], image)
            result[key] = item["id"]
    return result


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


def save(screenshots):
    with open(SCREENSHOTS_PATH, "w", encoding="utf-8") as handle:
        json.dump(screenshots, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def main():
    requested = [value for value in sys.argv[1:] if not value.startswith("-")]
    if not requested or "--all" in sys.argv:
        keys = list(GROUPS)
    else:
        keys = requested
    for key in keys:
        if key not in GROUPS:
            raise RuntimeError(f"Unknown group {key}")

    screenshots = json.load(open(SCREENSHOTS_PATH, encoding="utf-8"))
    images_by_group = screenshots.setdefault("images", {})
    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]
    placements = screenshots.setdefault("placements", {})

    # Phase 1: reserve and transfer every missing image without waiting for
    # processing, so Apple can prepare them in parallel.
    refresh_token()
    known_images = list_images()
    image_ids = {}
    pending = []
    for key in keys:
        images = images_by_group.setdefault(key, {})
        for slug in ORDER:
            reference = f"{key} {slug} — marketing"
            found = known_images.get(reference)
            if found and found["attributes"].get("state") != "FAILED":
                image_id = found["id"]
                print(f"reuse {key}/{slug} -> {image_id}", flush=True)
            else:
                measured = images.get(slug)
                if measured:
                    status, _ = request("GET", f"/v1/appAssetLibraryImages/{measured}")
                    if status == 200:
                        image_id = measured
                        print(f"reuse {key}/{slug} -> {image_id}", flush=True)
                    else:
                        measured = None
                if not measured:
                    path = f"docs/app-store/{key}/{slug}.jpg"
                    image_id = reserve_image(path, reference)
                    print(f"uploaded {path} -> {image_id}", flush=True)
            images[slug] = image_id
            image_ids[(key, slug)] = image_id
            pending.append((key, slug, image_id))
    save(screenshots)
    print("phase 1 complete: all images transferred", flush=True)

    # Phase 2: wait for processing in one pass.
    for key, slug, image_id in pending:
        attributes = wait_for_image(image_id)
        print(f"ready {key}/{slug} {attributes.get('specId')}", flush=True)

    # Phase 3: place and order in every locale.
    for key in keys:
        refresh_token()
        group = GROUPS[key]
        print(f"=== placing {key} -> {group} ===", flush=True)
        for locale, localization_id in version_localizations.items():
            current = existing_placements(localization_id)
            ids = []
            for slug in ORDER:
                image_id = image_ids[(key, slug)]
                placement_id = current.get((group, image_id)) or create_placement(
                    image_id, localization_id, group
                )
                ids.append(placement_id)
            order(localization_id, group, ids)
            placements.setdefault(locale, {})[key] = ids
            print(f"{locale} {key}: {len(ids)} placements ordered", flush=True)
        save(screenshots)
        print(f"saved {SCREENSHOTS_PATH} after {key}", flush=True)

    print("done")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
