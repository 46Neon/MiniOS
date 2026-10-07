package org.miniarino.desktop;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.view.ViewGroup;
import android.system.Os;
import android.util.Log;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

/** Verifies the installed launcher and a real PRoot guest process on supported Android APIs. */
@RunWith(AndroidJUnit4.class)
public final class LinuxRuntimeExecInstrumentedTest {
    private static final String TAG = "MiniArinoExecTest";
    private static final String SUCCESS = "MINIARINO_PROOT_GUEST_OK";
    private static final String KNOWN_LINKER_WARNING =
            "WARNING: linker: Warning: failed to find generated linker configuration from \"/linkerconfig/ld.config.txt\"";

    @Test(timeout = 30000L)
    public void launcherOpensTheRealAppActivity() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertTrue("Supported Android compatibility tests start at API 26", Build.VERSION.SDK_INT >= 26);
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        assertNotNull("The test package must expose its app launcher", launch);
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        Activity activity = InstrumentationRegistry.getInstrumentation().startActivitySync(launch);
        try {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync();
            assertEquals("Launcher must open MiniAriño's actual home screen",
                    HomeActivity.class.getName(), activity.getClass().getName());
            assertTrue("Home screen must inflate visible application content",
                    ((ViewGroup) activity.findViewById(android.R.id.content)).getChildCount() > 0);
        } finally {
            activity.finish();
        }
        Log.i(TAG, "PASS: launcher opened MiniAriño on Android API " + Build.VERSION.SDK_INT);
    }

    @Test(timeout = 900000L)
    public void appPrivateProotExecutesGuestCommand() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        Context testAssets = InstrumentationRegistry.getInstrumentation().getContext();
        assertEquals("The isolated debug APK must keep its side-by-side package identity",
                "org.miniarino.desktop.sdk28test", context.getPackageName());
        assertEquals("Writable app-private exec requires the legacy target SDK", 28,
                context.getApplicationInfo().targetSdkVersion);
        assertTrue("Supported Android compatibility tests start at API 26", Build.VERSION.SDK_INT >= 26);
        assertEquals("The runtime test image must be x86_64", "x86_64", Build.SUPPORTED_ABIS[0]);

        File runtime = new File(context.getFilesDir(), "proot-emulator-test");
        File bin = new File(runtime, "usr/bin");
        File lib = new File(runtime, "usr/lib");
        File loaderDir = new File(runtime, "usr/libexec/proot");
        File tmp = new File(runtime, "tmp");
        File guest = new File(runtime, "guest");
        File log = new File(runtime, "guest-smoke.log");
        mkdirs(bin); mkdirs(lib); mkdirs(loaderDir); mkdirs(tmp); mkdirs(new File(tmp, "proot"));
        mkdirs(new File(guest, "bin")); mkdirs(new File(guest, "system")); mkdirs(new File(guest, "apex"));
        mkdirs(new File(guest, "dev")); mkdirs(new File(guest, "proc"));

        copyAsset(testAssets, "proot-test-x86_64/bin/proot", new File(bin, "proot"), true);
        copyAsset(testAssets, "proot-test-x86_64/lib/libtalloc.so.2", new File(lib, "libtalloc.so.2"), false);
        copyAsset(testAssets, "proot-test-x86_64/lib/libandroid-shmem.so", new File(lib, "libandroid-shmem.so"), false);
        copyAsset(testAssets, "proot-test-x86_64/libexec/proot/loader", new File(loaderDir, "loader"), true);

        // Minimal guest root: use the emulator's same-ABI shell through explicit binds. This
        // exercises PRoot's guest exec/loader path without downloading a second distro image.
        Os.symlink("/system/bin/sh", new File(guest, "bin/sh").getAbsolutePath());
        java.util.List<String> command = new java.util.ArrayList<>();
        command.add(new File(bin, "proot").getAbsolutePath());
        java.util.Collections.addAll(command, "--link2symlink", "-0", "-r", guest.getAbsolutePath(),
                "-b", "/system:/system");
        // Android 8 does not have /apex. Bind it only on hosts where the directory exists.
        if (new File("/apex").isDirectory()) {
            java.util.Collections.addAll(command, "-b", "/apex:/apex");
        }
        java.util.Collections.addAll(command, "-b", "/dev:/dev", "-b", "/proc:/proc",
                "-w", "/", "/bin/sh", "-c", "echo " + SUCCESS);
        ProcessBuilder builder = new ProcessBuilder(command);
        builder.environment().put("LD_LIBRARY_PATH", lib.getAbsolutePath());
        builder.environment().put("PROOT_LOADER", new File(loaderDir, "loader").getAbsolutePath());
        builder.environment().put("PROOT_TMP_DIR", new File(tmp, "proot").getAbsolutePath());
        builder.environment().put("PROOT_NO_SECCOMP", "1");
        builder.environment().put("TMPDIR", tmp.getAbsolutePath());
        builder.redirectErrorStream(true);
        builder.redirectOutput(log);

        Process process = builder.start();
        FutureTask<Integer> waiter = new FutureTask<>(process::waitFor);
        Thread thread = new Thread(waiter, "miniarino-proot-emulator-smoke");
        thread.setDaemon(true);
        thread.start();
        final int exit;
        try {
            exit = waiter.get(60, TimeUnit.SECONDS);
        } catch (java.util.concurrent.TimeoutException e) {
            process.destroy();
            throw new IOException("Android PRoot guest command timed out", e);
        }
        String output = read(log).trim();
        assertEquals("PRoot host process and guest /bin/sh must exit successfully: " + output, 0, exit);
        boolean markerFound = false;
        for (String line : output.split("\\R")) {
            if (SUCCESS.equals(line)) {
                markerFound = true;
            } else {
                assertEquals("Unexpected PRoot output line", KNOWN_LINKER_WARNING, line);
            }
        }
        assertTrue("The guest shell must emit its marker as a complete output line", markerFound);
        Log.i(TAG, "PASS: x86_64 PRoot executed a guest command from an app-private root on Android API " + Build.VERSION.SDK_INT);
    }

    private static void copyAsset(Context context, String name, File target, boolean executable) throws Exception {
        try (InputStream in = context.getAssets().open(name); FileOutputStream out = new FileOutputStream(target)) {
            byte[] buffer = new byte[16384];
            int count;
            while ((count = in.read(buffer)) >= 0) out.write(buffer, 0, count);
        }
        if (executable && !target.setExecutable(true, true)) throw new IOException("Could not make private PRoot file executable");
    }

    private static void mkdirs(File path) throws IOException {
        if (!path.isDirectory() && !path.mkdirs() && !path.isDirectory()) throw new IOException("Could not create PRoot smoke-test directory");
    }

    private static String read(File file) throws IOException {
        if (!file.isFile()) return "";
        try (InputStream in = new java.io.FileInputStream(file); java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = in.read(buffer)) >= 0) out.write(buffer, 0, count);
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }
}
