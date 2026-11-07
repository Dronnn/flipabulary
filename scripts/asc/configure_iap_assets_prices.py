#!/usr/bin/env python3
"""Finish Flipabulary IAPs: promo image, review screenshot, US price, availability."""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6831894963"
REVIEW_SCREENSHOT = "docs/evidence/iphone-light/support.png"

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
        with urllib.request.urlopen(req, timeout=60) as response:
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
        with urllib.request.urlopen(req, timeout=120) as response:
            response.read()


def products():
    status, payload = request("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=50")
    if status != 200:
        raise RuntimeError(f"List IAPs failed: {status} {payload}")
    return {item["attributes"]["productId"]: item for item in payload.get("data", [])}


def version_for(iap_id):
    status, payload = request("GET", f"/v2/inAppPurchases/{iap_id}/versions?limit=10")
    if status != 200:
        raise RuntimeError(f"Versions failed: {status} {payload}")
    versions = payload.get("data", [])
    if not versions:
        raise RuntimeError(f"No version for {iap_id}")
    return versions[0]


def ensure_promo(version_id, slug):
    status, payload = request("GET", f"/v1/inAppPurchaseVersions/{version_id}/images?limit=50")
    if status == 200 and payload.get("data"):
        return
    path = f"docs/app-store/iap-icons/{slug}.jpg"
    data = open(path, "rb").read()
    body = {
        "data": {
            "type": "inAppPurchaseImages",
            "attributes": {"fileSize": len(data), "fileName": os.path.basename(path)},
            "relationships": {
                "version": {"data": {"type": "inAppPurchaseVersions", "id": version_id}}
            },
        }
    }
    status, payload = request("POST", "/v2/inAppPurchaseImages", body)
    if status != 201:
        raise RuntimeError(f"Promo reserve {slug} failed: {status} {payload}")
    image_id = payload["data"]["id"]
    upload_operations(payload["data"]["attributes"]["uploadOperations"], data)
    status, payload = request(
        "PATCH",
        f"/v2/inAppPurchaseImages/{image_id}",
        {"data": {"type": "inAppPurchaseImages", "id": image_id, "attributes": {"uploaded": True}}},
    )
    if status not in (200, 204):
        raise RuntimeError(f"Promo commit {slug} failed: {status} {payload}")
    print(f"  promo image uploaded: {slug}")


def ensure_review_screenshot(iap_id):
    status, payload = request("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
    if status == 200 and payload.get("data"):
        return
    data = open(REVIEW_SCREENSHOT, "rb").read()
    body = {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileSize": len(data), "fileName": os.path.basename(REVIEW_SCREENSHOT)},
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}
            },
        }
    }
    status, payload = request("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", body)
    if status != 201:
        raise RuntimeError(f"Review screenshot reserve {iap_id} failed: {status} {payload}")
    screenshot_id = payload["data"]["id"]
    upload_operations(payload["data"]["attributes"]["uploadOperations"], data)
    status, payload = request(
        "PATCH",
        f"/v1/inAppPurchaseAppStoreReviewScreenshots/{screenshot_id}",
        {
            "data": {
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "id": screenshot_id,
                "attributes": {"uploaded": True},
            }
        },
    )
    if status not in (200, 204):
        raise RuntimeError(f"Review screenshot commit {iap_id} failed: {status} {payload}")
    print("  review screenshot uploaded")


def us_price_point(iap_id, target):
    url = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter%5Bterritory%5D=USA&limit=200"
    while url:
        status, payload = request("GET", url)
        if status != 200:
            raise RuntimeError(f"Price points {iap_id} failed: {status} {payload}")
        for item in payload.get("data", []):
            if item["attributes"].get("customerPrice") == target:
                return item["id"]
        next_url = payload.get("links", {}).get("next")
        if not next_url:
            break
        url = next_url.replace(BASE, "")
    raise RuntimeError(f"No USA price point {target} for {iap_id}")


def ensure_us_price(iap_id, target):
    status, payload = request("GET", f"/v1/inAppPurchasePriceSchedules/{iap_id}/manualPrices?limit=50")
    if status == 200 and payload.get("data"):
        return
    point_id = us_price_point(iap_id, target)
    body = {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${USA}"}]},
            },
        },
        "included": [
            {
                "type": "inAppPurchasePrices",
                "id": "${USA}",
                "attributes": {"startDate": None},
                "relationships": {
                    "inAppPurchasePricePoint": {
                        "data": {"type": "inAppPurchasePricePoints", "id": point_id}
                    },
                    "inAppPurchaseV2": {
                        "data": {"type": "inAppPurchases", "id": iap_id}
                    },
                },
            }
        ],
    }
    status, payload = request("POST", "/v1/inAppPurchasePriceSchedules", body)
    if status != 201:
        raise RuntimeError(f"US price {iap_id} failed: {status} {payload}")
    print(f"  US price {target}")


def ensure_availability(iap_id, territories):
    status, payload = request("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
    if status == 200:
        return
    body = {
        "data": {
            "type": "inAppPurchaseAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "availableTerritories": {
                    "data": [{"type": "territories", "id": t} for t in territories]
                },
                "inAppPurchase": {"data": {"id": iap_id, "type": "inAppPurchases"}},
            },
        }
    }
    status, payload = request("POST", "/v1/inAppPurchaseAvailabilities", body)
    if status != 201:
        raise RuntimeError(f"Availability {iap_id} failed: {status} {payload}")
    print("  availability: 175 territories")


def main():
    config = json.load(open("docs/app-store/iap.json", encoding="utf-8"))
    slugs = {
        "com.mrmaier.flipabulary.support.coffee": "coffee",
        "com.mrmaier.flipabulary.support.lunch": "lunch",
        "com.mrmaier.flipabulary.support.bigfan": "bigfan",
        "com.mrmaier.flipabulary.support.patron": "patron",
        "com.mrmaier.flipabulary.support.champion": "champion",
        "com.mrmaier.flipabulary.support.legend": "legend",
    }
    targets = {
        "com.mrmaier.flipabulary.support.coffee": "2.99",
        "com.mrmaier.flipabulary.support.lunch": "4.99",
        "com.mrmaier.flipabulary.support.bigfan": "7.99",
        "com.mrmaier.flipabulary.support.patron": "19.99",
        "com.mrmaier.flipabulary.support.champion": "49.99",
        "com.mrmaier.flipabulary.support.legend": "99.99",
    }
    status, payload = request("GET", "/v1/territories?limit=200")
    if status != 200:
        raise RuntimeError(f"Territories failed: {status} {payload}")
    territories = [item["id"] for item in payload["data"]]

    current = products()
    for product_id, slug in slugs.items():
        item = current.get(product_id)
        if not item:
            raise RuntimeError(f"Missing product {product_id}")
        iap_id = item["id"]
        version = version_for(iap_id)
        print(f"{item['attributes']['name']} {product_id} ({iap_id})")
        ensure_promo(version["id"], slug)
        ensure_review_screenshot(iap_id)
        ensure_us_price(iap_id, targets[product_id])
        ensure_availability(iap_id, territories)
        status, refreshed = request("GET", f"/v2/inAppPurchases/{iap_id}")
        print(f"  state: {refreshed['data']['attributes']['state']}")

    print("done")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
