#include "ucitest_uci.h"

#define UCI_STAT_DATA  0x80
#define UCI_STAT_STAT  0x40
#define UCI_STATE_MASK 0x30
#define UCI_STATE_IDLE 0x00
#define UCI_STATE_LAST 0x20
#define UCI_STATE_MORE 0x30
#define UCI_STAT_ABORT 0x04
#define UCI_STAT_ERROR 0x08

#define UCI_WAIT_SHORT  1200u
#define UCI_WAIT_LONG   7000u

static unsigned int uci_base_addr;

static unsigned char id_matches(unsigned char id) {
    return (unsigned char)((id & UCITEST_UCI_ID_MASK) == UCITEST_UCI_ID_MATCH);
}

static unsigned char probe_base(unsigned int base) {
    ucitest_uci_asm_set_base(base);
    if (id_matches(ucitest_uci_asm_id())) {
        uci_base_addr = base;
        return 1u;
    }
    return 0u;
}

static unsigned char wait_idle(void) {
    unsigned int tries;
    unsigned char st;

    for (tries = 0u; tries < UCI_WAIT_LONG; ++tries) {
        st = ucitest_uci_asm_status();
        if ((st & UCI_STAT_ERROR) != 0u) {
            ucitest_uci_asm_clear_error();
        }
        if ((st & UCI_STATE_MASK) == UCI_STATE_IDLE && (st & 0x01u) == 0u) {
            return 1u;
        }
    }
    return 0u;
}

static unsigned char wait_data_state(void) {
    unsigned int tries;
    unsigned char st;
    unsigned char state;

    for (tries = 0u; tries < UCI_WAIT_LONG; ++tries) {
        st = ucitest_uci_asm_status();
        if ((st & UCI_STAT_ERROR) != 0u) {
            return 0u;
        }
        state = (unsigned char)(st & UCI_STATE_MASK);
        if (state == UCI_STATE_LAST || state == UCI_STATE_MORE ||
            state == UCI_STATE_IDLE) {
            return 1u;
        }
    }
    return 0u;
}

static unsigned char sync_interface(void) {
    unsigned int tries;
    unsigned char st;
    unsigned char state;

    for (tries = 0u; tries < UCI_WAIT_SHORT; ++tries) {
        st = ucitest_uci_asm_status();
        state = (unsigned char)(st & UCI_STATE_MASK);

        if ((st & UCI_STAT_ERROR) != 0u) {
            ucitest_uci_asm_clear_error();
            tries = 0u;
            continue;
        }
        if ((st & UCI_STAT_ABORT) != 0u) {
            ucitest_uci_asm_abort();
            tries = 0u;
            continue;
        }
        if ((st & UCI_STAT_DATA) != 0u) {
            (void)ucitest_uci_asm_read_data();
            tries = 0u;
            continue;
        }
        if ((st & UCI_STAT_STAT) != 0u) {
            (void)ucitest_uci_asm_read_stat();
            tries = 0u;
            continue;
        }
        if (state == UCI_STATE_LAST || state == UCI_STATE_MORE) {
            ucitest_uci_asm_accept_data();
            tries = 0u;
            continue;
        }
        if (state == UCI_STATE_IDLE && (st & 0x01u) == 0u) {
            return 1u;
        }
    }

    ucitest_uci_asm_abort();
    return wait_idle();
}

unsigned char ucitest_uci_detect(void) {
    static const unsigned int bases[] = {
        0xDF1Cu,
        0xDE1Cu,
        0xDFFCu
    };
    unsigned char i;

    if (uci_base_addr != 0u) {
        if (probe_base(uci_base_addr)) {
            return 1u;
        }
        uci_base_addr = 0u;
    }
    for (i = 0u; i < sizeof(bases) / sizeof(bases[0]); ++i) {
        if (probe_base(bases[i])) {
            return 1u;
        }
    }
    return 0u;
}

unsigned int ucitest_uci_base(void) {
    if (!ucitest_uci_detect()) {
        return 0u;
    }
    return uci_base_addr;
}

unsigned char ucitest_uci_id(void) {
    if (!ucitest_uci_detect()) {
        return 0u;
    }
    return ucitest_uci_asm_id();
}

unsigned char ucitest_uci_status(void) {
    if (!ucitest_uci_detect()) {
        return 0u;
    }
    return ucitest_uci_asm_status();
}

void ucitest_uci_abort(void) {
    if (ucitest_uci_detect()) {
        ucitest_uci_asm_abort();
    }
}

void ucitest_uci_clear_error(void) {
    if (ucitest_uci_detect()) {
        ucitest_uci_asm_clear_error();
    }
}

unsigned char ucitest_uci_command(const unsigned char *cmd,
                                  unsigned int cmd_len,
                                  UciTestTransfer *xfer) {
    unsigned int i;
    unsigned char st;
    unsigned char state;
    unsigned int drain_guard;

    if (xfer != 0) {
        xfer->data_len = 0u;
        xfer->stat_len = 0u;
        xfer->flags = 0u;
        xfer->last_status = 0u;
    }
    if (!ucitest_uci_detect() || cmd == 0 || cmd_len == 0u) {
        return 0u;
    }
    if (!sync_interface()) {
        ucitest_uci_asm_abort();
        if (!wait_idle()) {
            if (xfer != 0) {
                xfer->flags |= UCITEST_UCI_TIMEOUT;
            }
            return 0u;
        }
    }

    for (i = 0u; i < cmd_len; ++i) {
        ucitest_uci_asm_write_cmd(cmd[i]);
    }
    ucitest_uci_asm_push_cmd();

    if (!wait_data_state()) {
        ucitest_uci_asm_abort();
        if (xfer != 0) {
            xfer->flags |= UCITEST_UCI_TIMEOUT;
        }
        return 0u;
    }

    for (;;) {
        st = ucitest_uci_asm_status();
        if (xfer != 0) {
            xfer->last_status = st;
        }
        state = (unsigned char)(st & UCI_STATE_MASK);
        if (state == UCI_STATE_IDLE) {
            break;
        }
        if (state != UCI_STATE_LAST && state != UCI_STATE_MORE) {
            if (!wait_data_state()) {
                ucitest_uci_asm_abort();
                if (xfer != 0) {
                    xfer->flags |= UCITEST_UCI_TIMEOUT;
                }
                return 0u;
            }
            continue;
        }

        drain_guard = 0u;
        while (drain_guard < UCI_WAIT_SHORT) {
            st = ucitest_uci_asm_status();
            if ((st & UCI_STAT_DATA) != 0u) {
                if (xfer != 0 && xfer->data != 0 &&
                    xfer->data_len < xfer->data_cap) {
                    xfer->data[xfer->data_len] = ucitest_uci_asm_read_data();
                    ++xfer->data_len;
                } else {
                    (void)ucitest_uci_asm_read_data();
                    if (xfer != 0) {
                        xfer->flags |= UCITEST_UCI_TRUNC_DATA;
                    }
                }
                drain_guard = 0u;
                continue;
            }
            if ((st & UCI_STAT_STAT) != 0u) {
                if (xfer != 0 && xfer->stat != 0 &&
                    xfer->stat_len < xfer->stat_cap) {
                    xfer->stat[xfer->stat_len] = ucitest_uci_asm_read_stat();
                    ++xfer->stat_len;
                } else {
                    (void)ucitest_uci_asm_read_stat();
                    if (xfer != 0) {
                        xfer->flags |= UCITEST_UCI_TRUNC_STAT;
                    }
                }
                drain_guard = 0u;
                continue;
            }
            ++drain_guard;
        }

        ucitest_uci_asm_accept_data();
        if (state == UCI_STATE_LAST) {
            (void)wait_idle();
            break;
        }
        if (!wait_data_state()) {
            ucitest_uci_asm_abort();
            if (xfer != 0) {
                xfer->flags |= UCITEST_UCI_TIMEOUT;
            }
            return 0u;
        }
    }
    return 1u;
}
