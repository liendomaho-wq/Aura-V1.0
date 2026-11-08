/* Passive egress evidence. No destination payload or hostname is retained. */
#ifndef AURA_FORWARDING_HEALTH_H
#define AURA_FORWARDING_HEALTH_H

#include <stddef.h>
#include <stdint.h>
#include <sys/socket.h>

#define AURA_EGRESS_MAX_UDP_PEERS 16
#define AURA_EGRESS_TTL_MS UINT64_C(60000)

/* Event numbers are shared with the private HEV observer, not wire protocol. */
#define AURA_EGRESS_TICK 0
#define AURA_EGRESS_UDP_SENT 1
#define AURA_EGRESS_UDP_REPLY_DELIVERED 2

typedef struct {
    uint8_t address[16];
    uint16_t port;
    uint16_t family;
    uint32_t scope_id;
    uint64_t sent_at_ms;
    int eligible;
} AuraEgressUdpPeer;

typedef struct {
    uint64_t tcp_last_probe_ms;
    uint64_t tcp_bytes_acked;
    uint64_t tcp_bytes_received;
    int tcp_peer_checked;
    int tcp_peer_eligible;
    int tcp_bidirectional;
    AuraEgressUdpPeer udp_peers[AURA_EGRESS_MAX_UDP_PEERS];
} AuraEgressObservation;

void aura_egress_reset(void);
int aura_egress_recent(void);
void aura_egress_observe_tcp(AuraEgressObservation *observation, int upstream_fd);
void aura_egress_observe_udp(AuraEgressObservation *observation, int event,
                            const struct sockaddr *peer, socklen_t peer_len,
                            size_t delivered_payload_bytes);

#endif
