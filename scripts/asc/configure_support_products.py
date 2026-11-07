#!/usr/bin/env python3
"""Create Flipabulary support products and localized metadata in App Store Connect.

Idempotent: existing products, versions, and localizations are reused.
Requires a fresh JWT from ~/.config/opencode/scripts/asc-jwt.rb.
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6831894963"
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
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = response.read().decode()
            return response.status, json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        payload = error.read().decode()
        return error.code, json.loads(payload) if payload else {}


TIERS = [
    ("Coffee", "com.mrmaier.flipabulary.support.coffee"),
    ("Lunch", "com.mrmaier.flipabulary.support.lunch"),
    ("Big fan", "com.mrmaier.flipabulary.support.bigfan"),
    ("Patron", "com.mrmaier.flipabulary.support.patron"),
    ("Champion", "com.mrmaier.flipabulary.support.champion"),
    ("Legend", "com.mrmaier.flipabulary.support.legend"),
]

LOCALES = {
    "en": "en-US",
    "de": "de-DE",
    "es": "es-ES",
    "pt-BR": "pt-BR",
    "fr": "fr-FR",
    "ru": "ru",
    "pl": "pl",
    "uk": "uk",
    "zh-Hans": "zh-Hans",
    "ko": "ko",
    "ja": "ja",
    "vi": "vi",
    "it": "it",
    "nl": "nl-NL",
    "tr": "tr",
    "id": "id",
}

NAMES = {
    "Coffee": {
        "en": "Coffee", "de": "Kaffee", "es": "Café", "pt-BR": "Café",
        "fr": "Café", "ru": "Кофе", "pl": "Kawa", "uk": "Кава",
        "zh-Hans": "咖啡", "ko": "커피", "ja": "コーヒー", "vi": "Cà phê",
        "it": "Caffè", "nl": "Koffie", "tr": "Kahve", "id": "Kopi",
    },
    "Lunch": {
        "en": "Lunch", "de": "Mittagessen", "es": "Almuerzo", "pt-BR": "Almoço",
        "fr": "Déjeuner", "ru": "Обед", "pl": "Obiad", "uk": "Обід",
        "zh-Hans": "午餐", "ko": "점심", "ja": "ランチ", "vi": "Bữa trưa",
        "it": "Pranzo", "nl": "Lunch", "tr": "Öğle yemeği", "id": "Makan siang",
    },
    "Big fan": {
        "en": "Big fan", "de": "Großer Fan", "es": "Gran fan", "pt-BR": "Super fã",
        "fr": "Grand fan", "ru": "Суперфанат", "pl": "Wielki fan", "uk": "Великий фанат",
        "zh-Hans": "超级粉丝", "ko": "열혈 팬", "ja": "大ファン", "vi": "Người hâm mộ lớn",
        "it": "Grande fan", "nl": "Grote fan", "tr": "Büyük hayran", "id": "Penggemar berat",
    },
    "Patron": {
        "en": "Patron", "de": "Patron", "es": "Patrocinador", "pt-BR": "Patrono",
        "fr": "Mécène", "ru": "Патрон", "pl": "Mecenas", "uk": "Патрон",
        "zh-Hans": "赞助人", "ko": "후원자", "ja": "パトロン", "vi": "Nhà tài trợ",
        "it": "Sostenitore", "nl": "Mecenas", "tr": "Patron", "id": "Patron",
    },
    "Champion": {
        "en": "Champion", "de": "Champion", "es": "Campeón", "pt-BR": "Campeão",
        "fr": "Champion", "ru": "Чемпион", "pl": "Mistrz", "uk": "Чемпіон",
        "zh-Hans": "冠军", "ko": "챔피언", "ja": "チャンピオン", "vi": "Nhà vô địch",
        "it": "Campione", "nl": "Kampioen", "tr": "Şampiyon", "id": "Juara",
    },
    "Legend": {
        "en": "Legend", "de": "Legende", "es": "Leyenda", "pt-BR": "Lenda",
        "fr": "Légende", "ru": "Легенда", "pl": "Legenda", "uk": "Легенда",
        "zh-Hans": "传奇", "ko": "전설", "ja": "伝説", "vi": "Huyền thoại",
        "it": "Leggenda", "nl": "Legende", "tr": "Efsane", "id": "Legenda",
    },
}

DESCRIPTIONS = {
    "en": "A one-time tip. Unlocks no features.",
    "de": "Einmaliger Tipp. Keine Funktionen.",
    "es": "Propina única. No desbloquea funciones.",
    "pt-BR": "Gorjeta única. Não desbloqueia recursos.",
    "fr": "Pourboire unique. Aucune fonction.",
    "ru": "Разовые чаевые. Без новых функций.",
    "pl": "Jednorazowy napiwek. Bez funkcji.",
    "uk": "Одноразові чайові. Без нових функцій.",
    "zh-Hans": "一次性打赏，不解锁任何功能。",
    "ko": "일회성 팁. 기능은 해제되지 않습니다.",
    "ja": "一度きりのチップ。機能は解除されません。",
    "vi": "Tip một lần. Không mở khóa tính năng.",
    "it": "Mancia una tantum. Nessuna funzione.",
    "nl": "Eenmalige fooi. Geen functies vrij.",
    "tr": "Tek seferlik bahşiş. Özellik açmaz.",
    "id": "Tip sekali. Tidak membuka fitur.",
}


def list_products():
    status, payload = request("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=50")
    if status != 200:
        raise RuntimeError(f"List products failed: {status} {payload}")
    return {item["attributes"]["productId"]: item for item in payload.get("data", [])}


def list_versions(product_id):
    status, payload = request("GET", f"/v2/inAppPurchases/{product_id}/versions?limit=10")
    if status != 200:
        raise RuntimeError(f"List versions failed: {status} {payload}")
    return payload.get("data", [])


def list_localizations(version_id):
    status, payload = request("GET", f"/v1/inAppPurchaseVersions/{version_id}/localizations?limit=50")
    if status != 200:
        raise RuntimeError(f"List localizations failed: {status} {payload}")
    return {item["attributes"]["locale"]: item for item in payload.get("data", [])}


def ensure_product(reference_name, product_id):
    products = list_products()
    if product_id in products:
        return products[product_id]
    status, payload = request(
        "POST",
        "/v2/inAppPurchases",
        {
            "data": {
                "type": "inAppPurchases",
                "attributes": {
                    "name": reference_name,
                    "productId": product_id,
                    "inAppPurchaseType": "CONSUMABLE",
                    "reviewNote": "Flipabulary support tip. Consumable, repeatable, unlocks no features.",
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}}
                },
            }
        },
    )
    if status != 201:
        raise RuntimeError(f"Create {product_id} failed: {status} {payload}")
    print(f"created product {reference_name} {product_id} -> {payload['data']['id']}")
    return payload["data"]


def ensure_version(product_id):
    versions = list_versions(product_id)
    for version in versions:
        if version["attributes"]["state"] == "PREPARE_FOR_SUBMISSION":
            return version
    status, payload = request(
        "POST",
        "/v1/inAppPurchaseVersions",
        {
            "data": {
                "type": "inAppPurchaseVersions",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": product_id}}
                },
            }
        },
    )
    if status != 201:
        raise RuntimeError(f"Create version for {product_id} failed: {status} {payload}")
    print(f"created version for {product_id} -> {payload['data']['id']}")
    return payload["data"]


def ensure_localization(version_id, locale, name, description):
    localizations = list_localizations(version_id)
    if locale in localizations:
        return localizations[locale]
    status, payload = request(
        "POST",
        "/v2/inAppPurchaseLocalizations",
        {
            "data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {
                    "locale": locale,
                    "name": name,
                    "description": description,
                },
                "relationships": {
                    "version": {"data": {"type": "inAppPurchaseVersions", "id": version_id}}
                },
            }
        },
    )
    if status != 201:
        raise RuntimeError(f"Create localization {locale} failed: {status} {payload}")
    print(f"  localization {locale}: {name}")
    return payload["data"]


def main():
    result = {}
    for reference_name, product_id in TIERS:
        product = ensure_product(reference_name, product_id)
        apple_id = product["id"]
        version = ensure_version(apple_id)
        print(f"{reference_name} ({product_id}) id={apple_id} version={version['id']}")
        for language, locale in LOCALES.items():
            name = NAMES[reference_name][language]
            description = DESCRIPTIONS[language]
            if len(name) > 30:
                raise RuntimeError(f"Name too long for {locale}: {name}")
            if len(description) > 45:
                raise RuntimeError(f"Description too long for {locale}: {description}")
            ensure_localization(version["id"], locale, name, description)
        result[product_id] = {
            "appleId": apple_id,
            "versionId": version["id"],
            "referenceName": reference_name,
        }

    os.makedirs("docs/app-store", exist_ok=True)
    with open("docs/app-store/iap.json", "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote docs/app-store/iap.json")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
