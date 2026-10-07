#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>

#include <errno.h>
#include <fcntl.h>
#include <new>
#include <pthread.h>
#include <atomic>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

struct Host;
struct FrameCallback {
    wl_list link;
    wl_resource *resource;
};
struct SurfaceState {
    Host *host;
    wl_resource *buffer;
    wl_list callbacks;
};
struct Host {
    wl_display *display;
    ANativeWindow *window;
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t ready_cond;
    bool ready;
    bool stopping;
    int result;
    char socket_path[108];
};

static pthread_mutex_t g_host_mutex = PTHREAD_MUTEX_INITIALIZER;
static Host *g_host = nullptr;
static std::atomic<int> g_rendered_frames(0);

static void frame_resource_destroyed(wl_resource *resource) {
    auto *frame = static_cast<FrameCallback *>(wl_resource_get_user_data(resource));
    if (frame) {
        wl_list_remove(&frame->link);
        delete frame;
    }
}

static void region_destroy(wl_client *, wl_resource *resource) { wl_resource_destroy(resource); }
static void region_add(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}
static void region_subtract(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}
static const struct wl_region_interface region_impl = {region_destroy, region_add, region_subtract};

static void surface_destroy(wl_client *, wl_resource *resource) { wl_resource_destroy(resource); }
static void surface_resource_destroyed(wl_resource *resource) {
    auto *surface = static_cast<SurfaceState *>(wl_resource_get_user_data(resource));
    if (!surface) return;
    FrameCallback *frame, *next;
    wl_list_for_each_safe(frame, next, &surface->callbacks, link) {
        wl_resource_destroy(frame->resource);
    }
    delete surface;
}
static void surface_attach(wl_client *, wl_resource *resource, wl_resource *buffer, int32_t, int32_t) {
    auto *surface = static_cast<SurfaceState *>(wl_resource_get_user_data(resource));
    if (surface) surface->buffer = buffer;
}
static void surface_damage(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}
static void surface_damage_buffer(wl_client *, wl_resource *, int32_t, int32_t, int32_t, int32_t) {}
static void surface_set_region(wl_client *, wl_resource *, wl_resource *) {}
static void surface_transform(wl_client *, wl_resource *, int32_t) {}
static void surface_scale(wl_client *, wl_resource *, int32_t) {}
static void surface_offset(wl_client *, wl_resource *, int32_t, int32_t) {}

static void surface_frame(wl_client *client, wl_resource *resource, uint32_t callback_id) {
    auto *surface = static_cast<SurfaceState *>(wl_resource_get_user_data(resource));
    if (!surface) return;
    auto *frame = new (std::nothrow) FrameCallback{};
    if (!frame) return;
    frame->resource = wl_resource_create(client, &wl_callback_interface, 1, callback_id);
    if (!frame->resource) { delete frame; return; }
    wl_list_init(&frame->link);
    wl_resource_set_implementation(frame->resource, nullptr, frame, frame_resource_destroyed);
    wl_list_insert(surface->callbacks.prev, &frame->link);
}

static bool render_shm_buffer(Host *host, wl_resource *buffer_resource) {
    if (!host || !host->window || !buffer_resource) return false;
    wl_shm_buffer *buffer = wl_shm_buffer_get(buffer_resource);
    if (!buffer) return false;
    const uint32_t format = wl_shm_buffer_get_format(buffer);
    if (format != WL_SHM_FORMAT_ARGB8888 && format != WL_SHM_FORMAT_XRGB8888) return false;
    const int width = wl_shm_buffer_get_width(buffer);
    const int height = wl_shm_buffer_get_height(buffer);
    const int stride = wl_shm_buffer_get_stride(buffer);
    if (width <= 0 || height <= 0 || stride < width * 4) return false;

    ANativeWindow_setBuffersGeometry(host->window, width, height, WINDOW_FORMAT_RGBA_8888);
    ANativeWindow_Buffer target{};
    if (ANativeWindow_lock(host->window, &target, nullptr) != 0) return false;
    bool copied = false;
    if (target.bits && target.width > 0 && target.height > 0 && target.stride >= target.width) {
        wl_shm_buffer_begin_access(buffer);
        const auto *source = static_cast<const uint8_t *>(wl_shm_buffer_get_data(buffer));
        auto *destination = static_cast<uint8_t *>(target.bits);
        const int copy_width = width < target.width ? width : target.width;
        const int copy_height = height < target.height ? height : target.height;
        for (int y = 0; y < target.height; ++y) {
            auto *dst = destination + static_cast<size_t>(y) * target.stride * 4;
            if (y >= copy_height) {
                memset(dst, 0, static_cast<size_t>(target.width) * 4);
                continue;
            }
            const auto *src = source + static_cast<size_t>(y) * stride;
            for (int x = 0; x < copy_width; ++x) {
                uint32_t pixel;
                memcpy(&pixel, src + static_cast<size_t>(x) * 4, sizeof(pixel));
                dst[x * 4 + 0] = static_cast<uint8_t>((pixel >> 16) & 0xff); // R
                dst[x * 4 + 1] = static_cast<uint8_t>((pixel >> 8) & 0xff);  // G
                dst[x * 4 + 2] = static_cast<uint8_t>(pixel & 0xff);         // B
                dst[x * 4 + 3] = 0xff;
            }
            if (copy_width < target.width)
                memset(dst + static_cast<size_t>(copy_width) * 4, 0,
                       static_cast<size_t>(target.width - copy_width) * 4);
        }
        wl_shm_buffer_end_access(buffer);
        copied = true;
    }
    const int posted = ANativeWindow_unlockAndPost(host->window);
    if (copied && posted == 0) {
        g_rendered_frames.fetch_add(1, std::memory_order_release);
        return true;
    }
    return false;
}

static void surface_commit(wl_client *, wl_resource *resource) {
    auto *surface = static_cast<SurfaceState *>(wl_resource_get_user_data(resource));
    if (!surface) return;
    if (surface->buffer && render_shm_buffer(surface->host, surface->buffer))
        wl_buffer_send_release(surface->buffer);
    timespec timestamp{};
    clock_gettime(CLOCK_MONOTONIC, &timestamp);
    const uint32_t now = static_cast<uint32_t>(timestamp.tv_sec * 1000ULL + timestamp.tv_nsec / 1000000ULL);
    FrameCallback *frame, *next;
    wl_list_for_each_safe(frame, next, &surface->callbacks, link) {
        wl_callback_send_done(frame->resource, now);
        wl_resource_destroy(frame->resource);
    }
}

static const struct wl_surface_interface surface_impl = {
    surface_destroy, surface_attach, surface_damage, surface_frame,
    surface_set_region, surface_set_region, surface_commit,
    surface_transform, surface_scale, surface_damage_buffer, surface_offset
};

static void compositor_create_surface(wl_client *client, wl_resource *resource, uint32_t id) {
    auto *host = static_cast<Host *>(wl_resource_get_user_data(resource));
    wl_resource *surface_resource = wl_resource_create(client, &wl_surface_interface, 1, id);
    auto *surface = new (std::nothrow) SurfaceState{};
    if (!surface_resource || !surface) {
        if (surface_resource) wl_resource_destroy(surface_resource);
        delete surface;
        wl_client_post_no_memory(client);
        return;
    }
    surface->host = host;
    surface->buffer = nullptr;
    wl_list_init(&surface->callbacks);
    wl_resource_set_implementation(surface_resource, &surface_impl, surface, surface_resource_destroyed);
}
static void compositor_create_region(wl_client *client, wl_resource *, uint32_t id) {
    wl_resource *region = wl_resource_create(client, &wl_region_interface, 1, id);
    if (!region) { wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(region, &region_impl, nullptr, nullptr);
}
static const struct wl_compositor_interface compositor_impl = {compositor_create_surface, compositor_create_region};

static void bind_compositor(wl_client *client, void *data, uint32_t version, uint32_t id) {
    auto *host = static_cast<Host *>(data);
    wl_resource *resource = wl_resource_create(client, &wl_compositor_interface, version < 1 ? version : 1, id);
    if (!resource) { wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(resource, &compositor_impl, host, nullptr);
}

static void *server_main(void *opaque) {
    auto *host = static_cast<Host *>(opaque);
    host->display = wl_display_create();
    int result = -1;
    if (host->display && wl_display_init_shm(host->display) == 0 &&
        wl_global_create(host->display, &wl_compositor_interface, 1, host, bind_compositor) &&
        wl_display_add_socket(host->display, host->socket_path) == 0) result = 0;
    pthread_mutex_lock(&host->mutex);
    host->result = result;
    host->ready = true;
    pthread_cond_signal(&host->ready_cond);
    pthread_mutex_unlock(&host->mutex);
    if (result == 0) wl_display_run(host->display);
    if (host->display) {
        wl_display_destroy_clients(host->display);
        wl_display_destroy(host->display);
        host->display = nullptr;
    }
    return nullptr;
}

static jstring to_java(JNIEnv *env, const char *text) { return env->NewStringUTF(text ? text : ""); }

extern "C" JNIEXPORT jstring JNICALL
Java_org_miniarino_desktop_WaylandProofActivity_startHostNative(JNIEnv *env, jclass, jobject java_surface, jstring socket_value) {
    const char *socket = env->GetStringUTFChars(socket_value, nullptr);
    if (!socket) return to_java(env, "Could not read the private Wayland socket path");
    if (strlen(socket) >= sizeof(((Host *)0)->socket_path)) {
        env->ReleaseStringUTFChars(socket_value, socket);
        return to_java(env, "Private Wayland socket path is too long");
    }
    ANativeWindow *window = ANativeWindow_fromSurface(env, java_surface);
    if (!window) { env->ReleaseStringUTFChars(socket_value, socket); return to_java(env, "Android did not provide a Surface window"); }
    pthread_mutex_lock(&g_host_mutex);
    if (g_host) {
        pthread_mutex_unlock(&g_host_mutex);
        ANativeWindow_release(window);
        env->ReleaseStringUTFChars(socket_value, socket);
        return to_java(env, "Wayland host is already running");
    }
    auto *host = new (std::nothrow) Host{};
    if (!host) {
        pthread_mutex_unlock(&g_host_mutex);
        ANativeWindow_release(window);
        env->ReleaseStringUTFChars(socket_value, socket);
        return to_java(env, "Could not allocate Wayland host state");
    }
    host->window = window;
    snprintf(host->socket_path, sizeof(host->socket_path), "%s", socket);
    pthread_mutex_init(&host->mutex, nullptr);
    pthread_cond_init(&host->ready_cond, nullptr);
    g_host = host;
    env->ReleaseStringUTFChars(socket_value, socket);
    pthread_mutex_unlock(&g_host_mutex);

    if (pthread_create(&host->thread, nullptr, server_main, host) != 0) {
        pthread_mutex_lock(&g_host_mutex); g_host = nullptr; pthread_mutex_unlock(&g_host_mutex);
        ANativeWindow_release(window); delete host;
        return to_java(env, "Could not start Wayland server thread");
    }
    pthread_mutex_lock(&host->mutex);
    while (!host->ready) pthread_cond_wait(&host->ready_cond, &host->mutex);
    const int result = host->result;
    pthread_mutex_unlock(&host->mutex);
    if (result != 0) {
        pthread_join(host->thread, nullptr);
        pthread_mutex_lock(&g_host_mutex); g_host = nullptr; pthread_mutex_unlock(&g_host_mutex);
        ANativeWindow_release(window);
        pthread_cond_destroy(&host->ready_cond); pthread_mutex_destroy(&host->mutex); delete host;
        return to_java(env, "Wayland display, wl_shm, compositor global, or private socket initialization failed");
    }
    return to_java(env, "Host ready: real libwayland-server socket at the app-private path; input forwarding is not implemented.");
}

extern "C" JNIEXPORT void JNICALL
Java_org_miniarino_desktop_WaylandProofActivity_stopHostNative(JNIEnv *, jclass) {
    pthread_mutex_lock(&g_host_mutex);
    Host *host = g_host;
    g_host = nullptr;
    pthread_mutex_unlock(&g_host_mutex);
    if (!host) return;
    if (host->display) wl_display_terminate(host->display);
    pthread_join(host->thread, nullptr);
    ANativeWindow_release(host->window);
    pthread_cond_destroy(&host->ready_cond);
    pthread_mutex_destroy(&host->mutex);
    delete host;
}

extern "C" int wayland_host_render_count(void) {
    return g_rendered_frames.load(std::memory_order_acquire);
}
