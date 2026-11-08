package com.ciberdefensa.aura;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.VpnService;
import android.os.Build;
import android.os.SystemClock;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;

import hev.htproxy.TProxyService;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;
import java.util.function.BooleanSupplier;

import static org.junit.Assert.*;

/** Real Android consent, TUN, HEV, SOCKS and host TCP/UDP peers. No mock engine. */
@RunWith(AndroidJUnit4.class)
public final class VpnForwardingInstrumentationTest {
    private static final String TEST_APPLICATION_ID = "com.ciberdefensa.aura.vaultmigrationtest";
    private static final int FIXTURE_PORT = 32967;
    private static final int SOCKS_PORT = 18763;
    private Context context;
    private Activity activity;

    private static void eventually(String description, BooleanSupplier condition, long timeoutMs) {
        long deadline = SystemClock.elapsedRealtime() + timeoutMs;
        while (!condition.getAsBoolean()) {
            if (SystemClock.elapsedRealtime() >= deadline) {
                fail("Timed out waiting for actual Android state: " + description);
            }
            SystemClock.sleep(100);
        }
    }

    private static boolean flag(String name) {
        return Boolean.TRUE.equals(AuraVpnService.shieldStatus().get(name));
    }

    @Before
    public void prepareIsolatedApplicationAndRealConsent() throws Exception {
        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        // No state mutation until the separate application's UID is confirmed.
        assertEquals(TEST_APPLICATION_ID, context.getPackageName());
        assertEquals("This lane must execute real Android 16", 36, Build.VERSION.SDK_INT);
        assertTrue("The test must run as a normal application UID", android.os.Process.myUid() >= 10000);
        context.stopService(new Intent(context, AuraVpnService.class));
        eventually("previous test service stopped", () -> !flag("service_active") && flag("status_verified"), 120_000);
        Intent activityIntent = new Intent(context, VpnInstrumentationActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity = InstrumentationRegistry.getInstrumentation().startActivitySync(activityIntent);
        Intent consent = VpnService.prepare(context);
        if (consent != null) {
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> activity.startActivity(consent));
            UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
            UiObject2 checkbox = device.wait(Until.findObject(
                    By.clazz("android.widget.CheckBox").pkg("com.android.vpndialogs")), 1_000);
            if (checkbox != null && !checkbox.isChecked()) checkbox.click();
            UiObject2 accept = device.wait(Until.findObject(
                    By.res("android", "button1").pkg("com.android.vpndialogs")), 30_000);
            assertNotNull("Real system VPN consent dialog was not displayed", accept);
            accept.click();
            eventually("system VPN consent", () -> VpnService.prepare(context) == null, 30_000);
        }
    }

    private void startRealTunnel() {
        Intent start = new Intent(context, AuraVpnService.class)
                .putExtra(AuraVpnService.EXTRA_START_REQUEST_ID, "instrumentation-" + UUID.randomUUID());
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(start);
        else context.startService(start);
        eventually("live worker and valid TUN", () -> flag("forwarding_ready"), 120_000);
        assertTrue(flag("status_verified"));
        assertTrue(TProxyService.TProxyIsRunning());
    }

    private Network vpnNetwork() {
        ConnectivityManager manager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        final Network[] selected = new Network[1];
        eventually("actual VPN Network", () -> {
            for (Network candidate : manager.getAllNetworks()) {
                NetworkCapabilities capabilities = manager.getNetworkCapabilities(candidate);
                if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                    selected[0] = candidate;
                    return true;
                }
            }
            return false;
        }, 30_000);
        return selected[0];
    }

    private static byte[] payload() {
        return ("AURA-VPN-TEST:" + UUID.randomUUID()).getBytes(StandardCharsets.US_ASCII);
    }

    private void tcpEcho(String address) throws Exception {
        byte[] expected = payload();
        // Explicitly bind to the VPN Network. A successful direct physical
        // socket or unrelated background DNS count cannot satisfy this test.
        try (Socket socket = vpnNetwork().getSocketFactory().createSocket()) {
            socket.connect(new InetSocketAddress(InetAddress.getByName(address), FIXTURE_PORT), 15_000);
            socket.setSoTimeout(15_000);
            DataOutputStream output = new DataOutputStream(socket.getOutputStream());
            output.writeShort(expected.length);
            output.write(expected);
            output.flush();
            DataInputStream input = new DataInputStream(socket.getInputStream());
            int length = input.readUnsignedShort();
            assertEquals(expected.length, length);
            byte[] received = new byte[length];
            input.readFully(received);
            assertArrayEquals(expected, received);
        }
    }

    private void udpEcho(String address) throws Exception {
        byte[] expected = payload();
        try (DatagramSocket socket = new DatagramSocket()) {
            vpnNetwork().bindSocket(socket);
            socket.setSoTimeout(15_000);
            InetAddress destination = InetAddress.getByName(address);
            socket.send(new DatagramPacket(expected, expected.length, destination, FIXTURE_PORT));
            DatagramPacket reply = new DatagramPacket(new byte[1200], 1200);
            socket.receive(reply);
            assertEquals(FIXTURE_PORT, reply.getPort());
            assertEquals(destination, reply.getAddress());
            assertEquals(expected.length, reply.getLength());
            byte[] received = new byte[reply.getLength()];
            System.arraycopy(reply.getData(), reply.getOffset(), received, 0, received.length);
            assertArrayEquals(expected, received);
        }
    }

    private void requireObservedEgress() {
        eventually("bidirectional remote payload evidence", () ->
                TProxyService.TProxyHasRecentEgress() && flag("forwarding_active") && flag("status_verified"),
                30_000);
    }

    private void rejectUnauthenticatedSocksClients() throws Exception {
        try (Socket socket = new Socket("127.0.0.1", SOCKS_PORT)) {
            socket.setSoTimeout(5_000);
            socket.getOutputStream().write(new byte[]{5, 1, 0});
            DataInputStream input = new DataInputStream(socket.getInputStream());
            assertEquals(5, input.readUnsignedByte());
            assertEquals(255, input.readUnsignedByte());
        }
        try (Socket socket = new Socket("127.0.0.1", SOCKS_PORT)) {
            socket.setSoTimeout(5_000);
            socket.getOutputStream().write(new byte[]{5, 1, 2});
            DataInputStream input = new DataInputStream(socket.getInputStream());
            assertEquals(5, input.readUnsignedByte());
            assertEquals(2, input.readUnsignedByte());
            socket.getOutputStream().write(new byte[]{1, 3, 'b', 'a', 'd', 3, 'b', 'a', 'd'});
            assertEquals(1, input.readUnsignedByte());
            assertNotEquals(0, input.readUnsignedByte());
        }
    }

    @Test
    public void forwardsRealTcpUdpIpv4AndRejectsUnauthenticatedProxyClients() throws Exception {
        startRealTunnel();
        rejectUnauthenticatedSocksClients();
        long[] before = TProxyService.TProxyGetStats();
        tcpEcho("10.0.2.2");
        udpEcho("10.0.2.2");
        requireObservedEgress();
        long[] after = TProxyService.TProxyGetStats();
        assertNotNull(before);
        assertNotNull(after);
        assertTrue("Actual TUN transmit bytes must increase", after[1] > before[1]);
        assertTrue("Actual TUN receive bytes must increase", after[3] > before[3]);
    }

    @Test
    public void forwardsRealTcpUdpIpv6WithoutBypassingTun() throws Exception {
        startRealTunnel();
        // QEMU/SLIRP's host IPv6 alias. An unavailable IPv6 underlay is a real
        // failed test, never an Assume/skip or a fabricated compatibility pass.
        String host = InstrumentationRegistry.getArguments().getString("fixtureIpv6", "fec0::2");
        tcpEcho(host);
        udpEcho(host);
        requireObservedEgress();
    }

    @Test
    public void recoversTerminatedNativeWorkerAndRoutesNewTraffic() throws Exception {
        startRealTunnel();
        tcpEcho("10.0.2.2");
        requireObservedEgress();
        long previousGeneration = TProxyService.TProxyWorkerGeneration();
        assertTrue(TProxyService.TProxyStopService());
        eventually("watchdog creates a new real native worker", () ->
                TProxyService.TProxyWorkerGeneration() > previousGeneration && flag("forwarding_ready"),
                120_000);
        udpEcho("10.0.2.2");
        requireObservedEgress();
    }

    @Test
    public void panicIsolationRetainsTunPreventsUdpLeakAndResumes() throws Exception {
        startRealTunnel();
        tcpEcho("10.0.2.2");
        requireObservedEgress();
        assertTrue(AuraVpnService.engagePanicIsolation());
        assertTrue(flag("isolation_active"));
        assertTrue(flag("vpn_interface_active"));
        assertFalse(flag("forwarding_active"));
        assertFalse(TProxyService.TProxyIsRunning());
        try (DatagramSocket socket = new DatagramSocket()) {
            vpnNetwork().bindSocket(socket);
            socket.setSoTimeout(2_000);
            byte[] data = payload();
            socket.send(new DatagramPacket(data, data.length, InetAddress.getByName("10.0.2.2"), FIXTURE_PORT));
            try {
                socket.receive(new DatagramPacket(new byte[1200], 1200));
                fail("UDP escaped the retained isolation TUN");
            } catch (SocketTimeoutException expected) {
                // Only a genuine receive timeout is accepted, not another I/O failure.
            }
        }
        SystemClock.sleep(2_500);
        assertFalse("Watchdog must not restart an isolated worker", TProxyService.TProxyIsRunning());
        assertTrue(AuraVpnService.resumeTunnel());
        tcpEcho("10.0.2.2");
        requireObservedEgress();
    }

    @After
    public void stopAndVerifyActualNativeAndTunCleanup() throws Exception {
        if (context == null) return;
        assertEquals(TEST_APPLICATION_ID, context.getPackageName());
        if (flag("isolation_active")) assertTrue(AuraVpnService.resumeTunnel());
        context.stopService(new Intent(context, AuraVpnService.class));
        eventually("confirmed service shutdown", () -> !flag("service_active") && flag("status_verified"), 120_000);
        Map<String, Boolean> status = AuraVpnService.shieldStatus();
        assertFalse(Boolean.TRUE.equals(status.get("vpn_interface_active")));
        assertFalse(Boolean.TRUE.equals(status.get("forwarding_active")));
        assertFalse(TProxyService.TProxyIsRunning());
        assertFalse(TProxyService.TProxyHasRecentEgress());
        try (Socket socket = new Socket()) {
            try {
                socket.connect(new InetSocketAddress("127.0.0.1", SOCKS_PORT), 2_000);
                fail("Local SOCKS listener leaked after confirmed shutdown");
            } catch (IOException expected) {
                // No listening native socket survives the stop/join contract.
            }
        } finally {
            if (activity != null) InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> activity.finish());
        }
    }
}
