#ifndef AURA_SNI_FIREWALL_H
#define AURA_SNI_FIREWALL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum
{
    AURA_TLS_SNI_INCOMPLETE = 0,
    AURA_TLS_SNI_ALLOWED = 1,
    AURA_TLS_SNI_BLOCKED = 2,
    AURA_TLS_SNI_MALFORMED = 3,
    AURA_TLS_SNI_ECH = 4
} AuraTlsSniResult;

AuraTlsSniResult aura_inspect_tls_sni (const uint8_t *payload,
                                      uint32_t payload_len, char *sni,
                                      size_t sni_capacity);
bool aura_should_block_tls_sni (const uint8_t *payload, uint32_t payload_len);
int aura_add_dynamic_sni_rule (const char *domain);
int aura_set_dynamic_sni_allowlist (const char *const *domains, size_t count);

#endif
