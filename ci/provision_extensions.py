#!/usr/bin/env python3
"""
Create + install App Store provisioning profiles for the app's extensions
(widget, watch) so the Release archive can sign them, mirroring the main-app
flow in ios.yml. Reuses the JWT the signing step already wrote to
/tmp/asc_jwt.txt and the freshly-created Distribution certificate.

For each extension bundle id it: looks up (or registers) the bundle id,
deletes any existing App Store profile with the target name, creates a new one
bound to the Distribution cert, and installs it into the runner's Provisioning
Profiles directory. App Groups / other capabilities come from the App ID as
configured in the portal, so the minted profile carries them automatically.

Writes every bundleId=profileName pair (including the main app) to
/tmp/ext_profiles so the ExportOptions step can build the full map.

Usage:
    python3 ci/provision_extensions.py \
        --main "com.aidanmcconnon.currents=Currents AppStore Manual" \
        --ext  "com.aidanmcconnon.currents.widgets=Currents Widgets AppStore Manual" \
        --ext  "com.aidanmcconnon.currents.watchkitapp=Currents Watch AppStore Manual"
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import plistlib
import subprocess
import sys
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def api(method: str, path: str, jwt: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {jwt}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"API {method} {path} failed: {e.code} {detail}")


def bundle_resource_id(bundle_id: str, jwt: str) -> str:
    from urllib.parse import quote
    res = api("GET", f"/bundleIds?filter%5Bidentifier%5D={quote(bundle_id)}", jwt)
    data = res.get("data", [])
    if data:
        return data[0]["id"]
    # Register it if the user hasn't (name must be alphanumeric+spaces).
    name = "Currents " + bundle_id.rsplit(".", 1)[-1].capitalize()
    res = api("POST", "/bundleIds", jwt, {
        "data": {"type": "bundleIds", "attributes": {
            "identifier": bundle_id, "name": name, "platform": "IOS"}}})
    return res["data"]["id"]


def delete_profiles_named(name: str, jwt: str) -> None:
    res = api("GET", "/profiles?filter%5BprofileType%5D=IOS_APP_STORE&limit=200", jwt)
    for p in res.get("data", []):
        if p["attributes"].get("name") == name:
            api("DELETE", f"/profiles/{p['id']}", jwt)


def create_and_install(bundle_id: str, profile_name: str, cert_id: str, jwt: str) -> None:
    resource = bundle_resource_id(bundle_id, jwt)
    delete_profiles_named(profile_name, jwt)
    res = api("POST", "/profiles", jwt, {
        "data": {
            "type": "profiles",
            "attributes": {"name": profile_name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"id": resource, "type": "bundleIds"}},
                "certificates": {"data": [{"id": cert_id, "type": "certificates"}]},
            },
        }
    })
    content = base64.b64decode(res["data"]["attributes"]["profileContent"])
    tmp = "/tmp/ext_profile.mobileprovision"
    with open(tmp, "wb") as f:
        f.write(content)
    decoded = subprocess.run(["security", "cms", "-D", "-i", tmp],
                             capture_output=True, check=True).stdout
    uuid = plistlib.loads(decoded)["UUID"]
    dest = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(dest, exist_ok=True)
    with open(f"{dest}/{uuid}.mobileprovision", "wb") as f:
        f.write(content)
    print(f"Installed profile '{profile_name}' for {bundle_id} (UUID {uuid})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--main", required=True, help="bundleId=ProfileName for the main app (already installed)")
    ap.add_argument("--ext", action="append", default=[], help="bundleId=ProfileName per extension")
    args = ap.parse_args()

    jwt = open("/tmp/asc_jwt.txt").read().strip()

    certs = api("GET", "/certificates?filter%5BcertificateType%5D=DISTRIBUTION", jwt)
    cert_ids = [c["id"] for c in certs.get("data", [])]
    if not cert_ids:
        raise SystemExit("No Distribution certificate found")
    cert_id = cert_ids[0]

    pairs = [args.main] + args.ext
    with open("/tmp/ext_profiles", "w") as out:
        for pair in pairs:
            bundle_id, _, profile_name = pair.partition("=")
            if pair != args.main:
                create_and_install(bundle_id, profile_name, cert_id, jwt)
            out.write(f"{bundle_id}={profile_name}\n")
    print("Wrote /tmp/ext_profiles")


if __name__ == "__main__":
    main()
