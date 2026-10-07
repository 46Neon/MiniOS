#include <jni.h>
#include <wayland-client-core.h>
#include <wayland-client-protocol.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

extern "C" int wayland_host_render_count(void);

struct ClientGlobals {
    wl_compositor *compositor = nullptr;
    wl_shm *shm = nullptr;
};
struct FrameState { bool done = false; };

static void registry_global(void *data, wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    auto *globals = static_cast<ClientGlobals *>(data);
    if (strcmp(interface, wl_compositor_interface.name) == 0)
        globals->compositor = reinterpret_cast<wl_compositor *>(wl_registry_bind(
            registry, name, &wl_compositor_interface, version < 1 ? version : 1));
    else if (strcmp(interface, wl_shm_interface.name) == 0)
        globals->shm = reinterpret_cast<wl_shm *>(wl_registry_bind(
            registry, name, &wl_shm_interface, version < 1 ? version : 1));
}
static void registry_remove(void *, wl_registry *, uint32_t) {}
static const wl_registry_listener registry_listener = {registry_global, registry_remove};
static void frame_done(void *data, wl_callback *, uint32_t) {
    static_cast<FrameState *>(data)->done = true;
}
static const wl_callback_listener frame_listener = {frame_done};

static jstring java_string(JNIEnv *env, const char *message) { return env->NewStringUTF(message); }

extern "C" JNIEXPORT jstring JNICALL
Java_org_miniarino_desktop_WaylandProofActivity_submitTestSurfaceNative(
        JNIEnv *env, jclass, jstring socket_value, jstring tmp_value) {
    const char *socket_path = env->GetStringUTFChars(socket_value, nullptr);
    const char *tmp_path = env->GetStringUTFChars(tmp_value, nullptr);
    if (!socket_path || !tmp_path) {
        if (socket_path) env->ReleaseStringUTFChars(socket_value, socket_path);
        if (tmp_path) env->ReleaseStringUTFChars(tmp_value, tmp_path);
        return java_string(env, "Could not read private Wayland socket/tmp paths");
    }

    char socket_copy[108];
    char file_template[256];
    snprintf(socket_copy, sizeof(socket_copy), "%s", socket_path);
    snprintf(file_template, sizeof(file_template), "%s/wayland-test-XXXXXX", tmp_path);
    env->ReleaseStringUTFChars(socket_value, socket_path);
    env->ReleaseStringUTFChars(tmp_value, tmp_path);

    const int frames_before = wayland_host_render_count();
    wl_display *display = wl_display_connect(socket_copy);
    if (!display) return java_string(env, "FAIL: the real Wayland client library could not connect to the host socket");
    ClientGlobals globals{};
    wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, &globals);
    if (wl_display_roundtrip(display) < 0 || !globals.compositor || !globals.shm) {
        wl_display_disconnect(display);
        return java_string(env, "FAIL: host did not advertise wl_compositor and wl_shm");
    }

    constexpr int width = 320, height = 240, stride = width * 4;
    const size_t byte_count = static_cast<size_t>(stride) * height;
    const int fd = mkstemp(file_template);
    if (fd < 0 || ftruncate(fd, static_cast<off_t>(byte_count)) != 0) {
        if (fd >= 0) { close(fd); unlink(file_template); }
        wl_display_disconnect(display);
        return java_string(env, "FAIL: could not allocate a real wl_shm backing file in private tmp");
    }
    void *pixels = mmap(nullptr, byte_count, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) {
        close(fd); unlink(file_template); wl_display_disconnect(display);
        return java_string(env, "FAIL: mmap of the wl_shm test buffer failed");
    }
    // Little-endian ARGB8888, an opaque vivid green test surface.
    auto *words = static_cast<uint32_t *>(pixels);
    for (size_t i = 0; i < byte_count / sizeof(uint32_t); ++i) words[i] = 0xff31b85bU;
    munmap(pixels, byte_count);

    wl_shm_pool *pool = wl_shm_create_pool(globals.shm, fd, static_cast<int32_t>(byte_count));
    wl_buffer *buffer = pool ? wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888) : nullptr;
    close(fd);
    unlink(file_template);
    if (!pool || !buffer) {
        if (buffer) wl_buffer_destroy(buffer);
        if (pool) wl_shm_pool_destroy(pool);
        wl_display_disconnect(display);
        return java_string(env, "FAIL: libwayland could not create the wl_shm pool/buffer");
    }

    wl_surface *surface = wl_compositor_create_surface(globals.compositor);
    if (!surface) {
        wl_buffer_destroy(buffer);
        wl_shm_pool_destroy(pool);
        wl_display_disconnect(display);
        return java_string(env, "FAIL: libwayland could not create the test wl_surface");
    }
    FrameState frame{};
    wl_callback *callback = wl_surface_frame(surface);
    if (!callback) {
        wl_surface_destroy(surface);
        wl_buffer_destroy(buffer);
        wl_shm_pool_destroy(pool);
        wl_display_disconnect(display);
        return java_string(env, "FAIL: libwayland could not create the frame callback");
    }
    wl_callback_add_listener(callback, &frame_listener, &frame);
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage(surface, 0, 0, width, height);
    wl_surface_commit(surface);
    const int roundtrip = wl_display_roundtrip(display);
    const bool rendered = frame.done && wayland_host_render_count() > frames_before;

    if (callback) wl_callback_destroy(callback);
    if (surface) wl_surface_destroy(surface);
    wl_buffer_destroy(buffer);
    wl_shm_pool_destroy(pool);
    wl_display_disconnect(display);
    if (roundtrip < 0 || !rendered)
        return java_string(env, "FAIL: client commit/callback completed without a confirmed ANativeWindow buffer post");
    return java_string(env, "PASS: separate libwayland-client connection submitted a wl_shm ARGB8888 surface; host posted it to Android Surface. Host protocol/surface gate only—no PRoot guest or input round trip.");
}
