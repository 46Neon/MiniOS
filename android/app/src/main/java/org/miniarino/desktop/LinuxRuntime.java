package org.miniarino.desktop;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.system.Os;
import android.util.Base64;
import android.system.OsConstants;

import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import java.util.zip.GZIPInputStream;

/** Pinned Termux PRoot runtime plus an official, digest-pinned Debian ARM64 OCI rootfs. */
final class LinuxRuntime {
    static final String PROOT_VERSION = "5.1.107.96";
    static final String PROOT_SOURCE_COMMIT = "de39661946f7e8175b5dd0755121fa28cb0aebd1";
    static final String OCI_MANIFEST_DIGEST = "sha256:a1b86db52ce3daef089e45aabe36dfec4091f82464c25c1fdcf03de197cbe82a";
    static final String ROOTFS_LAYER_SHA256 = "c75f989a229d12b2d2613a5997de9ff3546f664c22da9248720033a2410220f6";
    static final long ROOTFS_LAYER_BYTES = 28137179L;
    private static final String DOCKER_TOKEN_URL = "https://auth.docker.io/token?service=registry.docker.io&scope=repository%3Alibrary%2Fdebian%3Apull";
    private static final String OCI_MANIFEST_URL = "https://registry-1.docker.io/v2/library/debian/manifests/" + OCI_MANIFEST_DIGEST;
    private static final String ROOTFS_BLOB_URL = "https://registry-1.docker.io/v2/library/debian/blobs/sha256:" + ROOTFS_LAYER_SHA256;
    private static final String ROOT_MARKER = ".miniarino-debian-arm64-ready";
    static final String DESKTOP_READY_MARKER = "MINIARINO_XFCE_SESSION_READY";
    private static final long DESKTOP_START_TIMEOUT_MS = TimeUnit.MINUTES.toMillis(15);
    private static final int CONNECT_TIMEOUT_MS = 20000;
    private static final int READ_TIMEOUT_MS = 45000;

    private final Context context;
    private final File base;
    private final File rootfs;
    private final File binDir;
    private final File libDir;
    private final File loaderDir;
    private final File tmpDir;

    LinuxRuntime(Context context) {
        this.context = context.getApplicationContext();
        this.base = new File(context.getFilesDir(), "linux");
        this.rootfs = new File(base, "debian-arm64");
        this.binDir = new File(base, "usr/bin");
        this.libDir = new File(base, "usr/lib");
        this.loaderDir = new File(base, "usr/libexec/proot");
        // Lorie is started with this same app-private TMPDIR so its Unix X socket is visible in Debian /tmp.
        this.tmpDir = new File(context.getFilesDir(), "tmp");
    }

    boolean isReady() {
        return new File(rootfs, ROOT_MARKER).isFile() && new File(binDir, "proot").canExecute();
    }

    /** Downloads, verifies, and installs the pinned official Debian bookworm-slim ARM64 layer. */
    void provision(Progress progress) throws Exception {
        ensureDir(base); ensureDir(binDir); ensureDir(libDir); ensureDir(loaderDir); ensureDir(tmpDir); ensureDir(new File(tmpDir, "proot"));
        installBundledRuntime();
        if (new File(rootfs, ROOT_MARKER).isFile()) return;
        File archive = new File(base, "debian-arm64-rootfs.tar.gz");
        String token = fetchDockerPullToken();
        verifyPinnedManifest(token);
        progress.update("Downloading verified Debian ARM64 root filesystem (~27 MiB)…");
        downloadAndVerify(archive, token);
        File staging = new File(base, "debian-arm64-staging");
        deleteTree(staging);
        ensureDir(staging);
        progress.update("Extracting Debian ARM64 root filesystem…");
        extractRootfs(archive, staging);
        if (!archive.delete()) archive.deleteOnExit();
        try (FileOutputStream out = new FileOutputStream(new File(staging, ROOT_MARKER))) {
            out.write((OCI_MANIFEST_DIGEST + "\n" + ROOTFS_LAYER_SHA256 + "\n").getBytes(StandardCharsets.UTF_8));
        }
        deleteTree(rootfs);
        if (!staging.renameTo(rootfs)) throw new IOException("Cannot finalize Debian root filesystem installation");
    }

    private void installBundledRuntime() throws IOException {
        copyAssetIfMissing("proot/bin/proot", new File(binDir, "proot"), true);
        copyAssetIfMissing("proot/lib/libtalloc.so.2", new File(libDir, "libtalloc.so.2"), false);
        copyAssetIfMissing("proot/lib/libandroid-shmem.so", new File(libDir, "libandroid-shmem.so"), false);
        copyAssetIfMissing("proot/libexec/proot/loader", new File(loaderDir, "loader"), true);
    }

    private void copyAssetIfMissing(String asset, File target, boolean executable) throws IOException {
        if (target.isFile() && (!executable || target.canExecute())) return;
        File parent = target.getParentFile();
        ensureDir(parent);
        try (InputStream in = context.getAssets().open(asset); FileOutputStream out = new FileOutputStream(target)) {
            copy(in, out, null);
        }
        if (executable && !target.setExecutable(true, true)) throw new IOException("Cannot enable execution for " + target.getName());
    }

    private String fetchDockerPullToken() throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(DOCKER_TOKEN_URL).openConnection();
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS); connection.setReadTimeout(READ_TIMEOUT_MS);
        try (InputStream in = connection.getInputStream()) {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream(); copy(in, bytes, null);
            return new JSONObject(new String(bytes.toByteArray(), StandardCharsets.UTF_8)).getString("token");
        } finally { connection.disconnect(); }
    }

    private void verifyPinnedManifest(String token) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(OCI_MANIFEST_URL).openConnection();
        connection.setRequestProperty("Authorization", "Bearer " + token);
        connection.setRequestProperty("Accept", "application/vnd.oci.image.manifest.v1+json");
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS); connection.setReadTimeout(READ_TIMEOUT_MS);
        try {
            int code = connection.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) throw new IOException("Pinned Debian OCI manifest returned HTTP " + code);
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            try (InputStream in = connection.getInputStream()) { copyBounded(in, bytes, null, 131072L); }
            verifyPinnedManifestDocument(bytes.toByteArray());
        } finally { connection.disconnect(); }
    }

    /** Verifies manifest bytes and every ARM64 rootfs descriptor before any layer download. */
    static void verifyPinnedManifestDocument(byte[] document) throws Exception {
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        String manifestDigest = "sha256:" + hex(sha256.digest(document));
        if (!OCI_MANIFEST_DIGEST.equals(manifestDigest)) {
            throw new IOException("Debian OCI manifest digest mismatch: expected " + OCI_MANIFEST_DIGEST + ", received " + manifestDigest);
        }
        JSONObject manifest = new JSONObject(new String(document, StandardCharsets.UTF_8));
        verifyManifestContents(manifest);
    }

    /** Separate content checks make registry drift diagnosable and directly fixture-testable. */
    static void verifyManifestContents(JSONObject manifest) throws Exception {
        String manifestType = manifest.optString("mediaType", "<missing>");
        if (!"application/vnd.oci.image.manifest.v1+json".equals(manifestType)) {
            throw new IOException("Unexpected Debian manifest mediaType: " + manifestType);
        }

        JSONObject config = manifest.optJSONObject("config");
        if (config == null) throw new IOException("Pinned Debian manifest is missing its image config descriptor");
        String configMediaType = config.optString("mediaType", "<missing>");
        if (!"application/vnd.oci.image.config.v1+json".equals(configMediaType)) throw new IOException("Unexpected Debian image config mediaType: " + configMediaType);
        String configDigest = config.optString("digest", "<missing>");
        long configSize = config.optLong("size", -1L);
        if (!ROOTFS_CONFIG_SHA256.equals(configDigest) || configSize != 468L) {
            throw new IOException("Debian image config descriptor mismatch: expected " + ROOTFS_CONFIG_SHA256 + " (468 bytes), received " + configDigest + " (" + configSize + " bytes)");
        }
        String encodedConfig = config.optString("data", "");
        if (encodedConfig.isEmpty()) throw new IOException("Pinned Debian manifest is missing its inline image config");
        byte[] configBytes;
        try { configBytes = Base64.decode(encodedConfig, Base64.DEFAULT); }
        catch (IllegalArgumentException e) { throw new IOException("Pinned Debian image config is not valid Base64", e); }
        if (configBytes.length != configSize) throw new IOException("Debian image config size mismatch: expected " + configSize + ", received " + configBytes.length);
        String actualConfigDigest = "sha256:" + hex(MessageDigest.getInstance("SHA-256").digest(configBytes));
        if (!ROOTFS_CONFIG_SHA256.equals(actualConfigDigest)) throw new IOException("Debian image config SHA-256 mismatch: expected " + ROOTFS_CONFIG_SHA256 + ", received " + actualConfigDigest);
        JSONObject imageConfig = new JSONObject(new String(configBytes, StandardCharsets.UTF_8));
        String os = imageConfig.optString("os", "<missing>");
        String architecture = imageConfig.optString("architecture", "<missing>");
        String variant = imageConfig.optString("variant", "<missing>");
        if (!"linux".equals(os) || !"arm64".equals(architecture) || !"v8".equals(variant)) {
            throw new IOException("Debian image platform mismatch: expected linux/arm64/v8, received " + os + "/" + architecture + "/" + variant);
        }
        JSONObject rootfsConfig = imageConfig.optJSONObject("rootfs");
        org.json.JSONArray diffIds = rootfsConfig == null ? null : rootfsConfig.optJSONArray("diff_ids");
        if (rootfsConfig == null || !"layers".equals(rootfsConfig.optString("type")) || diffIds == null || diffIds.length() != 1 || !ROOTFS_DIFF_ID.equals(diffIds.optString(0))) {
            throw new IOException("Debian image config does not describe the pinned single ARM64 rootfs layer (expected diff ID " + ROOTFS_DIFF_ID + ")");
        }

        org.json.JSONArray layers = manifest.optJSONArray("layers");
        if (layers == null || layers.length() != 1) {
            throw new IOException("Pinned Debian ARM64 manifest layer count mismatch: expected 1, received " + (layers == null ? "missing" : layers.length()));
        }
        JSONObject layer = layers.optJSONObject(0);
        if (layer == null) throw new IOException("Pinned Debian ARM64 manifest layer[0] is not an object");
        String mediaType = layer.optString("mediaType", "<missing>");
        String digest = layer.optString("digest", "<missing>");
        long size = layer.optLong("size", -1L);
        if (!"application/vnd.oci.image.layer.v1.tar+gzip".equals(mediaType) || !ROOTFS_LAYER_SHA256.equals(digest) || size != ROOTFS_LAYER_BYTES) {
            throw new IOException("Pinned Debian ARM64 layer[0] mismatch: expected application/vnd.oci.image.layer.v1.tar+gzip " + ROOTFS_LAYER_SHA256 + " (" + ROOTFS_LAYER_BYTES + " bytes), received " + mediaType + " " + digest + " (" + size + " bytes)");
        }
    }

    private void downloadAndVerify(File target, String token) throws Exception {
        File part = new File(target.getPath() + ".part");
        HttpURLConnection connection = (HttpURLConnection) new URL(ROOTFS_BLOB_URL).openConnection();
        connection.setRequestProperty("Authorization", "Bearer " + token);
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS); connection.setReadTimeout(READ_TIMEOUT_MS);
        connection.setInstanceFollowRedirects(true);
        try {
            int code = connection.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) throw new IOException("Debian layer download returned HTTP " + code);
            long advertised = connection.getContentLengthLong();
            if (advertised >= 0 && advertised != ROOTFS_LAYER_BYTES) throw new IOException("Unexpected Debian layer size");
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new BufferedInputStream(connection.getInputStream()); FileOutputStream out = new FileOutputStream(part)) {
                copyBounded(in, out, digest, ROOTFS_LAYER_BYTES);
            }
            String actual = hex(digest.digest());
            if (!ROOTFS_LAYER_SHA256.equals(actual) || part.length() != ROOTFS_LAYER_BYTES) {
                part.delete(); throw new IOException("Debian rootfs SHA-256 verification failed");
            }
            if (target.exists() && !target.delete()) throw new IOException("Cannot replace old Debian layer");
            if (!part.renameTo(target)) throw new IOException("Cannot finalize Debian layer download");
        } finally { connection.disconnect(); }
    }

    /** Extracts plain USTAR entries without following archive-created symlinks during extraction. */
    private void extractRootfs(File archive, File destination) throws Exception {
        List<Link> symlinks = new ArrayList<>();
        List<Link> hardlinks = new ArrayList<>();
        try (InputStream in = new BufferedInputStream(new GZIPInputStream(new FileInputStream(archive)))) {
            byte[] header = new byte[512];
            while (readBlock(in, header)) {
                if (allZero(header)) break;
                String name = tarString(header, 0, 100);
                String prefix = tarString(header, 345, 155);
                if (!prefix.isEmpty()) name = prefix + "/" + name;
                String relative = safeArchivePath(name);
                long size = tarOctal(header, 124, 12);
                int type = header[156] & 0xff;
                String linkName = tarString(header, 157, 100);
                if (relative.isEmpty()) { skipExactly(in, size); skipExactly(in, (512 - (size % 512)) % 512); continue; }
                File output = new File(destination, relative);
                ensureContained(destination, output);
                if (type == 0 || type == '0') {
                    ensureDir(output.getParentFile());
                    try (OutputStream out = new BufferedOutputStream(new FileOutputStream(output))) { copyExactly(in, out, size); }
                    int mode = (int) tarOctal(header, 100, 8);
                    output.setReadable((mode & 0444) != 0, false);
                    output.setWritable((mode & 0222) != 0, true);
                    output.setExecutable((mode & 0111) != 0, false);
                } else if (type == '5') {
                    ensureDir(output);
                    skipExactly(in, size);
                } else if (type == '2') {
                    symlinks.add(new Link(relative, safeLinkTarget(relative, linkName), false));
                    skipExactly(in, size);
                } else if (type == '1') {
                    hardlinks.add(new Link(relative, safeArchivePath(linkName), true));
                    skipExactly(in, size);
                } else if (type == 'x' || type == 'g' || type == 'L' || type == 'K') {
                    throw new IOException("Unsupported non-USTAR metadata in pinned Debian layer");
                } else {
                    skipExactly(in, size);
                }
                long padding = (512 - (size % 512)) % 512;
                skipExactly(in, padding);
            }
        }
        for (Link link : hardlinks) {
            File source = new File(destination, link.target);
            File output = new File(destination, link.path);
            ensureContained(destination, source); ensureContained(destination, output);
            if (!source.isFile()) throw new IOException("Broken hard link in Debian rootfs archive");
            ensureDir(output.getParentFile());
            try (InputStream in = new FileInputStream(source); OutputStream out = new FileOutputStream(output)) { copy(in, out, null); }
        }
        for (Link link : symlinks) {
            File output = new File(destination, link.path);
            ensureDir(output.getParentFile());
            if (output.exists() || output.isDirectory()) continue;
            Os.symlink(link.target, output.getAbsolutePath());
        }
    }

    private static String safeLinkTarget(String linkPath, String target) throws IOException {
        if (target.isEmpty() || target.indexOf('\0') >= 0) throw new IOException("Invalid symlink in rootfs");
        // Check resolution within the guest root; absolute targets are root-relative in Debian.
        String parent = new File(linkPath).getParent();
        String resolved = target.startsWith("/") ? target.substring(1) : (parent == null ? "" : parent + "/") + target;
        String normalized = new File("/" + resolved).getCanonicalPath().substring(1);
        if (normalized.equals("..") || normalized.startsWith("../")) throw new IOException("Escaping symlink in rootfs");
        return target;
    }

    private static String safeArchivePath(String input) throws IOException {
        String path = input.replace('\\', '/');
        while (path.startsWith("./")) path = path.substring(2);
        if (path.isEmpty() || path.equals(".")) return "";
        if (path.startsWith("/") || path.indexOf('\0') >= 0) throw new IOException("Unsafe path in rootfs archive");
        String normalized = new File("/" + path).getCanonicalPath().substring(1);
        if (normalized.equals("..") || normalized.startsWith("../")) throw new IOException("Path escapes rootfs archive");
        return normalized;
    }

    private static void ensureContained(File root, File path) throws IOException {
        String base = root.getCanonicalPath() + File.separator;
        String canonical = path.getCanonicalPath();
        if (!canonical.equals(root.getCanonicalPath()) && !canonical.startsWith(base)) throw new IOException("Rootfs extraction path escaped private storage");
    }

    private static boolean readBlock(InputStream in, byte[] b) throws IOException {
        int off = 0; while (off < b.length) { int n = in.read(b, off, b.length - off); if (n < 0) { if (off == 0) return false; throw new IOException("Truncated tar header"); } off += n; } return true;
    }
    private static void copyExactly(InputStream in, OutputStream out, long count) throws IOException { byte[] b = new byte[32768]; while (count > 0) { int n = in.read(b, 0, (int) Math.min(b.length, count)); if (n < 0) throw new IOException("Truncated Debian rootfs file"); out.write(b, 0, n); count -= n; } }
    private static void skipExactly(InputStream in, long count) throws IOException { byte[] b = new byte[8192]; while (count > 0) { long n = in.skip(count); if (n <= 0) { int r = in.read(b, 0, (int) Math.min(b.length, count)); if (r < 0) throw new IOException("Truncated Debian rootfs archive"); n = r; } count -= n; } }
    private static void copy(InputStream in, OutputStream out, MessageDigest digest) throws IOException { byte[] b = new byte[32768]; int n; while ((n = in.read(b)) >= 0) { out.write(b, 0, n); if (digest != null) digest.update(b, 0, n); } }
    private static void copyBounded(InputStream in, OutputStream out, MessageDigest digest, long maximum) throws IOException {
        byte[] b = new byte[32768]; long total = 0; int n;
        while ((n = in.read(b)) >= 0) {
            total += n;
            if (total > maximum) throw new IOException("Downloaded OCI object exceeds its pinned size limit");
            out.write(b, 0, n); if (digest != null) digest.update(b, 0, n);
        }
    }
    private static boolean allZero(byte[] b) { for (byte value : b) if (value != 0) return false; return true; }
    private static String tarString(byte[] b, int off, int len) { int end = off; while (end < off + len && b[end] != 0) end++; return new String(b, off, end - off, StandardCharsets.UTF_8); }
    private static long tarOctal(byte[] b, int off, int len) throws IOException { String s = tarString(b, off, len).trim(); if (s.isEmpty()) return 0; try { return Long.parseLong(s, 8); } catch (NumberFormatException e) { throw new IOException("Invalid numeric field in rootfs tar", e); } }
    private static String hex(byte[] b) { StringBuilder s = new StringBuilder(); for (byte v : b) s.append(String.format(Locale.US, "%02x", v & 0xff)); return s.toString(); }
    private static void ensureDir(File dir) throws IOException { if (dir != null && !dir.isDirectory() && !dir.mkdirs() && !dir.isDirectory()) throw new IOException("Cannot create private Linux environment directory"); }
    private static void deleteTree(File path) throws IOException {
        if (path == null) return;
        boolean link = false; boolean exists = path.exists();
        try { link = (Os.lstat(path.getAbsolutePath()).st_mode & OsConstants.S_IFMT) == OsConstants.S_IFLNK; exists = true; } catch (Exception ignored) { }
        if (!exists) return;
        if (!link && path.isDirectory()) {
            File[] children = path.listFiles();
            if (children != null) for (File child : children) deleteTree(child);
        }
        if (!path.delete()) throw new IOException("Cannot remove incomplete private Linux environment");
    }

    void writeGuestDns() {
        List<String> servers = new ArrayList<>();
        try {
            ConnectivityManager manager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
            Network network = manager == null ? null : manager.getActiveNetwork();
            LinkProperties properties = network == null ? null : manager.getLinkProperties(network);
            if (properties != null) for (java.net.InetAddress address : properties.getDnsServers()) servers.add(address.getHostAddress());
        } catch (Exception ignored) { }
        if (servers.isEmpty()) { servers.add("1.1.1.1"); servers.add("8.8.8.8"); }
        File resolver = new File(base, "android-resolv.conf");
        try (FileOutputStream out = new FileOutputStream(resolver)) {
            for (String server : servers) out.write(("nameserver " + server + "\n").getBytes(StandardCharsets.UTF_8));
        } catch (IOException ignored) { }
    }

    Process startXfceDesktop(File logFile) throws IOException {
        if (!isReady()) throw new IOException("Debian ARM64 is not installed");
        writeGuestDns();
        File script = new File(base, "xfce-session.sh");
        copyAsset("linux/xfce-session.sh", script);
        String proot = new File(binDir, "proot").getAbsolutePath();
        String temp = tmpDir.getAbsolutePath();
        ProcessBuilder builder = new ProcessBuilder(proot, "--link2symlink", "-0", "-r", rootfs.getAbsolutePath(),
                "-b", "/dev", "-b", "/proc", "-b", "/sys", "-b", temp + ":/tmp",
                "-b", script.getAbsolutePath() + ":/tmp/miniarino-xfce-session.sh",
                "-b", new File(base, "android-resolv.conf").getAbsolutePath() + ":/etc/resolv.conf",
                "-w", "/root", "/bin/sh", "/tmp/miniarino-xfce-session.sh");
        builder.environment().put("LD_LIBRARY_PATH", libDir.getAbsolutePath());
        builder.environment().put("PROOT_LOADER", new File(loaderDir, "loader").getAbsolutePath());
        builder.environment().put("PROOT_TMP_DIR", new File(tmpDir, "proot").getAbsolutePath());
        builder.environment().put("PROOT_NO_SECCOMP", "1");
        builder.environment().put("TMPDIR", temp);
        builder.environment().put("DISPLAY", ":0");
        builder.environment().put("HOME", "/root");
        builder.environment().put("LANG", "C.UTF-8");
        builder.environment().put("XDG_RUNTIME_DIR", "/tmp/xdg-runtime");
        builder.environment().put("XDG_SESSION_TYPE", "x11");
        builder.environment().put("XDG_CURRENT_DESKTOP", "XFCE");
        builder.environment().put("DESKTOP_SESSION", "xfce");
        builder.redirectErrorStream(true);
        builder.redirectOutput(logFile);
        return builder.start();
    }

    void awaitXfceSession(Process process, File logFile) throws Exception {
        long deadline = System.currentTimeMillis() + DESKTOP_START_TIMEOUT_MS;
        try (java.io.RandomAccessFile log = new java.io.RandomAccessFile(logFile, "r")) {
            long position = 0;
            while (System.currentTimeMillis() < deadline) {
                log.seek(position);
                String line;
                while ((line = log.readLine()) != null) {
                    position = log.getFilePointer();
                    if (DESKTOP_READY_MARKER.equals(line.trim())) return;
                }
                try {
                    int exit = process.exitValue();
                    throw new IOException("XFCE session exited before readiness (code " + exit + "). " + recentLog(logFile));
                } catch (IllegalThreadStateException stillRunning) {
                    // Wait for the session manager to register on its private D-Bus before reporting success.
                }
                Thread.sleep(500L);
            }
        }
        throw new IOException("Timed out waiting for XFCE session startup. " + recentLog(logFile));
    }

    private static String recentLog(File file) {
        if (!file.isFile()) return "No desktop log was produced.";
        try (java.io.RandomAccessFile input = new java.io.RandomAccessFile(file, "r")) {
            long start = Math.max(0L, input.length() - 2048L);
            input.seek(start);
            byte[] bytes = new byte[(int) (input.length() - start)];
            input.readFully(bytes);
            return new String(bytes, StandardCharsets.UTF_8).replace('\n', ' ').trim();
        } catch (IOException ignored) { return "Could not read the desktop log."; }
    }

    private void copyAsset(String asset, File target) throws IOException {
        ensureDir(target.getParentFile());
        try (InputStream in = context.getAssets().open(asset); FileOutputStream out = new FileOutputStream(target)) {
            copy(in, out, null);
        }
    }

    interface Progress { void update(String message); }
    private static final class Link { final String path, target; final boolean hard; Link(String p, String t, boolean h) { path=p; target=t; hard=h; } }
}
