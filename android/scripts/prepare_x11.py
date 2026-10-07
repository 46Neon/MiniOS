from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCHES = [
    (
        ROOT / "vendor/termux-x11/lorie/build.gradle",
        "compileSdkVersion 34",
        "compileSdk 34",
    ),
    (
        ROOT / "vendor/termux-x11/shell-loader/stub/build.gradle",
        "android.compileSdkVersion 34",
        "android.compileSdk = 34",
    ),
    (
        ROOT / "vendor/termux-x11/lorie/src/main/res/values/strings.xml",
        '<string name="lorie_app_name">&TERMUX_X11_APP_NAME;</string>',
        '<string name="lorie_app_name">MiniAriño Desktop</string>',
    ),
    (
        ROOT / "vendor/termux-x11/lorie/src/main/res/values/strings.xml",
        '<string name="not_connected">Not connected</string>',
        '<string name="not_connected">MiniAriño Desktop</string>',
    ),
]

for path, old, new in PATCHES:
    source = path.read_text()
    if new in source:
        continue  # Keep the pinned-source patch safe to rerun locally.
    if source.count(old) != 1:
        raise SystemExit(f"Pinned Termux:X11 source changed unexpectedly: {path}")
    path.write_text(source.replace(old, new, 1))
