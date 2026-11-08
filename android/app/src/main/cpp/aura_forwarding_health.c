#define _GNU_SOURCE
#include "aura_forwarding_health.h"

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <linux/tcp.h>
#include <netinet/in.h>
#include <pthread.h>
#include <string.h>
#include <time.h>

static pthread_mutex_t evidence_mutex = PTHREAD_MUTEX_INITIALIZER;
static uint64_t last_egress_ms;

static uint64_t
monotonic_ms(void)
{
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
        return 0;
    return (uint64_t)value.tv_sec * UINT64_C(1000) +
           (uint64_t)value.tv_nsec / UINT64_C(1000000);
}

static int
fresh(uint64_t now, uint64_t observed)
{
    return observed != 0 && now >= observed && now - observed <= AURA_EGRESS_TTL_MS;
}

static void
record_evidence(uint64_t now)
{
    if (!now)
        return;
    pthread_mutex_lock(&evidence_mutex);
    last_egress_ms = now;
    pthread_mutex_unlock(&evidence_mutex);
}

void
aura_egress_reset(void)
{
    pthread_mutex_lock(&evidence_mutex);
    last_egress_ms = 0;
    pthread_mutex_unlock(&evidence_mutex);
}

int
aura_egress_recent(void)
{
    uint64_t observed;
    pthread_mutex_lock(&evidence_mutex);
    observed = last_egress_ms;
    pthread_mutex_unlock(&evidence_mutex);
    return fresh(monotonic_ms(), observed);
}

/* Canonicalize IPv4-mapped IPv6 so send/reply and local-address comparisons
 * cannot disagree merely because one kernel API uses AF_INET6. */
static int
endpoint(const struct sockaddr *address, socklen_t length, AuraEgressUdpPeer *out)
{
    const struct sockaddr_in *v4;
    const struct sockaddr_in6 *v6;
    uint32_t host;
    memset(out, 0, sizeof(*out));
    if (!address || length < sizeof(address->sa_family))
        return 0;
    if (address->sa_family == AF_INET && length >= sizeof(*v4)) {
        v4 = (const struct sockaddr_in *)address;
        out->family = AF_INET;
        out->port = v4->sin_port;
        memcpy(out->address, &v4->sin_addr, 4);
    } else if (address->sa_family == AF_INET6 && length >= sizeof(*v6)) {
        v6 = (const struct sockaddr_in6 *)address;
        out->port = v6->sin6_port;
        if (IN6_IS_ADDR_V4MAPPED(&v6->sin6_addr)) {
            out->family = AF_INET;
            memcpy(out->address, &v6->sin6_addr.s6_addr[12], 4);
        } else {
            if (IN6_IS_ADDR_UNSPECIFIED(&v6->sin6_addr) ||
                IN6_IS_ADDR_LOOPBACK(&v6->sin6_addr) ||
                IN6_IS_ADDR_MULTICAST(&v6->sin6_addr))
                return 0;
            out->family = AF_INET6;
            out->scope_id = v6->sin6_scope_id;
            memcpy(out->address, &v6->sin6_addr, 16);
        }
    } else {
        return 0;
    }
    if (out->family == AF_INET) {
        memcpy(&host, out->address, 4);
        host = ntohl(host);
        if ((host >> 24) == 127 || (host >> 24) == 0 || (host >> 28) >= 14)
            return 0;
    }
    return 1;
}

static int
same_address(const AuraEgressUdpPeer *left, const AuraEgressUdpPeer *right)
{
    return left->family == right->family &&
           memcmp(left->address, right->address, sizeof(left->address)) == 0 &&
           (left->family != AF_INET6 || left->scope_id == right->scope_id);
}

/* An authenticated loopback SOCKS connection, local DNS reply or even a
 * connection to another address of this same device is NOT egress proof.
 * Failure to enumerate local interfaces is conservative: evidence is refused. */
static int
remote_peer(const AuraEgressUdpPeer *peer)
{
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *entry;
    int remote = 1;
    if (getifaddrs(&interfaces) != 0)
        return 0;
    for (entry = interfaces; entry; entry = entry->ifa_next) {
        AuraEgressUdpPeer local;
        socklen_t length;
        if (!entry->ifa_addr)
            continue;
        length = entry->ifa_addr->sa_family == AF_INET6 ?
                     sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
        if (endpoint(entry->ifa_addr, length, &local) && same_address(peer, &local)) {
            remote = 0;
            break;
        }
    }
    freeifaddrs(interfaces);
    return remote;
}

void
aura_egress_observe_tcp(AuraEgressObservation *observation, int upstream_fd)
{
    struct tcp_info info;
    struct sockaddr_storage address;
    AuraEgressUdpPeer peer;
    socklen_t length;
    uint64_t now = monotonic_ms();
    if (!observation || upstream_fd < 0 || !now)
        return;
    /* Do not miss short connections before their first bidirectional payload.
     * Once confirmed, at most one TCP_INFO read per second per session. */
    if (observation->tcp_bidirectional && now >= observation->tcp_last_probe_ms &&
        now - observation->tcp_last_probe_ms < UINT64_C(1000))
        return;
    if (!observation->tcp_peer_checked) {
        length = sizeof(address);
        if (getpeername(upstream_fd, (struct sockaddr *)&address, &length) != 0)
            return;
        observation->tcp_peer_eligible =
            endpoint((struct sockaddr *)&address, length, &peer) && remote_peer(&peer);
        observation->tcp_peer_checked = 1;
    }
    if (!observation->tcp_peer_eligible)
        return;
    memset(&info, 0, sizeof(info));
    length = sizeof(info);
    if (getsockopt(upstream_fd, IPPROTO_TCP, TCP_INFO, &info, &length) != 0 ||
        length < offsetof(struct tcp_info, tcpi_data_segs_out) + sizeof(info.tcpi_data_segs_out))
        return;
    observation->tcp_last_probe_ms = now;
    /* SYN and FIN can produce acked=2/received=1 without ANY payload.
     * Require actual data-bearing segments too. A control-only close or
     * unchanged cumulative payload counters must never renew old evidence.
     * Kernels returning a shorter TCP_INFO remain conservatively unconfirmed. */
    if (aura_tcp_payload_present(info.tcpi_bytes_acked, info.tcpi_bytes_received,
                                 info.tcpi_data_segs_out, info.tcpi_data_segs_in) &&
        (info.tcpi_bytes_acked > observation->tcp_bytes_acked ||
         info.tcpi_bytes_received > observation->tcp_bytes_received) &&
        (info.tcpi_data_segs_out > observation->tcp_data_segs_out ||
         info.tcpi_data_segs_in > observation->tcp_data_segs_in)) {
        observation->tcp_bidirectional = 1;
        record_evidence(now);
    }
    observation->tcp_bytes_acked = info.tcpi_bytes_acked;
    observation->tcp_bytes_received = info.tcpi_bytes_received;
    observation->tcp_data_segs_out = info.tcpi_data_segs_out;
    observation->tcp_data_segs_in = info.tcpi_data_segs_in;
}

void
aura_egress_observe_udp(AuraEgressObservation *observation, int event,
                        const struct sockaddr *address, socklen_t length,
                        size_t delivered_payload_bytes)
{
    AuraEgressUdpPeer peer;
    AuraEgressUdpPeer *match = NULL;
    AuraEgressUdpPeer *available = NULL;
    uint64_t now = monotonic_ms();
    unsigned int i;
    if (!observation || !delivered_payload_bytes || !now ||
        !endpoint(address, length, &peer))
        return;
    for (i = 0; i < AURA_EGRESS_MAX_UDP_PEERS; i++) {
        AuraEgressUdpPeer *candidate = &observation->udp_peers[i];
        if (candidate->family && candidate->port == peer.port && same_address(candidate, &peer)) {
            match = candidate;
            break;
        }
        if (!available && !fresh(now, candidate->sent_at_ms))
            available = candidate;
    }
    if (event == AURA_EGRESS_UDP_SENT) {
        if (!match) {
            /* Refuse new observations when full; never allocate per packet or
             * drop application traffic just because the evidence table is full.
             * Negative eligibility is cached too, bounding interface scans. */
            if (!available)
                return;
            match = available;
            *match = peer;
            match->eligible = remote_peer(&peer);
        }
        match->sent_at_ms = now;
    } else if (event == AURA_EGRESS_UDP_REPLY_DELIVERED && match && match->eligible &&
               fresh(now, match->sent_at_ms)) {
        /* The HEV server calls this only AFTER a matching remote datagram was
         * received and its payload delivered back into the SOCKS/TUN path. */
        record_evidence(now);
    }
}
