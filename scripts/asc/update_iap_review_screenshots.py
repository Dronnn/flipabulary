#!/usr/bin/env python3
"""Replace each support IAP review screenshot with the correct six-tier screen."""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6831894963"
SCREENSHOTS = {
    "com.mrmaier.flipabulary.support.coffee": "docs/app-store/iap-screenshots/coffee.png",
    "com.mrmaier.flipabulary.support.lunch": "docs/app-store/iap-screenshots/lunch.png",
    "com.mrmaier.flipabulary.support.bigfan": "docs/app-store/iap-screenshots/bigfan.png",
    "com.mrmaier.flipabulary.support.patron": "docs/app-store/iap-screenshots/patron.png",
    "com.mrmaier.flipabulary.support.champion": "docs/app-store/iap-screenshots/champion.png",
    "com.mrmaier.flipabulary.support.legend": "docs/app-store/iap-screenshots/legend.png",
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
        with urllib.request.urlopen(req, timeout=120) as response:
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


def main():
    status, payload = request("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=50")
    if status != 200:
        raise RuntimeError(f"List IAPs failed: {status} {payload}")
    products = {item["attributes"]["productId"]: item["id"] for item in payload["data"]}

    for product_id, path in SCREENSHOTS.items():
        iap_id = products.get(product_id)
        if not iap_id:
            raise RuntimeError(f"Missing {product_id}")
        status, payload = request("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
        if status == 200 and payload.get("data"):
            screenshot_id = payload["data"]["id"]
            status, _ = request(
                "DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{screenshot_id}"
            )
            if status not in (200, 204):
                raise RuntimeError(f"Delete old screenshot failed: {status}")
            print(f"{product_id}: deleted old review screenshot")

        data = open(path, "rb").read()
        body = {
            "data": {
                "type": "inAppPurchaseAppStoreReviewScreenshots",
                "attributes": {
                    "fileSize": len(data),
                    "fileName": os.path.basename(path),
                },
                "relationships": {
                    "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}
                },
            }
        }
        status, payload = request("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", body)
        if status != 201:
            raise RuntimeError(f"Reserve screenshot {product_id} failed: {status} {payload}")
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
            raise RuntimeError(f"Commit screenshot {product_id} failed: {status} {payload}")
        time.sleep(1)
        status, payload = request(
            "GET", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{screenshot_id}"
        )
        state = payload.get("data", {}).get("attributes", {}).get("assetDeliveryState", {}).get("state")
        print(f"{product_id}: new review screenshot {state}")

    print("done")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
