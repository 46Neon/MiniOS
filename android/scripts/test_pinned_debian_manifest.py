#!/usr/bin/env python3
"""Offline regression test for the pinned Debian ARM64 OCI manifest gate."""
import base64
import copy
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "scripts/debian-arm64-manifest.fixture.json"
RUNTIME = ROOT / "app/src/main/java/org/miniarino/desktop/LinuxRuntime.java"
ACTIVITY = ROOT / "app/src/main/java/org/miniarino/desktop/HomeActivity.java"
X11_PATCH = ROOT / "scripts/prepare_x11.py"
MANIFEST_SHA = "sha256:a1b86db52ce3daef089e45aabe36dfec4091f82464c25c1fdcf03de197cbe82a"
CONFIG_SHA = "sha256:2a64693fa3d2d9c0fd20e6e74c9001aa672a1c081fce5178d104ef160231c409"
LAYER_SHA = "sha256:c75f989a229d12b2d2613a5997de9ff3546f664c22da9248720033a2410220f6"
DIFF_ID = "sha256:dca69811453d69d10b6c0345a5c49147162abe20a2f77802d66efc60667949ea"
LAYER_SIZE = 28137179


def validate(manifest):
    if manifest.get("mediaType") != "application/vnd.oci.image.manifest.v1+json":
        raise ValueError("manifest mediaType")
    config = manifest.get("config", {})
    if config.get("mediaType") != "application/vnd.oci.image.config.v1+json":
        raise ValueError("config mediaType")
    encoded = config.get("data", "")
    config_bytes = base64.b64decode(encoded, validate=True)
    if config.get("digest") != CONFIG_SHA or config.get("size") != 468:
        raise ValueError("config descriptor")
    if len(config_bytes) != 468 or "sha256:" + hashlib.sha256(config_bytes).hexdigest() != CONFIG_SHA:
        raise ValueError("config payload digest/size")
    image = json.loads(config_bytes)
    if (image.get("os"), image.get("architecture"), image.get("variant")) != ("linux", "arm64", "v8"):
        raise ValueError("platform")
    rootfs = image.get("rootfs", {})
    if rootfs.get("type") != "layers" or rootfs.get("diff_ids") != [DIFF_ID]:
        raise ValueError("rootfs diff ID")
    layers = manifest.get("layers")
    if not isinstance(layers, list) or len(layers) != 1:
        raise ValueError(f"layer count: {len(layers) if isinstance(layers, list) else 'missing'}")
    layer = layers[0]
    if layer.get("mediaType") != "application/vnd.oci.image.layer.v1.tar+gzip":
        raise ValueError("layer mediaType")
    if layer.get("digest") != LAYER_SHA or layer.get("size") != LAYER_SIZE:
        raise ValueError(f"layer descriptor: {layer.get('digest')} ({layer.get('size')} bytes)")


def rejects(mutated, label):
    try:
        validate(mutated)
    except (ValueError, json.JSONDecodeError):
        return
    raise SystemExit(f"Manifest regression test failed to reject {label}")


def main():
    raw = FIXTURE.read_bytes()
    if "sha256:" + hashlib.sha256(raw).hexdigest() != MANIFEST_SHA:
        raise SystemExit("Pinned fixture bytes do not match the manifest digest")
    fixture = json.loads(raw)
    validate(fixture)

    cases = []
    changed = copy.deepcopy(fixture); changed["layers"] = []; cases.append((changed, "zero layers"))
    changed = copy.deepcopy(fixture); changed["layers"].append(copy.deepcopy(changed["layers"][0])); cases.append((changed, "multiple layers"))
    changed = copy.deepcopy(fixture); changed["layers"][0]["digest"] = "sha256:" + "0" * 64; cases.append((changed, "wrong layer digest"))
    changed = copy.deepcopy(fixture); changed["layers"][0]["size"] += 1; cases.append((changed, "wrong layer size"))
    changed = copy.deepcopy(fixture); changed["layers"][0]["mediaType"] = "application/octet-stream"; cases.append((changed, "wrong layer media type"))
    changed = copy.deepcopy(fixture); payload = json.loads(base64.b64decode(changed["config"]["data"])); payload["architecture"] = "amd64"; changed["config"]["data"] = base64.b64encode(json.dumps(payload, separators=(",", ":")).encode()).decode(); cases.append((changed, "wrong architecture"))
    for mutated, label in cases:
        rejects(mutated, label)

    runtime = RUNTIME.read_text(encoding="utf-8")
    for marker in ("verifyPinnedManifestDocument(bytes.toByteArray())", "verifyManifestContents(manifest)", "Debian image platform mismatch", "layer count mismatch", "layer[0] mismatch", 'String expectedLayerDigest = "sha256:" + ROOTFS_LAYER_SHA256;', "ROOTFS_CONFIG_SHA256", "ROOTFS_DIFF_ID"):
        if marker not in runtime:
            raise SystemExit("Android manifest verifier lacks tested check/diagnostic: " + marker)
    activity = ACTIVITY.read_text(encoding="utf-8")
    ready = activity.index("linuxRuntime.awaitXfceSession(process, logFile)")
    launch = activity.index("openReadyDesktopDisplay();", ready)
    failure = activity.index("You are still on the MiniAriño home screen", ready)
    if not ready < launch or failure < ready:
        raise SystemExit("MiniAriño must open its embedded display only after readiness and stay home on failure")
    if "startActivity(display)" not in activity or '"com.termux.x11.MainActivity"' not in activity:
        raise SystemExit("The display activity should remain packaged and launched internally by MiniAriño")
    x11_patch = X11_PATCH.read_text(encoding="utf-8")
    if '<string name="lorie_app_name">MiniAriño Desktop</string>' not in x11_patch or '<string name="not_connected">MiniAriño Desktop</string>' not in x11_patch:
        raise SystemExit("Embedded display activity must use MiniAriño branding rather than the separate X11 app label")
    print("Pinned Debian ARM64 OCI fixture digest, config, platform and layer verified; mismatch regressions rejected.")
    print("Desktop launch is readiness-gated; failed startup keeps MiniAriño home visible.")


if __name__ == "__main__":
    main()
