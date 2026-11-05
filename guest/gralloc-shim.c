// Wraps redroid's software gralloc module to add the YUV locking it lacks. Without it, Android's CPU video
// decoders cannot write frames into graphic buffers ("lockYCbCr" fails) and video does not play.
// The module's YV12 buffers are large enough for this layout: 2 bytes per pixel are allocated, 1.5 are needed.
// Check it with: ./avm video-log
#include <stddef.h>
#include <stdint.h>

#define REAL_MODULE "/vendor/lib64/hw/gralloc.redroid-real.so"
#define TAG "FCGralloc"
#define MODULE_SIZE 0x2b0
#define OFF_API_VERSION 4
#define OFF_LOCK 264
#define OFF_UNLOCK 272
#define OFF_LOCK_YCBCR 288
#define GRALLOC_MODULE_API_VERSION_0_2 2
#define RTLD_NOW 2
#define LOG_INFO 4
#define LOG_ERROR 6
#define ALIGN16(x) (((x) + 15) & ~15)

struct android_ycbcr {
  void *y, *cb, *cr;
  size_t ystride, cstride, chroma_step;
  uint32_t reserved[8];
};

typedef int (*lock_fn)(const void *, const void *, int, int, int, int, int, void **);

void *dlopen(const char *, int);
void *dlsym(void *, const char *);
const char *dlerror(void);
void *memcpy(void *, const void *, size_t);
int __android_log_print(int, const char *, const char *, ...);

__attribute__((visibility("default"), aligned(16))) char HMI[MODULE_SIZE];

static lock_fn real_lock;
static unsigned long calls;

static int lock_ycbcr(const void *module, const void *handle, int usage, int l, int t, int w, int h,
                      struct android_ycbcr *out) {
  void *base = NULL;
  int err = real_lock(module, handle, usage, l, t, w, h, &base);
  if (err == 0) {
    size_t ystride = ALIGN16(w), cstride = ALIGN16(ystride / 2);
    char *cr = (char *)base + ystride * h;
    out->y = base;
    out->cr = cr;
    out->cb = cr + cstride * (h / 2);
    out->ystride = ystride;
    out->cstride = cstride;
    out->chroma_step = 1;
  }
  // Log the first frames, then a heartbeat, so a playing video shows up without flooding logcat.
  unsigned long n = __atomic_add_fetch(&calls, 1, __ATOMIC_RELAXED);
  if (n <= 5 || n % 300 == 0 || err != 0)
    __android_log_print(err ? LOG_ERROR : LOG_INFO, TAG, "lock_ycbcr #%lu %dx%d usage=0x%x err=%d", n, w, h, usage, err);
  return err;
}

__attribute__((constructor)) static void init(void) {
  void *lib = dlopen(REAL_MODULE, RTLD_NOW);
  void *real = lib ? dlsym(lib, "HMI") : NULL;
  if (!real) {
    __android_log_print(LOG_ERROR, TAG, "cannot load %s: %s", REAL_MODULE, dlerror());
    return;
  }
  memcpy(HMI, real, MODULE_SIZE);
  real_lock = *(lock_fn *)(HMI + OFF_LOCK);
  *(uint16_t *)(HMI + OFF_API_VERSION) = GRALLOC_MODULE_API_VERSION_0_2;
  *(void **)(HMI + OFF_LOCK_YCBCR) = (void *)lock_ycbcr;
  __android_log_print(LOG_INFO, TAG, "loaded: real lock=%p", (void *)real_lock);
}
