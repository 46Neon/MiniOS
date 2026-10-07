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
    (
        ROOT / "vendor/termux-x11/lorie/src/main/java/com/termux/x11/LorieApp.java",
        """        // A platform-supplied Context can identify as the host app's package in sharedUid builds.
        Context prefsCtx = this;
        if (!BuildConfig.APPLICATION_ID.equals(getPackageName())) {
            try {
                prefsCtx = createPackageContext(BuildConfig.APPLICATION_ID, 0);
            } catch (PackageManager.NameNotFoundException e) {
                throw new RuntimeException(e);
            }
        }
""",
        """        // Preferences belong to the installed host app, including any variant applicationIdSuffix.
        Context prefsCtx = this;
""",
    ),
    (
        ROOT / "vendor/termux-x11/lorie/src/main/java/com/termux/x11/CmdEntryPoint.java",
        """    @SuppressLint({\"WrongConstant\", \"PrivateApi\"})
    private Intent createIntent() {""",
        """    static String getPackageNameForUid() {
        try {
            String[] packageNames = android.app.ActivityThread.getPackageManager().getPackagesForUid(getuid());
            if (packageNames == null || packageNames.length == 0)
                throw new IllegalStateException(\"No installed package found for the current UID\");
            return packageNames[0];
        } catch (RemoteException e) {
            throw new RuntimeException(e);
        }
    }

    @SuppressLint({\"WrongConstant\", \"PrivateApi\"})
    private Intent createIntent() {""",
    ),
    (
        ROOT / "vendor/termux-x11/lorie/src/main/java/com/termux/x11/CmdEntryPoint.java",
        "intent.setPackage(BuildConfig.APPLICATION_ID);",
        "intent.setPackage(getPackageNameForUid());",
    ),
    (
        ROOT / "vendor/termux-x11/lorie/src/main/java/com/termux/x11/LoriePreferences.java",
        "i.setPackage(BuildConfig.APPLICATION_ID);",
        "i.setPackage(CmdEntryPoint.getPackageNameForUid());",
    ),
]

for path, old, new in PATCHES:
    source = path.read_text()
    if new in source:
        continue  # Keep the pinned-source patch safe to rerun locally.
    if source.count(old) != 1:
        raise SystemExit(f"Pinned Termux:X11 source changed unexpectedly: {path}")
    path.write_text(source.replace(old, new, 1))
