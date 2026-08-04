/*
 * tui_split.c - Compact list pane helpers
 */

#include "tui_split.h"

void tui_split_list(unsigned char x, unsigned char y,
                    unsigned char w, unsigned char h,
                    const char *title,
                    const char **items, unsigned char count,
                    unsigned char selected,
                    unsigned char color) {
    unsigned char row;
    unsigned char idx;
    unsigned char scroll;
    unsigned char text_color;

    scroll = 0u;
    if (selected >= h) {
        scroll = (unsigned char)(selected - h + 1u);
    }
    tui_clear_line(y, x, w, TUI_COLOR_GRAY3);
    tui_puts_n(x, y, title, w, TUI_COLOR_YELLOW);
    for (row = 1u; row < h; ++row) {
        idx = (unsigned char)(scroll + row - 1u);
        tui_clear_line((unsigned char)(y + row), x, w, TUI_COLOR_WHITE);
        if (idx >= count) {
            continue;
        }
        text_color = (idx == selected) ? TUI_COLOR_CYAN : color;
        tui_putc(x, (unsigned char)(y + row),
                 (idx == selected) ? tui_ascii_to_screen('>') : 32u,
                 text_color);
        tui_puts_n((unsigned char)(x + 1u), (unsigned char)(y + row),
                   items[idx], (unsigned char)(w - 1u), text_color);
    }
}
