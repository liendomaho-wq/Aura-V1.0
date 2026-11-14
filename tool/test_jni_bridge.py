#!/usr/bin/env python3
"""Host test for the JNI bridge in hev-jni.c.

Native -> Java callbacks from hev-task coroutines must be marshalled to one
attached pthread (ART aborts when Java runs on a coroutine stack). This test
compiles hev-jni.c against a fake JavaVM and checks that protect/resolve run
on the bridge thread, events are delivered without blocking, the queue is
bounded and a timed-out request does not wedge later calls.

Needs a C compiler and jni.h (from $JAVA_HOME/include or $AURA_JNI_INCLUDE);
the runtime part skips otherwise. Works both as a script and under pytest:
nothing runs or exits at import time, so pytest collection stays clean.
"""
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEV = ROOT / "android/app/src/main/cpp/hev-socks5-tunnel"
JNI_PATH = HEV / "src/hev-jni.c"
REQUIRED_SNIPPETS = (
    "AttachCurrentThreadAsDaemon",
    "bridge_call (request, AURA_JNI_PROTECT_TIMEOUT_MS)",
    "bridge_call (request, AURA_JNI_RESOLVE_TIMEOUT_MS)",
    "AURA_JNI_MAX_PENDING_EVENTS",
    "if (bridge_start () < 0)",
)


class Skip(Exception):
    """The runtime harness cannot run on this host."""


def check_static_guards():
    """Static guards: no direct attach on coroutine threads."""
    source = JNI_PATH.read_text(encoding="utf-8")
    for required in REQUIRED_SNIPPETS:
        if required not in source:
            raise AssertionError("JNI bridge is missing " + required)
    if "AttachCurrentThread (" in source:
        raise AssertionError(
            "native callbacks must not AttachCurrentThread from hev-task coroutines")
    return "PASS: native callbacks are routed through the attached JNI bridge thread."


def find_toolchain():
    include_dirs = []
    for candidate in (
        os.environ.get("AURA_JNI_INCLUDE"),
        os.path.join(os.environ["JAVA_HOME"], "include") if os.environ.get("JAVA_HOME") else None,
    ):
        if candidate and Path(candidate, "jni.h").is_file():
            include_dirs.append(candidate)
            # jni_md.h lives in a platform subdirectory (linux, darwin, ...).
            for platform_dir in ("linux", "darwin", "win32"):
                if Path(candidate, platform_dir).is_dir():
                    include_dirs.append(str(Path(candidate, platform_dir)))
            break
    compiler = shutil.which("gcc") or shutil.which("cc") or shutil.which("clang")
    if not include_dirs or not compiler:
        raise Skip("gcc or jni.h unavailable; JNI bridge runtime test not executed.")
    return compiler, include_dirs


HARNESS = r"""
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <assert.h>
/* stubs for symbols referenced by hev-jni.c */
int hev_socks5_tunnel_main (const char *p, int fd) { return 0; }
void hev_socks5_tunnel_quit (void) {}
void hev_socks5_tunnel_stats (size_t *a, size_t *b, size_t *c, size_t *d) {}
void hev_socks5_tunnel_set_blocked_ipv4 (const uint32_t *a, size_t c) {}
void hev_socks5_tunnel_set_blocked_ipv6 (const uint8_t (*a)[16], size_t c) {}
int hev_socks5_tunnel_block_domain (const char *d) { return 0; }
int hev_socks5_tunnel_is_domain_blocked (const char *d) { return 0; }
int aura_add_dynamic_sni_rule (const char *d) { return 1; }
int aura_set_dynamic_sni_allowlist (const char *const *d, size_t c) { return 1; }
#include "hev-jni.c"  /* statics are exercised directly */

static __thread int attached;
static pthread_t bridge_tid; static int bridge_seen;
static int protect_calls, dns_events, protect_delay_s;
static char last_domain[256];
static struct JNINativeInterface_ fns;
static const struct JNINativeInterface_ *envp = &fns;
static struct JNIInvokeInterface_ vmfns;
static const struct JNIInvokeInterface_ *vmp = &vmfns;

static jint GetEnv_ (JavaVM *vm, void **e, jint v) { if (!attached) return JNI_EDETACHED; *e = (void*)&envp; return JNI_OK; }
static jint Attach_ (JavaVM *vm, void **e, void *a) { attached = 1; bridge_tid = pthread_self(); bridge_seen = 1; *e = (void*)&envp; return JNI_OK; }
static jint Push_ (JNIEnv *e, jint c) { return 0; }
static jobject Pop_ (JNIEnv *e, jobject r) { return NULL; }
static jboolean ExcCheck_ (JNIEnv *e) { return 0; }
static void ExcClear_ (JNIEnv *e) {}
static jboolean CallBool_ (JNIEnv *e, jclass c, jmethodID m, ...) {
    assert (attached && pthread_equal (pthread_self (), bridge_tid));
    va_list ap; va_start (ap, m); int fd = va_arg (ap, jint); va_end (ap);
    protect_calls++; if (protect_delay_s) sleep (protect_delay_s);
    return fd == 42;
}
static jstring NewStr_ (JNIEnv *e, const char *s) { return (jstring)strdup (s); }
static jobject CallObj_ (JNIEnv *e, jclass c, jmethodID m, ...) { assert (attached); return (jobject)strdup ("93.184.216.34"); }
static const char *GetUTF_ (JNIEnv *e, jstring s, jboolean *c) { return (const char*)s; }
static void RelUTF_ (JNIEnv *e, jstring s, const char *c) {}
static void CallVoid_ (JNIEnv *e, jclass c, jmethodID m, ...) {
    assert (attached);
    va_list ap; va_start (ap, m); const char *d = va_arg (ap, const char *); va_end (ap);
    snprintf (last_domain, sizeof last_domain, "%s", d); dns_events++;
}
static void *protect_from_worker (void *a) {
    /* simulates a hev-task coroutine on the never-attached worker thread */
    return (void *)(intptr_t)hev_jni_protect_socket ((int)(intptr_t)a);
}
int main (void) {
    fns.PushLocalFrame = Push_; fns.PopLocalFrame = Pop_; fns.ExceptionCheck = ExcCheck_;
    fns.ExceptionClear = ExcClear_; fns.CallStaticBooleanMethod = CallBool_; fns.NewStringUTF = NewStr_;
    fns.CallStaticObjectMethod = CallObj_; fns.GetStringUTFChars = GetUTF_; fns.ReleaseStringUTFChars = RelUTF_;
    fns.CallStaticVoidMethod = CallVoid_;
    vmfns.GetEnv = GetEnv_; vmfns.AttachCurrentThreadAsDaemon = (void*)Attach_;
    java_vm = (JavaVM *)&vmp; tproxy_class = (jclass)1; protect_socket_method = resolve_host_method =
        dns_event_method = sni_event_method = encrypted_dns_event_method = (jmethodID)1;

    /* before the bridge starts, calls fail closed instead of attaching */
    assert (hev_jni_protect_socket (42) == 0 && protect_calls == 0);
    assert (bridge_start () == 0);
    pthread_t t; void *r;
    pthread_create (&t, NULL, protect_from_worker, (void*)42); pthread_join (t, &r);
    assert ((intptr_t)r == 1 && protect_calls == 1 && bridge_seen);
    pthread_create (&t, NULL, protect_from_worker, (void*)7); pthread_join (t, &r);
    assert ((intptr_t)r == 0 && protect_calls == 2);
    char addr[64]; assert (hev_jni_resolve_host ("example.com", addr, sizeof addr) == 1);
    assert (strcmp (addr, "93.184.216.34") == 0);
    hev_jni_report_dns_event ("example.org", 0, 0x0100000a, 5353);
    for (int i = 0; i < 100 && !dns_events; i++) usleep (10000);
    assert (dns_events == 1 && strcmp (last_domain, "example.org") == 0);
    /* flood: bounded queue never blocks the caller */
    for (int i = 0; i < 5000; i++) hev_jni_report_sni_event ("a.example", "1.2.3.4", 443);
    /* timeout path: caller gives up, bridge frees the request later */
    protect_delay_s = 6;
    pthread_create (&t, NULL, protect_from_worker, (void*)42); pthread_join (t, &r);
    assert ((intptr_t)r == 0);
    protect_delay_s = 0; sleep (2);
    pthread_create (&t, NULL, protect_from_worker, (void*)42); pthread_join (t, &r);
    assert ((intptr_t)r == 1);
    printf ("BRIDGE_TEST_OK protect_calls=%d events=%d\n", protect_calls, dns_events);
    return 0;
}

"""


def run_runtime_harness():
    compiler, include_dirs = find_toolchain()
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp, "bridge_test.c")
        binary = Path(tmp, "bridge_test")
        source.write_text(HARNESS, encoding="utf-8")
        command = [
            compiler, "-g", "-D__ANDROID__", "-Wno-incompatible-pointer-types",
            *[f"-I{d}" for d in include_dirs],
            f"-I{HEV / 'src'}", f"-I{HEV.parent}", f"-I{HEV / 'src/misc'}",
            f"-I{HEV / 'src/core/include'}", f"-I{HEV / 'third-part/hev-task-system/include'}",
            str(source), "-o", str(binary), "-lpthread",
        ]
        build = subprocess.run(command, capture_output=True, text=True)
        if build.returncode != 0:
            # The harness targets the Linux/Android libc. On other hosts
            # (e.g. macOS CI runners) a host-libc mismatch is not a bridge
            # defect, so skip there; on Linux a compile error is a failure.
            if platform.system() != "Linux":
                raise Skip("JNI bridge harness does not compile on "
                           f"{platform.system()}; runtime test not executed.\n"
                           + build.stderr[-2000:])
            raise AssertionError("JNI bridge harness failed to compile\n"
                                 + build.stdout + build.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
        if result.returncode != 0 or "BRIDGE_TEST_OK" not in result.stdout:
            raise AssertionError("JNI bridge runtime test failed\n"
                                 + result.stdout + result.stderr)
    return ("PASS: JNI bridge marshals protect/resolve/events off coroutine stacks "
            "with bounded queues and timeouts.")


def test_jni_bridge_static_guards():
    check_static_guards()


def test_jni_bridge_runtime():
    import pytest

    try:
        run_runtime_harness()
    except Skip as skip:
        pytest.skip(str(skip))


def main():
    try:
        print(check_static_guards())
        print(run_runtime_harness())
    except Skip as skip:
        print("SKIP: " + str(skip))
    except AssertionError as failure:
        sys.exit("FAIL: " + str(failure))


if __name__ == "__main__":
    main()
