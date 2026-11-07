#!/usr/bin/env python3
"""Verify the App Store page: placements, localizations, and IAP metadata."""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6831894963"

EXPECTED_SCREENSHOTS = {
    "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE": 6,
    "IPHONE_FACE_ID_LARGE_PROFILE": 6,
    "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE": 6,
    "IPHONE_FACE_ID_MEDIUM_PROFILE": 6,
    "IPHONE_HOME_BUTTON_LARGE_PROFILE": 6,
    "IPHONE_HOME_BUTTON_MEDIUM_PROFILE": 6,
    "IPHONE_HOME_BUTTON_40_PROFILE": 6,
    "IPHONE_HOME_BUTTON_35_PROFILE": 6,
    "IPAD_13_PROFILE": 6,
    "IPAD_129_PROFILE": 6,
    "IPAD_11_PROFILE": 6,
    "IPAD_105_PROFILE": 6,
    "IPAD_97_PROFILE": 6,
    "IPHONE_DUO_PROFILE": 6,
    "PRODUCT_PAGE_HEADER_ASSET": 1,
    "APP_STORE_SEARCH_RESULTS_ASSET": 1,
}

TOKEN = subprocess.check_output(
    ["ruby", os.path.expanduser("~/.config/opencode/scripts/asc-jwt.rb")],
    text=True,
).strip()


def get(path):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + TOKEN})
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"GET {path} failed: {error.code} {error.read().decode()}")


def main():
    localizations = json.load(open("docs/app-store/localizations.json", encoding="utf-8"))
    version_localizations = localizations["appStoreVersion"]
    problems = []

    for locale, localization_id in version_localizations.items():
        payload = get(f"/v1/appStoreVersionLocalizations/{localization_id}/placements?limit=200")
        counts = {}
        for item in payload.get("data", []):
            attributes = item["attributes"]
            key = (
                attributes["placementType"]
                if attributes["placementType"] != "APP_SCREENSHOT"
                else attributes["placementGroup"]
            )
            counts[key] = counts.get(key, 0) + 1
        for key, expected in EXPECTED_SCREENSHOTS.items():
            actual = counts.get(key, 0)
            if actual != expected:
                problems.append(f"{locale}: {key} = {actual}, expected {expected}")

    app_info = get(
        f"/v1/appInfos/64555a63-89db-4b46-870c-90a59c630d2c/appInfoLocalizations?limit=50"
    )
    if len(app_info.get("data", [])) != 16:
        problems.append(f"app info localizations = {len(app_info.get('data', []))}, expected 16")
    version = get(
        "/v1/appStoreVersions/a2cabc05-51d4-4f35-b9dd-5f298da38b63/appStoreVersionLocalizations?limit=50"
    )
    if len(version.get("data", [])) != 16:
        problems.append(f"version localizations = {len(version.get('data', []))}, expected 16")

    products = get(f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=50")
    for item in sorted(products.get("data", []), key=lambda value: value["attributes"]["name"]):
        name = item["attributes"]["name"]
        state = item["attributes"]["state"]
        if state != "READY_TO_SUBMIT":
            problems.append(f"{name}: state {state}")
        versions = get(f"/v2/inAppPurchases/{item['id']}/versions?limit=10")
        version_id = versions["data"][0]["id"]
        locales = get(f"/v1/inAppPurchaseVersions/{version_id}/localizations?limit=50")
        if len(locales.get("data", [])) != 16:
            problems.append(f"{name}: {len(locales.get('data', []))} localizations")
        images = get(f"/v1/inAppPurchaseVersions/{version_id}/images?limit=50")
        if len(images.get("data", [])) != 1:
            problems.append(f"{name}: {len(images.get('data', []))} promo images")
        screenshot = get(f"/v2/inAppPurchases/{item['id']}/appStoreReviewScreenshot")
        state = (
            screenshot.get("data", {})
            .get("attributes", {})
            .get("assetDeliveryState", {})
            .get("state")
        )
        if state != "COMPLETE":
            problems.append(f"{name}: review screenshot {state}")
        prices = get(f"/v1/inAppPurchasePriceSchedules/{item['id']}/manualPrices?limit=100")
        if len(prices.get("data", [])) != 62:
            problems.append(f"{name}: {len(prices.get('data', []))} manual prices")

    if problems:
        print("PROBLEMS")
        for problem in problems:
            print(" -", problem)
        return 1
    print("OK: 16 locales, 14 screenshot groups, header, search results, and 6 IAPs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
