/*
 * tui_split.h - Compact list pane helpers
 */

#ifndef TUI_SPLIT_H
#define TUI_SPLIT_H

#include "tui.h"

void tui_split_list(unsigned char x, unsigned char y,
                    unsigned char w, unsigned char h,
                    const char *title,
                    const char **items, unsigned char count,
                    unsigned char selected,
                    unsigned char color);

#endif /* TUI_SPLIT_H */
