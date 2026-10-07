package org.miniarino.desktop;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
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

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
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

        LinearLayout displayActions = new LinearLayout(this);
        displayActions.setOrientation(LinearLayout.HORIZONTAL);
        displayActions.addView(button("Start / open X11", v -> openDisplay()), new LinearLayout.LayoutParams(0, -2, 1));
        displayActions.addView(button("Stop X server", v -> stopXServer()), new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(displayActions);
        status = new TextView(this);
        status.setText("X11 is embedded. A Linux root filesystem and desktop session are not installed yet.");
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

    private void openDisplay() {
        try {
            File tmp = new File(getFilesDir(), "tmp");
            if (!tmp.exists() && !tmp.mkdirs()) throw new IOException("Unable to prepare X11 temporary directory");
            String apk = getApplicationInfo().sourceDir;
            synchronized (HomeActivity.class) {
                if (xServerProcess == null || !isAlive(xServerProcess)) {
                    ProcessBuilder pb = new ProcessBuilder("/system/bin/app_process", "/", "--nice-name=miniarino-x11",
                            "com.termux.x11.CmdEntryPoint", ":0");
                    pb.environment().put("CLASSPATH", apk);
                    pb.environment().put("LD_LIBRARY_PATH", getApplicationInfo().nativeLibraryDir);
                    pb.environment().put("TMPDIR", tmp.getAbsolutePath());
                    pb.redirectErrorStream(true);
                    xServerProcess = pb.start();
                }
            }
            Intent display = new Intent();
            display.setClassName(getPackageName(), "com.termux.x11.MainActivity");
            display.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            startActivity(display);
            status.setText("Started embedded Lorie X server process and opened its display window. No Linux desktop session is installed yet.");
        } catch (Exception e) {
            status.setText("Could not start the embedded X server: " + e.getMessage());
            Toast.makeText(this, "X11 startup failed; see status above", Toast.LENGTH_LONG).show();
        }
    }

    private static boolean isAlive(Process process) {
        try { process.exitValue(); return false; }
        catch (IllegalThreadStateException running) { return true; }
    }

    private void stopXServer() {
        synchronized (HomeActivity.class) {
            if (xServerProcess == null || !isAlive(xServerProcess)) {
                xServerProcess = null;
                status.setText("No MiniAriño X server process is currently tracked.");
                return;
            }
            xServerProcess.destroy();
            xServerProcess = null;
        }
        status.setText("Sent a stop signal to the X server process started by MiniAriño.");
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
