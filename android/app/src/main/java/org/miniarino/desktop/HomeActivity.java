package org.miniarino.desktop;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.Comparator;

/** Small first-run host UI. Workspace operations are confined to the app sandbox. */
public final class HomeActivity extends Activity {
    private static final int REQUEST_SHARED_FOLDER = 41;
    private File workspace;
    private File current;
    private LinearLayout listing;
    private TextView pathLabel;
    private TextView status;
    private static Process xServerProcess;
    private static Process linuxDesktopProcess;
    private static boolean desktopSetupInProgress;
    private volatile String lastDesktopFailure = "";
    private static final java.util.concurrent.ExecutorService SETUP_EXECUTOR = java.util.concurrent.Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private LinuxRuntime linuxRuntime;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        linuxRuntime = new LinuxRuntime(this);
        workspace = new File(getFilesDir(), "workspace");
        if (!workspace.exists() && !workspace.mkdirs()) {
            Toast.makeText(this, "Could not create private workspace", Toast.LENGTH_LONG).show();
        }
        current = workspace;
        render();
    }

    private int dp(float v) { return (int) (v * getResources().getDisplayMetrics().density + 0.5f); }

    private Button button(String text, View.OnClickListener listener) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setOnClickListener(listener);
        return b;
    }

    private void render() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(18), dp(18), dp(12));
        root.setBackgroundColor(0xfff5f7fa);

        TextView title = new TextView(this);
        title.setText("MiniAriño");
        title.setTextSize(27);
        title.setTextColor(0xff162335);
        root.addView(title);
        TextView subtitle = new TextView(this);
        subtitle.setText("Standalone Android workspace · ARM64");
        subtitle.setTextSize(14);
        subtitle.setTextColor(0xff526174);
        root.addView(subtitle);

        root.addView(button("Install XFCE desktop + start session", v -> installAndLaunchXfceDesktop()));
        if (BuildConfig.DEBUG && Arrays.asList(android.os.Build.SUPPORTED_ABIS).contains("arm64-v8a")) {
            root.addView(button("Wayland host proof (debug only)", v -> {
                Intent proof = new Intent();
                proof.setClassName(getPackageName(), "org.miniarino.desktop.WaylandProofActivity");
                startActivity(proof);
            }));
        }
        LinearLayout diagnosticsActions = new LinearLayout(this);
        diagnosticsActions.setOrientation(LinearLayout.HORIZONTAL);
        diagnosticsActions.addView(button("Copy diagnostics", v -> copyDiagnostics()), new LinearLayout.LayoutParams(0, -2, 1));
        diagnosticsActions.addView(button("Share diagnostics", v -> shareDiagnostics()), new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(diagnosticsActions);
        root.addView(button("Stop MiniAriño session", v -> stopXServer()));
        status = new TextView(this);
        status.setText(linuxRuntime.isReady()
                ? "Debian ARM64 is installed in MiniAriño. Start the XFCE setup; the embedded display opens only after the desktop is ready."
                : "MiniAriño will prepare its private Debian ARM64 system and install XFCE on first start. No separate terminal or X11 app is needed.");
        status.setTextSize(13);
        status.setTextColor(0xff526174);
        status.setPadding(0, dp(4), 0, dp(8));
        root.addView(status);

        TextView filesTitle = new TextView(this);
        filesTitle.setText("Private folders");
        filesTitle.setTextSize(18);
        filesTitle.setTextColor(0xff162335);
        filesTitle.setPadding(0, dp(6), 0, 0);
        root.addView(filesTitle);
        pathLabel = new TextView(this);
        pathLabel.setTextSize(12);
        pathLabel.setTextColor(0xff526174);
        root.addView(pathLabel);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.addView(button("New folder", v -> createFolder()), new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("Delete empty folder", v -> deleteFolder()), new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(actions);
        root.addView(button("Choose shared folder (Android SAF)", v -> chooseSharedFolder()));

        ScrollView scroll = new ScrollView(this);
        listing = new LinearLayout(this);
        listing.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(listing);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView note = new TextView(this);
        note.setText("Files shown here stay inside MiniAriño. Shared storage is only selected through Android's folder picker.");
        note.setTextColor(0xff526174);
        note.setTextSize(12);
        note.setPadding(0, dp(8), 0, 0);
        root.addView(note);
        setContentView(root);
        refreshListing();
    }

    private void startEmbeddedXServer() throws IOException {
        File tmp = new File(getFilesDir(), "tmp");
        if (!tmp.exists() && !tmp.mkdirs()) throw new IOException("MiniAriño could not prepare its private display directory");
        File xkbRoot = new File(getFilesDir(), "linux/debian-arm64/usr/share/X11/xkb");
        if (!new File(xkbRoot, "keycodes").isDirectory()) throw new IOException("Debian keyboard data is not installed; MiniAriño could not configure the embedded display");
        File socket = new File(tmp, ".X11-unix/X0");
        synchronized (HomeActivity.class) {
            if (xServerProcess != null && isAlive(xServerProcess)) return;
            if (socket.exists() && !socket.delete()) throw new IOException("MiniAriño could not clear a stale X11 socket");
            ProcessBuilder pb = new ProcessBuilder("/system/bin/app_process", "/", "--nice-name=miniarino-x11",
                    "com.termux.x11.CmdEntryPoint", ":0");
            pb.environment().put("CLASSPATH", getApplicationInfo().sourceDir);
            pb.environment().put("LD_LIBRARY_PATH", getApplicationInfo().nativeLibraryDir);
            pb.environment().put("TMPDIR", tmp.getAbsolutePath());
            pb.environment().put("XKB_CONFIG_ROOT", xkbRoot.getAbsolutePath());
            pb.redirectErrorStream(true);
            pb.redirectOutput(new File(getFilesDir(), "x11-server.log"));
            xServerProcess = pb.start();
        }
    }

    private void awaitEmbeddedXServer() throws Exception {
        File socket = new File(getFilesDir(), "tmp/.X11-unix/X0");
        File log = new File(getFilesDir(), "x11-server.log");
        long deadline = System.currentTimeMillis() + 30000L;
        while (System.currentTimeMillis() < deadline) {
            synchronized (HomeActivity.class) {
                if (xServerProcess == null || !isAlive(xServerProcess)) {
                    throw new IOException("Embedded display server exited before opening :0. " + tail(log));
                }
            }
            if (socket.exists()) return;
            Thread.sleep(250L);
        }
        throw new IOException("Embedded display server did not create its :0 socket. " + tail(log));
    }

    private void showEmbeddedDesktop() throws Exception {
        java.util.concurrent.FutureTask<Void> task = new java.util.concurrent.FutureTask<>(() -> {
            Intent display = new Intent();
            display.setClassName(getPackageName(), "com.termux.x11.MainActivity");
            display.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            startActivity(display);
            return null;
        });
        mainHandler.post(task);
        task.get(15, java.util.concurrent.TimeUnit.SECONDS);
    }

    private void installAndLaunchXfceDesktop() {
        synchronized (HomeActivity.class) {
            if (desktopSetupInProgress || (linuxDesktopProcess != null && isAlive(linuxDesktopProcess))) {
                status.setText("XFCE installation or desktop session is already running.");
                return;
            }
            desktopSetupInProgress = true;
        }
        lastDesktopFailure = "";
        status.setText("Preparing MiniAriño's private Debian system and installing XFCE. The embedded display will open only after XFCE is ready.");
        SETUP_EXECUTOR.execute(() -> {
            Process process = null;
            File installLog = new File(getFilesDir(), "xfce-install.log");
            File logFile = new File(getFilesDir(), "xfce-desktop.log");
            try {
                linuxRuntime.provision(message -> mainHandler.post(() -> { if (status != null) status.setText(message); }));
                mainHandler.post(() -> { if (status != null) status.setText("Installing XFCE and keyboard support in MiniAriño. This may take several minutes…"); });
                linuxRuntime.installDesktopPackages(installLog);
                startEmbeddedXServer();
                mainHandler.post(() -> { if (status != null) status.setText("Starting MiniAriño's embedded display server and verifying its keyboard configuration…"); });
                awaitEmbeddedXServer();
                process = linuxRuntime.startXfceDesktop(logFile);
                synchronized (HomeActivity.class) { linuxDesktopProcess = process; }
                mainHandler.post(() -> { if (status != null) status.setText("Starting XFCE on the embedded display. MiniAriño will open it after the session manager, terminal and file manager are ready…"); });
                linuxRuntime.awaitXfceSession(process, logFile);
                showEmbeddedDesktop();
                Process running = process;
                mainHandler.post(() -> { if (status != null && isAlive(running)) status.setText("MiniAriño XFCE is ready on its embedded display. The session includes a terminal and file manager."); });
                int exit = process.waitFor();
                synchronized (HomeActivity.class) { if (linuxDesktopProcess == process) linuxDesktopProcess = null; }
                mainHandler.post(() -> { if (status != null) status.setText("MiniAriño desktop session ended (exit code " + exit + "). Tap the desktop button to start it again."); });
            } catch (Exception e) {
                if (process != null && isAlive(process)) process.destroy();
                synchronized (HomeActivity.class) {
                    if (linuxDesktopProcess == process) linuxDesktopProcess = null;
                    if (xServerProcess != null && isAlive(xServerProcess)) xServerProcess.destroy();
                    xServerProcess = null;
                }
                final String failure = conciseFailure(e);
                lastDesktopFailure = failure;
                mainHandler.post(() -> {
                    if (status != null) status.setText("MiniAriño desktop did not start: " + failure + ". Copy or share diagnostics for help.");
                    Toast.makeText(HomeActivity.this, "MiniAriño could not start the desktop", Toast.LENGTH_LONG).show();
                });
            } finally {
                synchronized (HomeActivity.class) { desktopSetupInProgress = false; }
            }
        });
    }

    private static boolean isAlive(Process process) {
        try { process.exitValue(); return false; }
        catch (IllegalThreadStateException running) { return true; }
    }

    private void stopXServer() {
        boolean hadTrackedProcess = false;
        synchronized (HomeActivity.class) {
            if (linuxDesktopProcess != null && isAlive(linuxDesktopProcess)) {
                linuxDesktopProcess.destroy();
                hadTrackedProcess = true;
            }
            linuxDesktopProcess = null;
            if (xServerProcess != null && isAlive(xServerProcess)) {
                xServerProcess.destroy();
                hadTrackedProcess = true;
            }
            xServerProcess = null;
        }
        status.setText(hadTrackedProcess
                ? "Sent stop signals to the MiniAriño XFCE/PRoot session and embedded X server."
                : "No MiniAriño X server or XFCE session process is currently tracked.");
    }

    private static String conciseFailure(Throwable error) {
        Throwable current = error;
        while (current.getCause() != null && (current.getMessage() == null || current.getMessage().trim().isEmpty())) current = current.getCause();
        String message = current.getMessage();
        if (message == null || message.trim().isEmpty()) message = current.getClass().getSimpleName();
        message = message.replaceAll("\\s+", " ").trim();
        return message.length() > 280 ? message.substring(0, 277) + "…" : message;
    }

    private String collectDiagnostics() {
        StringBuilder text = new StringBuilder("MiniAriño desktop diagnostics\n");
        String version = "unknown";
        try { version = getPackageManager().getPackageInfo(getPackageName(), 0).versionName; } catch (Exception ignored) { }
        text.append("App version: ").append(version).append('\n');
        text.append("Android API: ").append(android.os.Build.VERSION.SDK_INT).append("; target SDK: ")
                .append(getApplicationInfo().targetSdkVersion).append('\n');
        text.append("ABI: ").append(android.os.Build.SUPPORTED_ABIS.length == 0 ? "unknown" : android.os.Build.SUPPORTED_ABIS[0]).append('\n');
        text.append("Current status: ").append(status == null ? "not available" : status.getText()).append('\n');
        if (!lastDesktopFailure.isEmpty()) text.append("Last failure: ").append(lastDesktopFailure).append('\n');
        appendLogTail(text, "xfce-install.log");
        appendLogTail(text, "xfce-desktop.log");
        appendLogTail(text, "x11-server.log");
        return text.toString();
    }

    private void appendLogTail(StringBuilder text, String name) {
        File log = new File(getFilesDir(), name);
        text.append("\n--- ").append(name).append(" (last 4 KiB) ---\n");
        if (!log.isFile()) { text.append("(not created)\n"); return; }
        try (java.io.RandomAccessFile input = new java.io.RandomAccessFile(log, "r")) {
            long start = Math.max(0L, input.length() - 4096L);
            input.seek(start);
            byte[] bytes = new byte[(int) (input.length() - start)];
            input.readFully(bytes);
            text.append(new String(bytes, java.nio.charset.StandardCharsets.UTF_8)).append('\n');
        } catch (IOException e) { text.append("(could not read diagnostic log)\n"); }
    }

    private String tail(File file) {
        if (!file.isFile()) return "No display log was produced.";
        try (java.io.RandomAccessFile input = new java.io.RandomAccessFile(file, "r")) {
            long start = Math.max(0L, input.length() - 2048L);
            input.seek(start);
            byte[] bytes = new byte[(int) (input.length() - start)];
            input.readFully(bytes);
            return new String(bytes, java.nio.charset.StandardCharsets.UTF_8).replace('\n', ' ').trim();
        } catch (IOException e) { return "Could not read display log."; }
    }

    private void copyDiagnostics() {
        android.content.ClipboardManager clipboard = (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(android.content.ClipData.newPlainText("MiniAriño diagnostics", collectDiagnostics()));
        Toast.makeText(this, "Diagnostics copied", Toast.LENGTH_SHORT).show();
    }

    private void shareDiagnostics() {
        Intent share = new Intent(Intent.ACTION_SEND);
        share.setType("text/plain");
        share.putExtra(Intent.EXTRA_SUBJECT, "MiniAriño desktop diagnostics");
        share.putExtra(Intent.EXTRA_TEXT, collectDiagnostics());
        startActivity(Intent.createChooser(share, "Share MiniAriño diagnostics"));
    }

    private boolean isWorkspacePath(File file) {
        try {
            String root = workspace.getCanonicalPath() + File.separator;
            String candidate = file.getCanonicalPath();
            return candidate.equals(workspace.getCanonicalPath()) || candidate.startsWith(root);
        } catch (IOException e) { return false; }
    }

    private void refreshListing() {
        if (listing == null) return;
        pathLabel.setText(current.equals(workspace) ? "/workspace" : "/workspace/" + workspace.toURI().relativize(current.toURI()).getPath());
        listing.removeAllViews();
        if (!current.equals(workspace)) {
            Button up = button("↑  Parent folder", v -> {
                File parent = current.getParentFile();
                if (parent != null && isWorkspacePath(parent)) { current = parent; refreshListing(); }
            });
            listing.addView(up);
        }
        File[] children = current.listFiles(f -> f.isDirectory() && isWorkspacePath(f));
        if (children == null) children = new File[0];
        Arrays.sort(children, Comparator.comparing(File::getName, String.CASE_INSENSITIVE_ORDER));
        if (children.length == 0) {
            TextView empty = new TextView(this);
            empty.setText("No folders here yet.");
            empty.setGravity(Gravity.CENTER_VERTICAL);
            empty.setPadding(dp(8), dp(18), dp(8), dp(18));
            listing.addView(empty);
        }
        for (File child : children) {
            Button row = button("📁  " + child.getName(), v -> { current = child; refreshListing(); });
            row.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
            listing.addView(row);
        }
    }

    private void createFolder() {
        final android.widget.EditText input = new android.widget.EditText(this);
        input.setSingleLine(true);
        input.setHint("Folder name");
        new AlertDialog.Builder(this).setTitle("Create a private folder").setView(input)
                .setNegativeButton("Cancel", null).setPositiveButton("Create", (d, w) -> {
                    String name = input.getText().toString().trim();
                    if (!validName(name)) { Toast.makeText(this, "Use a simple folder name without slashes", Toast.LENGTH_SHORT).show(); return; }
                    File target = new File(current, name);
                    if (!isWorkspacePath(target) || !target.mkdir()) Toast.makeText(this, "Could not create folder (it may already exist)", Toast.LENGTH_SHORT).show();
                    refreshListing();
                }).show();
    }

    private boolean validName(String name) {
        return name.length() > 0 && !name.equals(".") && !name.equals("..") && name.indexOf('/') < 0 && name.indexOf('\\') < 0 && name.indexOf('\0') < 0;
    }

    private void deleteFolder() {
        if (current.equals(workspace)) {
            Toast.makeText(this, "Select a child folder first; the workspace root cannot be deleted", Toast.LENGTH_SHORT).show();
            return;
        }
        File selected = current;
        new AlertDialog.Builder(this).setTitle("Delete empty folder?")
                .setMessage("Only this empty folder will be removed. Files and non-empty folders are never deleted here.")
                .setNegativeButton("Cancel", null).setPositiveButton("Delete", (d, w) -> {
                    if (!isWorkspacePath(selected) || !selected.isDirectory() || !selected.delete()) {
                        Toast.makeText(this, "Folder is not empty or could not be deleted", Toast.LENGTH_SHORT).show();
                    } else {
                        current = selected.getParentFile();
                    }
                    refreshListing();
                }).show();
    }

    private void chooseSharedFolder() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(intent, REQUEST_SHARED_FOLDER);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == REQUEST_SHARED_FOLDER && result == RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri != null) {
                int flags = data.getFlags() & (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                try { getContentResolver().takePersistableUriPermission(uri, flags); } catch (SecurityException ignored) { }
                Toast.makeText(this, "Shared folder permission saved through Android's picker", Toast.LENGTH_LONG).show();
            }
        }
    }
}
