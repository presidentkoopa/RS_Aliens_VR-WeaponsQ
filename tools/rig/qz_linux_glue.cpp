// qzlinux17 glue: replaces QzDoom_OpenXR.cpp / TBXR_Common.cpp / OpenXrInput.cpp of
// emawind84/questzdoom (the Android JNI + OpenXR layer) for a headless Linux test build.
// The engine's real OpenXR device mode (gl_openxrdevice.cpp, vr_mode 15) runs unchanged;
// this file only supplies what the OpenXR runtime would: HMD/controller poses (OpenXR stage
// space: +X right, +Y up, -Z forward, metres), buttons, eye buffers and the projection.
//
// Poses / buttons can be driven at runtime with console cvars (or env vars at startup):
//   qz_hmd   "x y z pitch yaw roll"   default "0 1.6 0 0 0 0"           (env QZ_HMD)
//   qz_rhand "x y z pitch yaw roll"   default "0.25 1.3 -0.3 30 0 0"     (env QZ_RHAND)
//   qz_lhand "x y z pitch yaw roll"   default "-0.25 1.3 -0.3 30 0 0"    (env QZ_LHAND)
//   qz_rtrigger / qz_rgrip / qz_ltrigger / qz_lgrip   0..1 (>0.5 = pressed)
//   qz_rbuttons / qz_lbuttons   raw xrButton bitmask (A=1 B=2 X=0x100 Y=0x200 thumb=4/0x400 ...)
//   qz_rstick / qz_lstick "x y"   thumbstick axes
// Angles in degrees: pitch about +X (positive = up), yaw about +Y (positive = left), roll about -Z.
// Hand pitch defaults to +30 because the engine applies vr_weaponRotate (-30) to the raw controller
// pose; +30 makes the in-game weapon aim level/forward (AttackPitch 0, AttackDir angle 0 pitch 0).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <time.h>
#include <signal.h>
#include <execinfo.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include "VrInput.h"
#include "xr_linear.h"
#include "c_dispatch.h"

// ---- android log shim ---------------------------------------------------
extern "C" int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap)
{
	static int on = -1;
	if (on < 0) on = getenv("QZ_LOGCAT") != nullptr;
	if (!on) return 0;
	fprintf(stderr, "[%s] ", tag ? tag : "");
	int r = vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	return r;
}
extern "C" int __android_log_print(int prio, const char *tag, const char *fmt, ...)
{
	va_list ap; va_start(ap, fmt);
	int r = __android_log_vprint(prio, tag, fmt, ap);
	va_end(ap);
	return r;
}

// ---- globals normally defined in QzDoom_OpenXR.cpp / TBXR_Common.cpp ----
class FArgs;
FArgs *Args;	// defined by the wrapper on Android (d_main.cpp only declares it)
int NUM_MULTI_SAMPLES = 2;
int REFRESH = 0;
float SS_MULTIPLIER = 1.25f;
bool qzdoom_initialised;
long long global_time;
float playerYaw;
bool resetDoomYaw;
bool resetPreviousPitch;
float doomYaw;
float previousPitch;
vec3_t worldPosition;
vec3_t hmdPosition;
vec3_t hmdorientation;
vec3_t positionDeltaThisFrame;
vec3_t weaponangles;
vec3_t weaponoffset;
bool weaponStabilised;
vec3_t offhandangles;
vec3_t offhandoffset;
bool player_moving;
bool shutdown;
bool ready_teleport;
bool trigger_teleport;
bool cinemamode;
ovrApp gAppState;
ovrAppThread *gAppThread;
ovrJava java;
static bool useVirtualScreen = false;

static int g_width = 1024, g_height = 1024;
static GLuint g_fbo, g_color, g_depth;

// ---- pose / button cvars --------------------------------------------------
static const char *envor(const char *e, const char *d) { const char *v = getenv(e); return v ? v : d; }
CVAR(String, qz_hmd,   envor("QZ_HMD",   "0 1.6 0 0 0 0"), 0)
CVAR(String, qz_rhand, envor("QZ_RHAND", "0.25 1.3 -0.3 30 0 0"), 0)
CVAR(String, qz_lhand, envor("QZ_LHAND", "-0.25 1.3 -0.3 30 0 0"), 0)
CVAR(Float, qz_rtrigger, 0.f, 0)
CVAR(Float, qz_rgrip, 0.f, 0)
CVAR(Float, qz_ltrigger, 0.f, 0)
CVAR(Float, qz_lgrip, 0.f, 0)
CVAR(Int, qz_rbuttons, 0, 0)
CVAR(Int, qz_lbuttons, 0, 0)
CVAR(String, qz_rstick, "0 0", 0)
CVAR(String, qz_lstick, "0 0", 0)

static XrPosef ParsePose(const char *s)
{
	float v[6] = {0, 0, 0, 0, 0, 0};
	sscanf(s, "%f %f %f %f %f %f", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]);
	XrPosef p;
	p.position.x = v[0]; p.position.y = v[1]; p.position.z = v[2];
	// q = yaw(Y) * pitch(X) * roll(Z)
	XrQuaternionf qy, qx, qz, t;
	XrVector3f ay = {0, 1, 0}, ax = {1, 0, 0}, az = {0, 0, -1};
	XrQuaternionf_CreateFromAxisAngle(&qy, &ay, v[4] * (float)M_PI / 180.f);
	XrQuaternionf_CreateFromAxisAngle(&qx, &ax, v[3] * (float)M_PI / 180.f);
	XrQuaternionf_CreateFromAxisAngle(&qz, &az, v[5] * (float)M_PI / 180.f);
	XrQuaternionf_Multiply(&t, &qz, &qx);   // xr_linear: Multiply(result,a,b) = b*a
	XrQuaternionf_Multiply(&p.orientation, &t, &qy);
	return p;
}

// ---- QzDoom_* ----------------------------------------------------------
void QzDoom_setUseScreenLayer(bool use) { useVirtualScreen = use; }
int QzDoom_SetRefreshRate(int refreshRate) { return 0; }
void QzDoom_GetScreenRes(uint32_t *width, uint32_t *height) { *width = g_width; *height = g_height; }
void QzDoom_Vibrate(float duration, int channel, float intensity) {}
void QzDoom_Restart() { fprintf(stderr, "qzlinux: QzDoom_Restart requested (Android would relaunch the app); exiting\n"); exit(3); }
bool VR_UseScreenLayer() { return useVirtualScreen || cinemamode; }
float VR_GetScreenLayerDistance() { return 4.0f; }

void VR_SetHMDOrientation(float pitch, float yaw, float roll)
{
	VectorSet(hmdorientation, pitch, yaw, roll);
	if (!VR_UseScreenLayer()) playerYaw = yaw;
}

void VR_SetHMDPosition(float x, float y, float z)
{
	VectorSet(hmdPosition, x, y, z);
	positionDeltaThisFrame[0] = (worldPosition[0] - x);
	positionDeltaThisFrame[1] = (worldPosition[1] - y);
	positionDeltaThisFrame[2] = (worldPosition[2] - z);
	worldPosition[0] = x; worldPosition[1] = y; worldPosition[2] = z;
}

void VR_GetMove(float *joy_forward, float *joy_side, float *hmd_forward, float *hmd_side, float *up,
				float *yaw, float *pitch, float *roll)
{
	*joy_forward = remote_movementForward;
	*hmd_forward = positional_movementForward;
	*up = remote_movementUp;
	*joy_side = remote_movementSideways;
	*hmd_side = positional_movementSideways;
	*yaw = cinemamode ? cinemamodeYaw : hmdorientation[YAW] + snapTurn;
	*pitch = cinemamode ? cinemamodePitch : hmdorientation[PITCH];
	*roll = cinemamode ? 0.0f : hmdorientation[ROLL];
}

void VR_FrameSetup() {}

// Per-eye FOV a Quest-like runtime would report (symmetric 90x90 here)
static XrFovf g_fov = { -0.785398f, 0.785398f, 0.785398f, -0.785398f };
static float fov_y = 90.0f;
float QzDoom_GetFOV() { return fov_y; }

bool VR_GetVRProjection(int eye, float zNear, float zFar, float *projection)
{
	XrMatrix4x4f m;
	XrMatrix4x4f_CreateProjectionFov(&m, GRAPHICS_OPENGL_ES, g_fov, zNear, zFar);
	memcpy(projection, m.m, 16 * sizeof(float));
	return true;
}

void VR_ExternalHapticEvent(const char *event, int position, int flags, int intensity, float angle, float yHeight) {}
void VR_HapticStopEvent(const char *event) {}
void VR_HapticEnable() {}
void VR_HapticDisable() {}
void VR_HapticEvent(const char *event, int position, int intensity, float angle, float yHeight) {}
void VR_HapticUpdateEvent(const char *event, int intensity, float angle) {}
void VR_HapticEndFrame() {}
extern "C" {
void jni_haptic_event(const char *event, int position, int intensity, float angle, float yHeight) {}
void jni_haptic_updateevent(const char *event, int intensity, float angle) {}
void jni_haptic_stopevent(const char *event) {}
void jni_haptic_endframe() {}
void jni_haptic_enable() {}
void jni_haptic_disable() {}
}
void jni_shutdown() { exit(0); }
void VR_Shutdown() { jni_shutdown(); }

// ---- pose math copied verbatim from TBXR_Common.cpp by build.sh ----
#include "tbxr_math.inc"

// ---- controllers (replaces OpenXrInput.cpp TBXR_UpdateControllers) ------
static void FillRemote(ovrInputStateTrackedRemote *r, float trig, float grip, int raw, const char *stick)
{
	memset(r, 0, sizeof(*r));
	r->Buttons = (uint32_t)raw;
	r->IndexTrigger = trig; r->GripTrigger = grip;
	if (trig > 0.5f) r->Buttons |= xrButton_Trigger;
	if (grip > 0.5f) r->Buttons |= xrButton_GripTrigger;
	sscanf(stick, "%f %f", &r->Joystick.x, &r->Joystick.y);
}

void TBXR_UpdateControllers()
{
	for (int i = 0; i < 2; i++)
	{
		ovrTrackedController &c = gAppState.TrackedController[i];
		memset(&c, 0, sizeof(c));
		c.Active = GL_TRUE;
		c.Pose = ParsePose(i == 0 ? *qz_lhand : *qz_rhand);
		c.Velocity.type = XR_TYPE_SPACE_VELOCITY;
	}
	leftRemoteTracking_new = gAppState.TrackedController[0];
	rightRemoteTracking_new = gAppState.TrackedController[1];
	FillRemote(&leftTrackedRemoteState_new, qz_ltrigger, qz_lgrip, qz_lbuttons, *qz_lstick);
	FillRemote(&rightTrackedRemoteState_new, qz_rtrigger, qz_rgrip, qz_rbuttons, *qz_rstick);
}

void VR_HandleControllerInput()
{
	TBXR_UpdateControllers();
	switch (vr_control_scheme)
	{
	case RIGHT_HANDED_DEFAULT:
		HandleInput_Default(vr_control_scheme,
			&rightTrackedRemoteState_new, &rightTrackedRemoteState_old, &rightRemoteTracking_new,
			&leftTrackedRemoteState_new, &leftTrackedRemoteState_old, &leftRemoteTracking_new,
			xrButton_A, xrButton_B, xrButton_X, xrButton_Y);
		break;
	case LEFT_HANDED_DEFAULT:
	case LEFT_HANDED_ALT:
		HandleInput_Default(vr_control_scheme,
			&leftTrackedRemoteState_new, &leftTrackedRemoteState_old, &leftRemoteTracking_new,
			&rightTrackedRemoteState_new, &rightTrackedRemoteState_old, &rightRemoteTracking_new,
			xrButton_X, xrButton_Y, xrButton_A, xrButton_B);
		break;
	}
}

// ---- TBXR_* -------------------------------------------------------------
double TBXR_GetTimeInMilliSeconds()
{
	struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
	return (now.tv_sec * 1e9 + now.tv_nsec) * 1e-6;
}
int TBXR_GetRefresh() { return 72; }
void TBXR_Recenter() {}
void TBXR_GetScreenRes(int *width, int *height) { *width = g_width; *height = g_height; }
void TBXR_Vibrate(int duration, int channel, float intensity) {}
void TBXR_ProcessHaptics() {}
void TBXR_updateProjections() {}
XrInstance TBXR_GetXrInstance() { return XR_NULL_HANDLE; }

static void TBXR_GetHMDOrientation()
{
	XrPosef head = ParsePose(*qz_hmd);
	gAppState.xfStageFromHead = head;
	vec3_t rotation = {0, 0, 0};
	vec3_t hmdorient = {0, 0, 0};
	QuatToYawPitchRoll(head.orientation, rotation, hmdorient);
	VR_SetHMDPosition(head.position.x, head.position.y, head.position.z);
	VR_SetHMDOrientation(hmdorient[0], hmdorient[1], hmdorient[2]);
}

bool TBXR_FrameSetup()
{
	if (gAppState.FrameSetupRefCount > 0) return false;
	VR_FrameSetup();
	TBXR_GetHMDOrientation();
	VR_HandleControllerInput();
	TBXR_ProcessHaptics();
	gAppState.FrameSetupRefCount++;
	return true;
}

void TBXR_prepareEyeBuffer(int eye)
{
	glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
	glEnable(GL_SCISSOR_TEST);
	glViewport(0, 0, g_width, g_height);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glScissor(0, 0, g_width, g_height);
	glClear(GL_COLOR_BUFFER_BIT);
	glScissor(0, 0, 0, 0);
	glDisable(GL_SCISSOR_TEST);
}


// ---- TEST ONLY: frame dump. "qz_shot <path.ppm>" writes the next eye-0 buffer (RGB, binary PPM) ----
static char g_shotPath[1024];
static int g_shotEye = 0;
CCMD(qz_shot)
{
	if (argv.argc() < 2) { fprintf(stderr, "qz_shot <file.ppm> [eye]\n"); return; }
	strncpy(g_shotPath, argv[1], sizeof(g_shotPath) - 1); g_shotPath[sizeof(g_shotPath) - 1] = 0;
	g_shotEye = argv.argc() > 2 ? atoi(argv[2]) : 0;
}
static void qz_dumpEye(int eye)
{
	if (!g_shotPath[0] || eye != g_shotEye) return;
	unsigned char *px = (unsigned char *)malloc((size_t)g_width * g_height * 4);
	glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
	glReadPixels(0, 0, g_width, g_height, GL_RGBA, GL_UNSIGNED_BYTE, px);
	FILE *f = fopen(g_shotPath, "wb");
	if (f)
	{
		fprintf(f, "P6\n%d %d\n255\n", g_width, g_height);
		for (int y = g_height - 1; y >= 0; y--)
			for (int x = 0; x < g_width; x++) fwrite(px + ((size_t)y * g_width + x) * 4, 1, 3, f);
		fclose(f);
		fprintf(stderr, "qzlinux: wrote %s (eye %d, %dx%d)\n", g_shotPath, eye, g_width, g_height);
	}
	free(px);
	g_shotPath[0] = 0;
}

void TBXR_finishEyeBuffer(int eye)
{
	qz_dumpEye(eye);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void TBXR_submitFrame()
{
	if (gAppState.FrameSetupRefCount == 0) return;
	fov_y = (fabs(g_fov.angleUp) + fabs(g_fov.angleDown)) * 180.0f / M_PI;
	gAppState.FrameSetupRefCount--;
}

// ---- EGL context ----------------------------------------------------------
static void InitEGL()
{
	EGLDisplay dpy = EGL_NO_DISPLAY;
	PFNEGLGETPLATFORMDISPLAYEXTPROC getPlat =
		(PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
	if (!getenv("QZ_EGL_X11") && getPlat) dpy = getPlat(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
	if (dpy == EGL_NO_DISPLAY) dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	EGLint maj, min;
	if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, &maj, &min)) { fprintf(stderr, "qzlinux: EGL init failed\n"); exit(1); }
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint cfgattr[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 8, EGL_NONE };
	EGLConfig cfg; EGLint n = 0;
	if (!eglChooseConfig(dpy, cfgattr, &cfg, 1, &n) || n == 0)
	{
		EGLint cfg2[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE };
		if (!eglChooseConfig(dpy, cfg2, &cfg, 1, &n) || n == 0) { fprintf(stderr, "qzlinux: no EGL config\n"); exit(1); }
	}
	EGLint ctxattr[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 2, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxattr);
	if (ctx == EGL_NO_CONTEXT) { fprintf(stderr, "qzlinux: eglCreateContext failed\n"); exit(1); }
	EGLint pb[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
	EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, pb);
	if (!eglMakeCurrent(dpy, surf, surf, ctx)) { fprintf(stderr, "qzlinux: eglMakeCurrent failed\n"); exit(1); }

	glGenFramebuffers(1, &g_fbo);
	glGenRenderbuffers(1, &g_color);
	glGenRenderbuffers(1, &g_depth);
	glBindRenderbuffer(GL_RENDERBUFFER, g_color);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, g_width, g_height);
	glBindRenderbuffer(GL_RENDERBUFFER, g_depth);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, g_width, g_height);
	glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, g_color);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, g_depth);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	fprintf(stderr, "qzlinux: EGL %d.%d, GL_RENDERER=%s, GL_VERSION=%s\n", maj, min,
		(const char *)glGetString(GL_RENDERER), (const char *)glGetString(GL_VERSION));
}

// ---- fatal error / crash reporting ------------------------------------------
// Linker --wrap of I_ShowFatalError (posix/nosdl/i_system.cpp): non-zero exit code on fatal errors.
static bool g_fatal = false;
extern void __real__Z16I_ShowFatalErrorPKc(const char *message) __asm__("__real__Z16I_ShowFatalErrorPKc");
extern "C" void __wrap__Z16I_ShowFatalErrorPKc(const char *message)
{
	g_fatal = true;
	fprintf(stderr, "qzlinux: FATAL: %s\n", message);
	__real__Z16I_ShowFatalErrorPKc(message);
}

extern FILE *Logfile;
static void qz_crash(int sig)
{
	void *bt[64]; int n = backtrace(bt, 64);
	const char *msg = "\nqzlinux: *** CRASH: signal %d (%s) - engine crashed (on Quest this would exit to home) ***\n";
	fprintf(stderr, msg, sig, strsignal(sig));
	backtrace_symbols_fd(bt, n, 2);
	if (Logfile) { fprintf(Logfile, msg, sig, strsignal(sig)); fflush(Logfile); backtrace_symbols_fd(bt, n, fileno(Logfile)); }
	signal(sig, SIG_DFL); raise(sig);
}

void VR_DoomMain(int argc, char **argv);

int main(int argc, char **argv)
{
	if (getenv("QZ_RES")) { int w = atoi(getenv("QZ_RES")); if (w > 64) g_width = g_height = w; }
	// VR_Init()
	playerYaw = 0.0f; resetDoomYaw = true; resetPreviousPitch = true;
	remote_movementSideways = remote_movementForward = remote_movementUp = 0.0f;
	positional_movementSideways = positional_movementForward = 0.0f;
	snapTurn = 0.0f; cinemamodeYaw = cinemamodePitch = 0.0f;
	srand(time(NULL));
	shutdown = false; ready_teleport = false; trigger_teleport = false; cinemamode = false;

	gAppState.Width = g_width; gAppState.Height = g_height;
	static char hmd[] = "meta";
	gAppState.OpenXRHMD = hmd;
	gAppState.SessionActive = GL_TRUE;

	signal(SIGSEGV, qz_crash); signal(SIGBUS, qz_crash); signal(SIGFPE, qz_crash); signal(SIGILL, qz_crash); signal(SIGABRT, qz_crash);
	InitEGL();
	qzdoom_initialised = true;
	VR_DoomMain(argc, argv);
	return g_fatal ? 2 : 0;
}

// Android OpenAL-soft (OpenSL backend) extension used by oalsound.cpp under __ANDROID__
struct ALCdevice;
extern "C" void OpenSL_android_set_pause(ALCdevice *Device, int pause) {}
