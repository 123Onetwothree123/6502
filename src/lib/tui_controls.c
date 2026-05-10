/*
 * tui_controls.c - Small focusable form controls for ReadyOS TUIs
 */

#include "tui_controls.h"

#include <string.h>

static char value_buf[12];

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

static void append_hex4(char *dst, unsigned char cap, unsigned int value) {
    append_hex2(dst, cap, (unsigned char)(value >> 8));
    append_hex2(dst, cap, (unsigned char)(value & 0xFFu));
}

static void format_value(const TuiControlField *field) {
    value_buf[0] = 0;
    switch (field->kind) {
        case TUI_CTRL_BYTE:
            append_char(value_buf, sizeof(value_buf), '$');
            append_hex2(value_buf, sizeof(value_buf),
                        (unsigned char)(field->value_lo & 0xFFu));
            break;
        case TUI_CTRL_WORD:
            append_char(value_buf, sizeof(value_buf), '$');
            append_hex4(value_buf, sizeof(value_buf), field->value_lo);
            break;
        case TUI_CTRL_DWORD:
            append_char(value_buf, sizeof(value_buf), '$');
            append_hex4(value_buf, sizeof(value_buf), field->value_hi);
            append_hex4(value_buf, sizeof(value_buf), field->value_lo);
            break;
        case TUI_CTRL_TOGGLE:
            if ((field->value_lo & 1u) != 0u) {
                strcpy(value_buf, "yes");
            } else {
                strcpy(value_buf, "no");
            }
            break;
        case TUI_CTRL_ENUM:
            if (field->choices != 0 && field->value_lo < field->choice_count) {
                strcpy(value_buf, field->choices[field->value_lo]);
            } else {
                append_char(value_buf, sizeof(value_buf), '$');
                append_hex2(value_buf, sizeof(value_buf),
                            (unsigned char)(field->value_lo & 0xFFu));
            }
            break;
        case TUI_CTRL_FLAGS:
            append_char(value_buf, sizeof(value_buf), '$');
            append_hex2(value_buf, sizeof(value_buf),
                        (unsigned char)(field->value_lo & 0xFFu));
            break;
        default:
            break;
    }
}

static void dec_field(TuiControlField *field) {
    if (field->kind == TUI_CTRL_DWORD && field->value_lo == 0u &&
        field->value_hi > 0u) {
        --field->value_hi;
        field->value_lo = 0xFFFFu;
        return;
    }
    if (field->value_lo > field->min_value) {
        --field->value_lo;
    }
}

static void inc_field(TuiControlField *field) {
    if (field->kind == TUI_CTRL_DWORD && field->value_lo == 0xFFFFu) {
        ++field->value_hi;
        field->value_lo = 0u;
        return;
    }
    if (field->max_value == 0u || field->value_lo < field->max_value) {
        ++field->value_lo;
    }
}

void tui_form_set_u32(TuiControlField *field,
                      unsigned int lo, unsigned int hi) {
    field->value_lo = lo;
    field->value_hi = hi;
}

void tui_form_get_u32(const TuiControlField *field,
                      unsigned int *lo, unsigned int *hi) {
    if (lo != 0) {
        *lo = field->value_lo;
    }
    if (hi != 0) {
        *hi = field->value_hi;
    }
}

void tui_form_init(TuiControlForm *form, TuiControlField *fields,
                   unsigned char count, unsigned char x, unsigned char y,
                   unsigned char w, unsigned char h) {
    form->fields = fields;
    form->count = count;
    form->focus = 0u;
    form->x = x;
    form->y = y;
    form->w = w;
    form->h = h;
}

void tui_form_draw(TuiControlForm *form) {
    unsigned char row;
    unsigned char idx;
    unsigned char color;
    unsigned char value_x;
    TuiControlField *field;

    value_x = (unsigned char)(form->x + 10u);
    for (row = 0u; row < form->h; ++row) {
        idx = row;
        tui_clear_line((unsigned char)(form->y + row), form->x, form->w,
                       TUI_COLOR_WHITE);
        if (idx >= form->count) {
            continue;
        }
        field = &form->fields[idx];
        color = (idx == form->focus) ? TUI_COLOR_CYAN : TUI_COLOR_GRAY3;
        tui_putc(form->x, (unsigned char)(form->y + row),
                 (idx == form->focus) ? tui_ascii_to_screen('>') : 32u, color);
        tui_puts_n((unsigned char)(form->x + 1u),
                   (unsigned char)(form->y + row),
                   field->label, 8u, color);
        if (field->kind == TUI_CTRL_TEXT) {
            if (field->text != 0) {
                tui_puts_n(value_x, (unsigned char)(form->y + row),
                           field->text, (unsigned char)(form->w - 10u),
                           (idx == form->focus) ? TUI_COLOR_YELLOW :
                                                   TUI_COLOR_WHITE);
            }
        } else {
            format_value(field);
            tui_puts_n(value_x, (unsigned char)(form->y + row),
                       value_buf, (unsigned char)(form->w - 10u),
                       (idx == form->focus) ? TUI_COLOR_YELLOW :
                                               TUI_COLOR_WHITE);
        }
    }
}

unsigned char tui_form_key(TuiControlForm *form, unsigned char key) {
    TuiControlField *field;
    unsigned char len;
    unsigned char i;

    if (form->count == 0u) {
        return 0u;
    }
    field = &form->fields[form->focus];

    if (key == TUI_KEY_UP) {
        if (form->focus > 0u) {
            --form->focus;
            return 1u;
        }
        return 0u;
    }
    if (key == TUI_KEY_DOWN) {
        if (form->focus + 1u < form->count) {
            ++form->focus;
            return 1u;
        }
        return 0u;
    }

    if (field->kind == TUI_CTRL_TEXT) {
        if (field->text == 0 || field->text_cap == 0u) {
            return 0u;
        }
        len = (unsigned char)strlen(field->text);
        if (key == TUI_KEY_DEL) {
            if (len > 0u) {
                field->text[(unsigned char)(len - 1u)] = 0;
                return 1u;
            }
            return 0u;
        }
        if (key >= 32u && key < 128u && len + 1u < field->text_cap) {
            field->text[len] = (char)key;
            field->text[(unsigned char)(len + 1u)] = 0;
            return 1u;
        }
        return 0u;
    }

    if (key == TUI_KEY_LEFT) {
        dec_field(field);
        return 1u;
    }
    if (key == TUI_KEY_RIGHT) {
        inc_field(field);
        return 1u;
    }
    if (key == ' ') {
        if (field->kind == TUI_CTRL_TOGGLE) {
            field->value_lo = (unsigned int)((field->value_lo == 0u) ? 1u : 0u);
            return 1u;
        }
        if (field->kind == TUI_CTRL_ENUM && field->choice_count != 0u) {
            ++field->value_lo;
            if (field->value_lo >= field->choice_count) {
                field->value_lo = 0u;
            }
            return 1u;
        }
    }
    if (key >= '0' && key <= '9') {
        if (field->kind == TUI_CTRL_BYTE || field->kind == TUI_CTRL_WORD ||
            field->kind == TUI_CTRL_FLAGS) {
            field->value_lo = (unsigned int)((field->value_lo * 10u) +
                                             (unsigned int)(key - '0'));
            if (field->max_value != 0u && field->value_lo > field->max_value) {
                field->value_lo = field->max_value;
            }
            return 1u;
        }
    }
    if (key == TUI_KEY_HOME) {
        field->value_lo = field->min_value;
        field->value_hi = 0u;
        if (field->kind == TUI_CTRL_TEXT && field->text != 0) {
            for (i = 0u; i < field->text_cap; ++i) {
                field->text[i] = 0;
            }
        }
        return 1u;
    }
    return 0u;
}
