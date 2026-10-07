package org.miniarino.desktop;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
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

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
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
    private static final java.util.concurrent.ExecutorService SETUP_EXECUTOR = java.util.concurrent.Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private LinuxRuntime linuxRuntime;
    private volatile String latestStartupFailure = "No startup failure recorded.";

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

        root.addView(button("Start MiniAriño desktop", v -> installAndLaunchXfceDesktop()));
        root.addView(button("Stop desktop", v -> stopXServer()));
        status = new TextView(this);
        status.setText(linuxRuntime.isReady()
                ? "Debian ARM64 is ready in MiniAriño private storage. Start the desktop to install or open XFCE."
                : "MiniAriño prepares its embedded display and private Debian ARM64 desktop on first use.");
        status.setTextSize(13);
        status.setTextColor(0xff526174);
        status.setPadding(0, dp(4), 0, dp(8));
        root.addView(status);
        root.addView(button("Copy/share diagnostics", v -> showDiagnosticOptions()));

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

    private boolean startEmbeddedXServer() {
        try {
            File tmp = linuxRuntime.displayTempDir();
            if (!tmp.exists() && !tmp.mkdirs()) throw new IOException("Could not prepare Debian /tmp for the built-in display");
            File xkb = linuxRuntime.xkbConfigDir();
            if (!xkb.isDirectory()) throw new IOException("Keyboard/display support is not installed yet. Try starting the desktop again after setup completes.");
            String apk = getApplicationInfo().sourceDir;
            synchronized (HomeActivity.class) {
                if (xServerProcess == null || !isAlive(xServerProcess)) {
                    File serverLog = new File(getFilesDir(), "x11-server.log");
                    ProcessBuilder pb = new ProcessBuilder("/system/bin/app_process", "/", "--nice-name=miniarino-x11",
                            "com.termux.x11.CmdEntryPoint", ":0");
                    pb.environment().put("CLASSPATH", apk);
                    pb.environment().put("LD_LIBRARY_PATH", getApplicationInfo().nativeLibraryDir);
                    pb.environment().put("TMPDIR", tmp.getAbsolutePath());
                    pb.environment().put("XKB_CONFIG_ROOT", xkb.getAbsolutePath());
                    pb.redirectErrorStream(true);
                    pb.redirectOutput(serverLog);
                    xServerProcess = pb.start();
                }
            }
            mainHandler.post(() -> { if (status != null) status.setText("MiniAriño's built-in display server is starting."); });
            return true;
        } catch (Exception e) {
            latestStartupFailure = "The built-in display server could not start: " + safeMessage(e);
            mainHandler.post(() -> {
                if (status != null) status.setText(conciseMessage(latestStartupFailure) + " You are still on the MiniAriño home screen. Use Copy/share diagnostics for details.");
                Toast.makeText(HomeActivity.this, "Desktop startup failed; MiniAriño home remains available", Toast.LENGTH_LONG).show();
            });
            return false;
        }
    }

    private void openReadyDesktopDisplay() {
        try {
            Intent display = new Intent();
            display.setClassName(getPackageName(), "com.termux.x11.MainActivity");
            display.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
            startActivity(display);
        } catch (Exception e) {
            if (status != null) status.setText("XFCE is running, but MiniAriño could not open its built-in display: " + e.getMessage());
        }
    }

    private void installAndLaunchXfceDesktop() {
        synchronized (HomeActivity.class) {
            if (desktopSetupInProgress) {
                status.setText("MiniAriño is preparing the desktop. Please wait.");
                return;
            }
            if (linuxDesktopProcess != null && isAlive(linuxDesktopProcess)) {
                status.setText("XFCE is ready; opening the MiniAriño desktop display.");
                openReadyDesktopDisplay();
                return;
            }
            desktopSetupInProgress = true;
        }
        status.setText("Preparing MiniAriño's private Debian desktop and display support. First start downloads Debian ARM64 and installs XFCE; this can take several minutes. The desktop display opens only after the session is ready.");
        SETUP_EXECUTOR.execute(() -> {
            Process process = null;
            File logFile = new File(getFilesDir(), "xfce-desktop.log");
            try {
                linuxRuntime.provision(message -> mainHandler.post(() -> { if (status != null) status.setText(message); }));
                mainHandler.post(() -> { if (status != null) status.setText("Installing XFCE and keyboard data needed by MiniAriño's built-in display…"); });
                File preparationLog = new File(getFilesDir(), "xfce-prepare.log");
                Process preparation = linuxRuntime.prepareXfceDesktop(preparationLog);
                linuxRuntime.awaitXfcePreparation(preparation, preparationLog);
                if (!startEmbeddedXServer()) throw new IOException(latestStartupFailure);
                Thread.sleep(2500L);
                synchronized (HomeActivity.class) {
                    if (xServerProcess == null || !isAlive(xServerProcess)) {
                        int exit = xServerProcess == null ? -1 : exitCode(xServerProcess);
                        throw new IOException("MiniAriño's built-in display server exited during startup (code " + exit + "). " + tail(new File(getFilesDir(), "x11-server.log"), 3072));
                    }
                }
                process = linuxRuntime.startXfceDesktop(logFile);
                synchronized (HomeActivity.class) { linuxDesktopProcess = process; }
                mainHandler.post(() -> { if (status != null) status.setText("Installing/verifying XFCE packages and starting the session on Lorie :0. Waiting for the XFCE session manager and desktop applications… log: xfce-desktop.log."); });
                linuxRuntime.awaitXfceSession(process, logFile);
                Process running = process;
                mainHandler.post(() -> {
                    if (status != null && isAlive(running)) status.setText("MiniAriño XFCE desktop is ready. The built-in display is opening.");
                    if (isAlive(running)) openReadyDesktopDisplay();
                });
                int exit = process.waitFor();
                synchronized (HomeActivity.class) { if (linuxDesktopProcess == process) linuxDesktopProcess = null; }
                mainHandler.post(() -> { if (status != null) status.setText("XFCE desktop session ended (exit code " + exit + "). Start it again with the desktop button; details are in xfce-desktop.log."); });
            } catch (Exception e) {
                if (process != null && isAlive(process)) process.destroy();
                synchronized (HomeActivity.class) { if (linuxDesktopProcess == process) linuxDesktopProcess = null; }
                final String failure = safeMessage(e);
                latestStartupFailure = failure;
                mainHandler.post(() -> {
                    if (status != null) status.setText("MiniAriño desktop did not start: " + conciseMessage(failure) + " You are still on the MiniAriño home screen. Tap Copy/share diagnostics for details.");
                    Toast.makeText(HomeActivity.this, "Desktop startup failed; MiniAriño home remains available", Toast.LENGTH_LONG).show();
                });
            } finally {
                synchronized (HomeActivity.class) { desktopSetupInProgress = false; }
            }
        });
    }

    private void showDiagnosticOptions() {
        new AlertDialog.Builder(this)
                .setTitle("MiniAriño startup diagnostics")
                .setMessage("Choose how to send the current startup details. The logs stay inside MiniAriño unless you choose to share them.")
                .setNegativeButton("Cancel", null)
                .setNeutralButton("Share", (dialog, which) -> shareDiagnostics())
                .setPositiveButton("Copy", (dialog, which) -> copyDiagnostics())
                .show();
    }

    private String diagnosticText() {
        StringBuilder text = new StringBuilder();
        text.append("MiniAriño desktop diagnostics\nFailure: ").append(latestStartupFailure).append("\n");
        text.append("Android SDK: ").append(android.os.Build.VERSION.SDK_INT).append("\n");
        text.append("ABI: ").append(android.os.Build.SUPPORTED_ABIS.length == 0 ? "unknown" : android.os.Build.SUPPORTED_ABIS[0]).append("\n");
        appendLog(text, "X server", new File(getFilesDir(), "x11-server.log"));
        appendLog(text, "XFCE preparation", new File(getFilesDir(), "xfce-prepare.log"));
        appendLog(text, "XFCE session", new File(getFilesDir(), "xfce-desktop.log"));
        return text.toString();
    }

    private static void appendLog(StringBuilder target, String label, File file) {
        target.append("\n--- ").append(label).append(" ---\n");
        target.append(file.isFile() ? tail(file, 4096) : "No log file was created.").append("\n");
    }

    private static String tail(File file, int maximumBytes) {
        try (FileInputStream in = new FileInputStream(file)) {
            long skip = Math.max(0L, file.length() - maximumBytes);
            while (skip > 0) { long n = in.skip(skip); if (n <= 0) break; skip -= n; }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[1024]; int count;
            while ((count = in.read(buffer)) >= 0) out.write(buffer, 0, count);
            return new String(out.toByteArray(), StandardCharsets.UTF_8).trim();
        } catch (IOException e) { return "Could not read this log: " + safeMessage(e); }
    }

    private void copyDiagnostics() {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) clipboard.setPrimaryClip(ClipData.newPlainText("MiniAriño diagnostics", diagnosticText()));
        Toast.makeText(this, "Diagnostics copied", Toast.LENGTH_SHORT).show();
    }

    private void shareDiagnostics() {
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_SUBJECT, "MiniAriño desktop startup diagnostics");
        send.putExtra(Intent.EXTRA_TEXT, diagnosticText());
        startActivity(Intent.createChooser(send, "Share MiniAriño diagnostics"));
    }

    private static String safeMessage(Exception exception) {
        String message = exception.getMessage();
        return message == null || message.trim().isEmpty() ? exception.getClass().getSimpleName() : message;
    }

    private static String conciseMessage(String message) {
        String concise = message == null ? "Desktop startup failed." : message.replaceAll("\\s+", " ").trim();
        return concise.length() > 180 ? concise.substring(0, 177) + "…" : concise;
    }

    private static int exitCode(Process process) {
        try { return process.exitValue(); } catch (IllegalThreadStateException running) { return -1; }
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
                ? "Stopped the MiniAriño XFCE/PRoot session and embedded display server."
                : "No MiniAriño desktop session is currently running.");
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
