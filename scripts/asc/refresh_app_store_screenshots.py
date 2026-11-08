#!/usr/bin/env python3
"""Replace every App Store screenshot with the current English-Spanish set."""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
ASSET_ID = "6831894963"
ORDER = ["words", "review", "editor", "widgets", "rules", "stackSettings"]
STATE_PATH = "docs/app-store/screenshots-v2.json"

GROUPS = {
    "iphone-69": "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
    "iphone-65": "IPHONE_FACE_ID_LARGE_PROFILE",
    "iphone-63": "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE",
    "iphone-61": "IPHONE_FACE_ID_MEDIUM_PROFILE",
    "iphone-55": "IPHONE_HOME_BUTTON_LARGE_PROFILE",
    "iphone-47": "IPHONE_HOME_BUTTON_MEDIUM_PROFILE",
    "iphone-40": "IPHONE_HOME_BUTTON_40_PROFILE",
    "iphone-35": "IPHONE_HOME_BUTTON_35_PROFILE",
    "duo": "IPHONE_DUO_PROFILE",
    "ipad-13": "IPAD_13_PROFILE",
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
                "assetLibrary": {"data": {"type": "appAssetLibraries", "id": ASSET_ID}}
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


def save(state):
    with open(STATE_PATH, "w", encoding="utf-8") as handle:
        json.dump(state, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


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
    state = {}
    if os.path.exists(STATE_PATH):
        state = json.load(open(STATE_PATH, encoding="utf-8"))
    images = state.setdefault("images", {})
    placements = state.setdefault("placements", {})

    # Phase 1: upload every image.
    for key in GROUPS:
        images.setdefault(key, {})
        for slug in ORDER:
            known = images[key].get(slug)
            if known:
                status, _ = request("GET", f"/v1/appAssetLibraryImages/{known}")
                if status == 200:
                    print(f"reuse {key}/{slug} -> {known}", flush=True)
                    continue
            path = (
                f"docs/app-store/duo-new/{slug}.jpg"
                if key == "duo"
                else f"docs/app-store/device-new/{key}/{slug}.jpg"
            )
            image_id = reserve_image(path, f"2026-11-08 {key} {slug} — English-Spanish")
            images[key][slug] = image_id
            save(state)
            print(f"uploaded {path} -> {image_id}", flush=True)

    # Phase 2: wait for processing.
    for key in GROUPS:
        for slug in ORDER:
            attributes = wait_for_image(images[key][slug])
            print(f"ready {key}/{slug} {attributes.get('specId')}", flush=True)

    # Phase 3: replace placements in every locale.
    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]
    for key, group in GROUPS.items():
        refresh_token()
        print(f"=== replacing {key} -> {group} ===", flush=True)
        for locale, localization_id in version_localizations.items():
            existing = list_placements(localization_id)
            for item in existing:
                attributes = item["attributes"]
                if (
                    attributes.get("placementType") == "APP_SCREENSHOT"
                    and attributes.get("placementGroup") == group
                ):
                    delete_placement(item["id"])
            ids = []
            for slug in ORDER:
                ids.append(create_placement(images[key][slug], localization_id, group))
            order(localization_id, group, ids)
            placements.setdefault(locale, {})[key] = ids
            print(f"{locale} {key}: 6 replaced", flush=True)
        save(state)
    print("done", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr, flush=True)
        sys.exit(1)
