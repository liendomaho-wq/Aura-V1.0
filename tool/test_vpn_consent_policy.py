"""Source policy guards only; these do NOT execute Android consent."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT / "android/app/src/androidTest/java/com/ciberdefensa/aura/VpnForwardingInstrumentationTest.java"


def test_consent_has_real_awake_foreground_preconditions_and_failure_diagnostics():
    source = TEST.read_text()
    assert "device.wakeUp()" in source
    assert "keyguard.isDeviceSecure()" in source
    assert "requestDismissKeyguard(activity, null)" in source
    assert "device.isScreenOn()" in source
    assert "device.dumpWindowHierarchy(hierarchy)" in source
    assert 'By.res("android", "button1").pkg("com.android.vpndialogs")' in source
    assert "accept.click()" in source
    assert "VpnService.prepare(context) == null" in source


def test_vpn_consent_never_becomes_an_appops_grant_or_assumption():
    source = TEST.read_text()
    for bypass in ("appops set", "pm grant", "adoptShellPermissionIdentity", "Assume.", "assumeTrue", "setTestProvider"):
        assert bypass not in source
