package org.miniarino.desktop;

import android.app.Activity;
import android.os.Bundle;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Opt-in debug-only proof screen; it does not replace or launch the default Lorie/X11 route. */
public final class WaylandProofActivity extends Activity implements SurfaceHolder.Callback {
    private static final ExecutorService CLIENT_EXECUTOR = Executors.newSingleThreadExecutor();
    private static native String startHostNative(Surface surface, String socketPath);
    private static native String submitTestSurfaceNative(String socketPath, String privateTmp);
    private static native void stopHostNative();

    private final Object stateLock = new Object();
    private File privateTmp;
    private File socket;
    private TextView status;
    private Button submit;
    private boolean hostReady;

    static { System.loadLibrary("wayland_android_host"); }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        privateTmp = new File(getFilesDir(), "tmp");
        if (!privateTmp.exists() && !privateTmp.mkdirs()) {
            showFailure("Could not create app-private shared tmp directory");
            return;
        }
        socket = new File(privateTmp, "wayland-0");
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(20, 16, 20, 12);
        root.setBackgroundColor(0xfff5f7fa);
        TextView heading = new TextView(this);
        heading.setText("Wayland host proof · debug only");
        heading.setTextSize(22);
        root.addView(heading);
        TextView contract = new TextView(this);
        contract.setText("An Android-hosted libwayland server owns this real Surface. The button starts a separate libwayland client connection that submits a green wl_shm buffer over the private Unix socket. This is host protocol/surface only; no PRoot guest, physical-device claim, or input forwarding.");
        contract.setTextSize(14);
        root.addView(contract);
        SurfaceView output = new SurfaceView(this);
        output.getHolder().addCallback(this);
        root.addView(output, new LinearLayout.LayoutParams(-1, 0, 1));
        submit = new Button(this);
        submit.setText("Connect test client and submit green wl_shm surface");
        submit.setAllCaps(false);
        submit.setEnabled(false);
        submit.setOnClickListener(v -> submitTestClient());
        root.addView(submit);
        status = new TextView(this);
        status.setTextSize(13);
        status.setTextColor(0xff203246);
        status.setText("Waiting for Android Surface…");
        root.addView(status);
        Button close = new Button(this);
        close.setText("Stop proof and return");
        close.setAllCaps(false);
        close.setOnClickListener(v -> finish());
        root.addView(close);
        setContentView(root);
    }

    private void showFailure(String message) {
        TextView text = new TextView(this);
        text.setText(message);
        setContentView(text);
    }

    @Override public void surfaceCreated(SurfaceHolder holder) {
        if (socket.exists() && !socket.delete()) {
            status.setText("Could not remove stale private Wayland socket");
            return;
        }
        String result = startHostNative(holder.getSurface(), socket.getAbsolutePath());
        synchronized (stateLock) { hostReady = result.startsWith("Host ready:"); }
        status.setText(result + "\nSocket: " + socket.getAbsolutePath());
        submit.setEnabled(hostReady);
    }

    @Override public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) { }

    @Override public void surfaceDestroyed(SurfaceHolder holder) {
        synchronized (stateLock) { hostReady = false; }
        if (submit != null) submit.setEnabled(false);
        stopHostNative();
    }

    private void submitTestClient() {
        synchronized (stateLock) {
            if (!hostReady) return;
            hostReady = false;
        }
        submit.setEnabled(false);
        status.setText("Connecting a real libwayland-client to the host socket and committing wl_shm…");
        final String socketPath = socket.getAbsolutePath();
        final String tmpPath = privateTmp.getAbsolutePath();
        CLIENT_EXECUTOR.execute(() -> {
            String result = submitTestSurfaceNative(socketPath, tmpPath);
            runOnUiThread(() -> {
                status.setText(result);
                synchronized (stateLock) { hostReady = result.startsWith("PASS:"); }
                submit.setEnabled(hostReady);
            });
        });
    }

    @Override protected void onDestroy() {
        synchronized (stateLock) { hostReady = false; }
        stopHostNative();
        super.onDestroy();
    }
}
