/*
 * tui_controls.h - Small focusable form controls for ReadyOS TUIs
 */

#ifndef TUI_CONTROLS_H
#define TUI_CONTROLS_H

#include "tui.h"

#define TUI_CTRL_TEXT   1
#define TUI_CTRL_BYTE   2
#define TUI_CTRL_WORD   3
#define TUI_CTRL_DWORD  4
#define TUI_CTRL_TOGGLE 5
#define TUI_CTRL_ENUM   6
#define TUI_CTRL_FLAGS  7

typedef struct {
    const char *label;
    unsigned char kind;
    unsigned int value_lo;
    unsigned int value_hi;
    unsigned int min_value;
    unsigned int max_value;
    char *text;
    unsigned char text_cap;
    unsigned char cursor;
    const char **choices;
    unsigned char choice_count;
} TuiControlField;

typedef struct {
    TuiControlField *fields;
    unsigned char count;
    unsigned char focus;
    unsigned char x;
    unsigned char y;
    unsigned char w;
    unsigned char h;
} TuiControlForm;

void tui_form_init(TuiControlForm *form, TuiControlField *fields,
                   unsigned char count, unsigned char x, unsigned char y,
                   unsigned char w, unsigned char h);
void tui_form_draw(TuiControlForm *form);
unsigned char tui_form_key(TuiControlForm *form, unsigned char key);
void tui_form_set_u32(TuiControlField *field,
                      unsigned int lo, unsigned int hi);
void tui_form_get_u32(const TuiControlField *field,
                      unsigned int *lo, unsigned int *hi);

#endif /* TUI_CONTROLS_H */
