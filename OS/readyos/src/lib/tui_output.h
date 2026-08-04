/*
 * tui_output.h - Scrollable text output helper
 */

#ifndef TUI_OUTPUT_H
#define TUI_OUTPUT_H

#include "tui.h"

#define TUI_OUTPUT_LINE_W 40

typedef struct {
    char (*lines)[TUI_OUTPUT_LINE_W + 1u];
    unsigned char cap;
    unsigned char count;
    unsigned char scroll;
} TuiOutput;

void tui_output_init(TuiOutput *out,
                     char (*lines)[TUI_OUTPUT_LINE_W + 1u],
                     unsigned char cap);
void tui_output_clear(TuiOutput *out);
void tui_output_add(TuiOutput *out, const char *text);
void tui_output_add_hex(TuiOutput *out, const unsigned char *data,
                        unsigned int len);
void tui_output_draw(TuiOutput *out, unsigned char x, unsigned char y,
                     unsigned char w, unsigned char h);
void tui_output_scroll(TuiOutput *out, signed char delta);

#endif /* TUI_OUTPUT_H */
