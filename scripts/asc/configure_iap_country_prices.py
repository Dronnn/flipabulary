#!/usr/bin/env python3
"""Apply rich / middle / poor country pricing to all Flipabulary support tips."""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6831894963"

TOKEN = subprocess.check_output(
    ["ruby", os.path.expanduser("~/.config/opencode/scripts/asc-jwt.rb")],
    text=True,
).strip()

GROUPS = {
    "rich": [
        "CHE", "NOR", "DNK", "SWE", "DEU", "GBR", "CAN", "AUS", "NZL",
        "JPN", "KOR", "SGP", "HKG", "ARE", "ISR", "QAT", "KWT", "SAU",
    ],
    "upper": [
        "BRA", "MEX", "TUR", "ZAF", "MYS", "THA", "COL", "CHN",
        "ARG", "ROU", "BGR", "SRB", "KAZ",
    ],
    "lower": [
        "IND", "IDN", "VNM", "PHL", "EGY", "MAR", "LTU", "ARM",
        "UKR", "BLR", "GEO", "AZE", "MDA", "ALB", "MKD", "BIH", "MNE",
    ],
    "low": [
        "KEN", "NGA", "PAK", "BGD", "ETH", "UGA", "TZA", "GHA",
        "SEN", "CIV", "CMR", "ZMB", "ZWE", "MOZ", "RWA",
    ],
}

PRODUCTS = {
    "com.mrmaier.flipabulary.support.coffee": {
        "base": "2.99", "upper": "1.99", "lower": "0.99", "low": "0.49",
    },
    "com.mrmaier.flipabulary.support.lunch": {
        "base": "4.99", "upper": "3.99", "lower": "1.99", "low": "0.99",
    },
    "com.mrmaier.flipabulary.support.bigfan": {
        "base": "7.99", "upper": "5.99", "lower": "3.99", "low": "1.99",
    },
    "com.mrmaier.flipabulary.support.patron": {
        "base": "19.99", "upper": "12.99", "lower": "7.99", "low": "4.99",
    },
    "com.mrmaier.flipabulary.support.champion": {
        "base": "49.99", "upper": "29.99", "lower": "19.99", "low": "12.99",
    },
    "com.mrmaier.flipabulary.support.legend": {
        "base": "99.99", "upper": "59.99", "lower": "39.99", "low": "24.99",
    },
}


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


def product_ids():
    status, payload = request("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=50")
    if status != 200:
        raise RuntimeError(f"List IAPs failed: {status} {payload}")
    return {item["attributes"]["productId"]: item["id"] for item in payload["data"]}


def us_price_points(iap_id):
    result = {}
    url = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter%5Bterritory%5D=USA&limit=200"
    while url:
        status, payload = request("GET", url)
        if status != 200:
            raise RuntimeError(f"Price points failed: {status} {payload}")
        for item in payload["data"]:
            price = item["attributes"].get("customerPrice")
            if price:
                result[price] = item["id"]
        next_url = payload.get("links", {}).get("next")
        url = next_url.replace(BASE, "") if next_url else None
    return result


def territory_from_point(point_id):
    try:
        padded = point_id + "=" * (-len(point_id) % 4)
        decoded = base64.urlsafe_b64decode(padded).decode()
        return json.loads(decoded).get("t")
    except Exception:
        return None


def equalizations(point_id):
    last = None
    for attempt in range(4):
        status, payload = request(
            "GET", f"/v1/inAppPurchasePricePoints/{point_id}/equalizations?limit=200"
        )
        if status == 200:
            break
        last = (status, payload)
        time.sleep(2 + attempt * 2)
    else:
        raise RuntimeError(f"Equalizations failed: {last}")
    result = {}
    for item in payload.get("data", []):
        territory = territory_from_point(item["id"])
        if territory:
            result[territory] = item["id"]
    return result


def set_schedule(iap_id, base_point, overrides):
    manual = [("USA", base_point)] + list(overrides.items())
    included = []
    used = set()
    for index, (territory, point_id) in enumerate(manual):
        if territory in used:
            continue
        used.add(territory)
        included.append(
            {
                "type": "inAppPurchasePrices",
                "id": f"${{P{index}}}",
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
        )
    body = {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {
                    "data": [
                        {"type": "inAppPurchasePrices", "id": f"${{P{index}}}"}
                        for index in range(len(included))
                    ]
                },
            },
        },
        "included": included,
    }
    status, payload = request("POST", "/v1/inAppPurchasePriceSchedules", body)
    if status != 201:
        raise RuntimeError(f"Schedule failed: {status} {payload}")
    return len(included)


def main():
    ids = product_ids()
    for product_id, targets in PRODUCTS.items():
        iap_id = ids.get(product_id)
        if not iap_id:
            raise RuntimeError(f"Missing product {product_id}")
        points = us_price_points(iap_id)
        missing = [price for price in targets.values() if price not in points]
        if missing:
            raise RuntimeError(f"Missing USA price points {missing} for {product_id}")
        base_point = points[targets["base"]]
        overrides = {}
        applied = {}
        for group, territories in GROUPS.items():
            target = targets["base"] if group == "rich" else targets[group]
            local_points = equalizations(points[target])
            for territory in territories:
                if territory in local_points and territory not in overrides:
                    overrides[territory] = local_points[territory]
                    applied[territory] = target
        count = set_schedule(iap_id, base_point, overrides)
        print(f"{product_id}: {count} manual prices")
        for territory in ["USA", "CHE", "DEU", "ARM", "GEO", "IND", "KEN", "NGA"]:
            if territory == "USA":
                print(f"  USA base ${targets['base']}")
            elif territory in applied:
                print(f"  {territory} target ${applied[territory]}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
