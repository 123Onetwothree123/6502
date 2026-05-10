/*
 * tui_output.c - Scrollable text output helper
 */

#include "tui_output.h"

#include <string.h>

static void copy_fit(char *dst, const char *src) {
    unsigned char i;

    for (i = 0u; i < TUI_OUTPUT_LINE_W && src[i] != 0; ++i) {
        dst[i] = src[i];
    }
    dst[i] = 0;
}

static void append_char(char *dst, unsigned char cap, char ch) {
    unsigned char len;

    len = (unsigned char)strlen(dst);
    if (len + 1u >= cap) {
        return;
    }
    dst[len] = ch;
    dst[(unsigned char)(len + 1u)] = 0;
}

static void append_hex2(char *dst, unsigned char cap, unsigned char value) {
    static const char hex[] = "0123456789ABCDEF";

    append_char(dst, cap, hex[(value >> 4) & 0x0Fu]);
    append_char(dst, cap, hex[value & 0x0Fu]);
}

void tui_output_init(TuiOutput *out,
                     char (*lines)[TUI_OUTPUT_LINE_W + 1u],
                     unsigned char cap) {
    out->lines = lines;
    out->cap = cap;
    out->count = 0u;
    out->scroll = 0u;
}

void tui_output_clear(TuiOutput *out) {
    out->count = 0u;
    out->scroll = 0u;
}

void tui_output_add(TuiOutput *out, const char *text) {
    unsigned char i;

    if (out->cap == 0u) {
        return;
    }
    if (out->count >= out->cap) {
        for (i = 1u; i < out->cap; ++i) {
            copy_fit(out->lines[(unsigned char)(i - 1u)], out->lines[i]);
        }
        out->count = (unsigned char)(out->cap - 1u);
    }
    copy_fit(out->lines[out->count], text);
    ++out->count;
}

void tui_output_add_hex(TuiOutput *out, const unsigned char *data,
                        unsigned int len) {
    char line[TUI_OUTPUT_LINE_W + 1u];
    unsigned int pos;
    unsigned char i;

    pos = 0u;
    while (pos < len) {
        line[0] = 0;
        append_hex2(line, sizeof(line), (unsigned char)(pos >> 8));
        append_hex2(line, sizeof(line), (unsigned char)(pos & 0xFFu));
        append_char(line, sizeof(line), ':');
        append_char(line, sizeof(line), ' ');
        for (i = 0u; i < 8u && pos + i < len; ++i) {
            append_hex2(line, sizeof(line), data[(unsigned int)(pos + i)]);
            append_char(line, sizeof(line), ' ');
        }
        tui_output_add(out, line);
        pos = (unsigned int)(pos + 8u);
    }
}

void tui_output_draw(TuiOutput *out, unsigned char x, unsigned char y,
                     unsigned char w, unsigned char h) {
    unsigned char row;
    unsigned char idx;

    for (row = 0u; row < h; ++row) {
        tui_clear_line((unsigned char)(y + row), x, w, TUI_COLOR_WHITE);
        idx = (unsigned char)(out->scroll + row);
        if (idx < out->count) {
            tui_puts_n(x, (unsigned char)(y + row), out->lines[idx], w,
                       TUI_COLOR_WHITE);
        }
    }
}

void tui_output_scroll(TuiOutput *out, signed char delta) {
    unsigned char max_scroll;

    if (out->count == 0u) {
        out->scroll = 0u;
        return;
    }
    max_scroll = out->count;
    if (delta < 0) {
        if (out->scroll > 0u) {
            --out->scroll;
        }
    } else if (delta > 0) {
        if (out->scroll + 1u < max_scroll) {
            ++out->scroll;
        }
    }
}
