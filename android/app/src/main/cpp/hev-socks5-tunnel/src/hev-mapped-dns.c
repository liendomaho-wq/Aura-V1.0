/*
 ============================================================================
 Name        : hev-mapped-dns.c
 Author      : hev <r@hev.cc>
 Copyright   : Copyright (c) 2025 hev
 Description : Mapped DNS
 ============================================================================
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <arpa/inet.h>
#ifdef __ANDROID__
#include <pthread.h>
#endif

#include <hev-compiler.h>
#include <hev-memory-allocator.h>

#include "hev-logger.h"

#include "hev-mapped-dns.h"

static HevMappedDNS *singleton;

#ifdef __ANDROID__
extern void hev_jni_report_dns_event (const char *domain, int action,
                                      uint32_t source_ipv4,
                                      uint16_t source_port);
#endif

enum
{
    DNS_EVENT_ALLOWED = 0,
    DNS_EVENT_BLOCKED = 1,
    DNS_EVENT_DGA_ALERT = 2,
    DNS_MAX_QUESTIONS = 32,
    DNS_MAX_NAME = 253,
    DNS_MAX_BLOCKED_DOMAINS = 256,
};

#ifdef __ANDROID__
static pthread_mutex_t blocked_domains_mutex = PTHREAD_MUTEX_INITIALIZER;
static char blocked_domains[DNS_MAX_BLOCKED_DOMAINS][DNS_MAX_NAME + 1];
static size_t blocked_domains_count;
#endif

typedef struct _DNSHdr DNSHdr;

struct _DNSHdr
{
    uint16_t id;
    uint16_t fl;
    uint16_t qd;
    uint16_t an;
    uint16_t ns;
    uint16_t ar;
};

struct _HevMappedDNSNode
{
    HevRBTreeNode tree;
    HevListNode list;
    char *name;
    int idx;
};

HevMappedDNS *
hev_mapped_dns_new (int net, int mask, int max)
{
    HevMappedDNS *self;
    int res;

    self = hev_malloc0 (sizeof (HevMappedDNS) + sizeof (void *) * max);
    if (!self)
        return NULL;

    res = hev_mapped_dns_construct (self, net, mask, max);
    if (res < 0) {
        hev_free (self);
        return NULL;
    }

    LOG_D ("%p mapped dns new", self);

    return self;
}

HevMappedDNS *
hev_mapped_dns_get (void)
{
    return singleton;
}

void
hev_mapped_dns_put (HevMappedDNS *self)
{
    singleton = self;
}

static HevMappedDNSNode *
hev_mapped_dns_node_alloc (const char *name)
{
    HevMappedDNSNode *node;

    node = hev_malloc0 (sizeof (HevMappedDNSNode));
    if (!node)
        return NULL;

    node->name = strdup (name);
    if (!node->name) {
        free (node);
        return NULL;
    }

    return node;
}

static void
hev_mapped_dns_node_free (HevMappedDNSNode *node)
{
    free (node->name);
    hev_free (node);
}

static int
hev_mapped_dns_find (HevMappedDNS *self, const char *name)
{
    HevRBTreeNode **new = &self->tree.root, *parent = NULL;
    HevMappedDNSNode *node;
    int idx = self->use;

    while (*new) {
        int res;

        node = container_of (*new, HevMappedDNSNode, tree);
        res = strcmp (node->name, name);
        parent = *new;

        if (res < 0) {
            new = &((*new)->left);
        } else if (res > 0) {
            new = &((*new)->right);
        } else {
            hev_list_del (&self->list, &node->list);
            hev_list_add_tail (&self->list, &node->list);
            return node->idx;
        }
    }

    node = hev_mapped_dns_node_alloc (name);
    if (!node)
        return -1;

    hev_rbtree_node_link (&node->tree, parent, new);
    hev_rbtree_insert_color (&self->tree, &node->tree);
    hev_list_add_tail (&self->list, &node->list);

    if (self->use < self->max) {
        self->use++;
    } else {
        HevMappedDNSNode *nf;
        HevListNode *nl;

        nl = hev_list_first (&self->list);
        nf = container_of (nl, HevMappedDNSNode, list);

        idx = nf->idx;
        hev_rbtree_erase (&self->tree, &nf->tree);
        hev_list_del (&self->list, &nf->list);
        hev_mapped_dns_node_free (nf);
    }

    self->records[idx] = node;
    node->idx = idx;

    return node->idx;
}

static inline uint16_t
read_u16 (const uint8_t *p)
{
    return ((uint16_t)p[0] << 8) | p[1];
}

static inline void
write_u16 (uint8_t *p, uint16_t v)
{
    p[0] = v >> 8;
    p[1] = v;
}

static inline void
write_u32 (uint8_t *p, uint32_t v)
{
    p[0] = v >> 24;
    p[1] = v >> 16;
    p[2] = v >> 8;
    p[3] = v;
}

static int
read_qname (const uint8_t *packet, int packet_len, int *offset,
            char domain[DNS_MAX_NAME + 1])
{
    int off = *offset;
    int name_len = 0;

    for (;;) {
        int label_len;
        int i;

        if (off >= packet_len)
            return -1;
        label_len = packet[off++];
        if (!label_len)
            break;
        if ((label_len & 0xc0) || label_len > 63 ||
            off + label_len > packet_len)
            return -1;
        if (name_len && name_len + 1 >= DNS_MAX_NAME)
            return -1;
        if (name_len)
            domain[name_len++] = '.';
        if (name_len + label_len > DNS_MAX_NAME)
            return -1;
        for (i = 0; i < label_len; i++) {
            const unsigned char ch = packet[off++];
            if (ch <= 0x20 || ch >= 0x7f)
                return -1;
            domain[name_len++] = (char)tolower (ch);
        }
    }

    if (!name_len)
        return -1;
    domain[name_len] = '\0';
    *offset = off;
    return 0;
}

static int
domain_is_suspicious (const char *domain)
{
    const char *label = domain;

    while (*label) {
        unsigned char seen[128] = { 0 };
        const char *end = strchr (label, '.');
        const size_t length = end ? (size_t)(end - label) : strlen (label);
        size_t i;
        unsigned int digits = 0;
        unsigned int unique = 0;

        if (length >= 40) {
            for (i = 0; i < length; i++) {
                const unsigned char ch = (unsigned char)label[i];
                if (ch < sizeof (seen) && !seen[ch]) {
                    seen[ch] = 1;
                    unique++;
                }
                if (ch >= '0' && ch <= '9')
                    digits++;
            }
            if (unique >= 20 && digits >= 4)
                return 1;
        }

        if (!end)
            break;
        label = end + 1;
    }

    return 0;
}

#ifdef __ANDROID__
static int
normalize_domain (const char *domain, char normalized[DNS_MAX_NAME + 1])
{
    size_t length, label_length = 0, i;

    if (!domain)
        return -1;
    length = strlen (domain);
    if (length && domain[length - 1] == '.')
        length--;
    if (!length || length > DNS_MAX_NAME)
        return -1;

    for (i = 0; i < length; i++) {
        const unsigned char ch = (unsigned char)domain[i];
        if (ch == '.') {
            if (!label_length || label_length > 63 || normalized[i - 1] == '-')
                return -1;
            label_length = 0;
            normalized[i] = '.';
        } else if ((ch >= 'a' && ch <= 'z') ||
                   (ch >= 'A' && ch <= 'Z') ||
                   (ch >= '0' && ch <= '9') || ch == '-') {
            if (!label_length && ch == '-')
                return -1;
            normalized[i] = (char)tolower (ch);
            label_length++;
            if (label_length > 63)
                return -1;
        } else {
            return -1;
        }
    }
    if (!label_length || normalized[length - 1] == '-')
        return -1;
    normalized[length] = '\0';
    return 0;
}
#endif

int
hev_mapped_dns_block_domain (const char *domain)
{
#ifdef __ANDROID__
    char normalized[DNS_MAX_NAME + 1];
    size_t i;

    if (normalize_domain (domain, normalized) < 0)
        return -1;
    pthread_mutex_lock (&blocked_domains_mutex);
    for (i = 0; i < blocked_domains_count; i++) {
        if (0 == strcmp (blocked_domains[i], normalized)) {
            pthread_mutex_unlock (&blocked_domains_mutex);
            return 1;
        }
    }
    if (blocked_domains_count >= DNS_MAX_BLOCKED_DOMAINS) {
        pthread_mutex_unlock (&blocked_domains_mutex);
        return 0;
    }
    memcpy (blocked_domains[blocked_domains_count++], normalized,
            strlen (normalized) + 1);
    pthread_mutex_unlock (&blocked_domains_mutex);
    return 1;
#else
    (void)domain;
    return -1;
#endif
}

int
hev_mapped_dns_is_blocked (const char *domain)
{
#ifdef __ANDROID__
    char normalized[DNS_MAX_NAME + 1];
    size_t i;
    int blocked = 0;

    if (normalize_domain (domain, normalized) < 0)
        return 0;
    pthread_mutex_lock (&blocked_domains_mutex);
    for (i = 0; i < blocked_domains_count; i++) {
        if (0 == strcmp (blocked_domains[i], normalized)) {
            blocked = 1;
            break;
        }
    }
    pthread_mutex_unlock (&blocked_domains_mutex);
    return blocked;
#else
    (void)domain;
    return 0;
#endif
}

int
hev_mapped_dns_handle (HevMappedDNS *self, void *req, int qlen, void *res,
                       int slen, uint32_t source_ipv4, uint16_t source_port)
{
    typedef struct
    {
        int name_offset;
        uint16_t type;
        uint16_t class;
        char name[DNS_MAX_NAME + 1];
        int dga_alert;
        int blocked;
    } DNSQuestion;
    const uint8_t *rb = req;
    uint8_t *sb = res;
    DNSQuestion questions[DNS_MAX_QUESTIONS];
    uint16_t qd;
    uint16_t query_flags;
    uint16_t answer_count = 0;
    int has_blocked_question = 0;
    int off;
    int i;

    if (qlen < 0 || (size_t)qlen < sizeof (DNSHdr))
        return -1;
    qd = read_u16 (rb + 4);
    query_flags = read_u16 (rb + 2);
    if (!qd || qd > DNS_MAX_QUESTIONS || (query_flags & 0x8000))
        return -1;

    off = sizeof (DNSHdr);
    for (i = 0; i < qd; i++) {
        questions[i].name_offset = off;
        if (read_qname (rb, qlen, &off, questions[i].name) < 0 ||
            off + 4 > qlen)
            return -1;
        questions[i].type = read_u16 (rb + off);
        questions[i].class = read_u16 (rb + off + 2);
        off += 4;
    }

    if (off > slen)
        return -1;
    memcpy (sb, rb, off);
    for (i = 0; i < qd; i++) {
        questions[i].dga_alert = questions[i].class == 1 &&
            domain_is_suspicious (questions[i].name);
        questions[i].blocked = questions[i].class == 1 &&
            (hev_mapped_dns_is_blocked (questions[i].name) ||
             questions[i].dga_alert);
        if (questions[i].blocked)
            has_blocked_question = 1;
    }

    /* A DNS response has one RCODE for the entire message. If any question
     * is blocked, return NXDOMAIN with no answers, including for mixed-query
     * messages. Never resolve a blocked name to a device's loopback services. */
    if (has_blocked_question) {
#ifdef __ANDROID__
        for (i = 0; i < qd; i++) {
            if (questions[i].blocked)
                hev_jni_report_dns_event (questions[i].name,
                                          questions[i].dga_alert ?
                                              DNS_EVENT_DGA_ALERT : DNS_EVENT_BLOCKED,
                                          source_ipv4, source_port);
        }
#endif
        write_u16 (sb + 2, (uint16_t)(0x8080 | (query_flags & 0x7910) | 3));
        write_u16 (sb + 6, 0);
        write_u16 (sb + 8, 0);
        write_u16 (sb + 10, 0);
        return off;
    }

    for (i = 0; i < qd; i++) {
        uint32_t mapped_ip;
        int idx;

#ifdef __ANDROID__
        hev_jni_report_dns_event (questions[i].name, DNS_EVENT_ALLOWED,
                                  source_ipv4, source_port);
#endif

        if (questions[i].class != 1 || questions[i].type != 1)
            continue;
        idx = hev_mapped_dns_find (self, questions[i].name);
        if (idx < 0)
            continue;
        mapped_ip = (uint32_t)(self->net | idx);

        if (off + 16 > slen || questions[i].name_offset >= 0x4000)
            return -1;
        write_u16 (sb + off, (uint16_t)(0xc000 | questions[i].name_offset));
        write_u16 (sb + off + 2, 1);
        write_u16 (sb + off + 4, 1);
        write_u32 (sb + off + 6, 1);
        write_u16 (sb + off + 10, 4);
        write_u32 (sb + off + 12, mapped_ip);
        off += 16;
        answer_count++;
    }

    write_u16 (sb + 2, (uint16_t)(0x8080 | (query_flags & 0x7910)));
    write_u16 (sb + 6, answer_count);
    write_u16 (sb + 8, 0);
    write_u16 (sb + 10, 0);

    return off;
}

const char *
hev_mapped_dns_lookup (HevMappedDNS *self, int ip)
{
    HevMappedDNSNode *node;
    int idx;

    idx = ip & ~self->mask;
    if (idx >= self->max)
        return NULL;

    node = self->records[idx];
    if (!node)
        return NULL;

    hev_list_del (&self->list, &node->list);
    hev_list_add_tail (&self->list, &node->list);

    return node->name;
}

int
hev_mapped_dns_construct (HevMappedDNS *self, int net, int mask, int max)
{
    int res;

    res = hev_object_construct (&self->base);
    if (res < 0)
        return res;

    LOG_D ("%p mapped dns construct", self);

    HEV_OBJECT (self)->klass = HEV_MAPPED_DNS_TYPE;

    if (max > ~mask)
        return -1;

    self->max = max;
    self->net = net;
    self->mask = mask;

    return 0;
}

static void
hev_mapped_dns_destruct (HevObject *base)
{
    HevMappedDNS *self = HEV_MAPPED_DNS (base);
    HevListNode *n;

    LOG_D ("%p mapped dns destruct", self);

    n = hev_list_first (&self->list);
    while (n) {
        HevMappedDNSNode *t;

        t = container_of (n, HevMappedDNSNode, list);
        n = hev_list_node_next (n);
        hev_mapped_dns_node_free (t);
    }

    HEV_OBJECT_TYPE->destruct (base);
    hev_free (base);
}

HevObjectClass *
hev_mapped_dns_class (void)
{
    static HevMappedDNSClass klass;
    HevMappedDNSClass *kptr = &klass;
    HevObjectClass *okptr = HEV_OBJECT_CLASS (kptr);

    if (!okptr->name) {
        memcpy (kptr, HEV_OBJECT_TYPE, sizeof (HevObjectClass));

        okptr->name = "HevMappedDNS";
        okptr->destruct = hev_mapped_dns_destruct;
    }

    return okptr;
}
