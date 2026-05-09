#include "../rs_edit.h"
#include "tui.h"
#include <cbm.h>
#include <conio.h>

#define SCREEN_WIDTH 40
#define PROMPT_TEXT ">"
#define PROMPT_LEN 1
#define INPUT_COLS (SCREEN_WIDTH - PROMPT_LEN)
#define PHYSICAL_MAX INPUT_COLS

#define KEY_RETURN 13
#define KEY_LEFT 157
#define KEY_RIGHT 29
#define KEY_DEL 20
#define KEY_NEXT_APP TUI_KEY_NEXT_APP
#define KEY_PREV_APP TUI_KEY_PREV_APP
#define KEY_RUNSTOP TUI_KEY_RUNSTOP

#define C_WHITE 1
#define C_YELLOW 7

static unsigned char edit_ascii_to_screen(unsigned char ascii) {
    if (ascii >= 'A' && ascii <= 'Z') return (unsigned char)(ascii - 'A' + 1);
    if (ascii >= 'a' && ascii <= 'z') return (unsigned char)(ascii - 'a' + 1);
    if (ascii >= '0' && ascii <= '9') return (unsigned char)(ascii - '0' + 48);

    switch (ascii) {
        case ' ': return 32;
        case '!': return 33;
        case '"': return 34;
        case '#': return 35;
        case '$': return 36;
        case '%': return 37;
        case '&': return 38;
        case '\'': return 39;
        case '(': return 40;
        case ')': return 41;
        case '*': return 42;
        case '+': return 43;
        case ',': return 44;
        case '-': return 45;
        case '.': return 46;
        case '/': return 47;
        case ':': return 58;
        case ';': return 59;
        case '<': return 60;
        case '=': return 61;
        case '>': return 62;
        case '?': return 63;
        case '@': return 0;
        case '[': return 27;
        case ']': return 29;
        case 124u:
        case '|': return 93;
        case '_': return 100;
        default: return 32;
    }
}

static unsigned char edit_normalize_input_key(unsigned char key) {
    switch (key) {
        case '!':
        case '^':
        case CH_LIRA:
        case CH_PI:
        case CH_VLINE:
        case CH_CURS_UP:
        case 0x01:
        case 0x81:
        case 0xA1:
        case 0xC1:
        case 0xD1:
            return '|';
        default:
            break;
    }
    return key;
}

static unsigned char edit_key_to_insert_char(unsigned char raw,
                                             unsigned char* out_char) {
    unsigned char accepted;
    unsigned char normalized;

    accepted = 0;
    if (raw >= 32 && raw <= 126) {
        accepted = 1;
    } else {
        switch (raw) {
            case CH_CURS_UP:
            case CH_PI:
            case CH_VLINE:
            case 0x81:
            case 0xA1:
            case 0xC1:
            case 0xD1:
                accepted = 1;
                break;
            default:
                break;
        }
    }

    normalized = edit_normalize_input_key(raw);
    if (!accepted) return 0;
    if (out_char) *out_char = normalized;
    return 1;
}

static void edit_draw_prompt(const char* buf, unsigned char len) {
    unsigned char col;
    unsigned char c;
    unsigned char y;

    y = rs_shell_cursor_y();
    rs_shell_clear_line(y, C_WHITE);
    rs_shell_draw_text(0, y, PROMPT_TEXT, C_YELLOW);

    for (col = 0; col < INPUT_COLS; ++col) {
        if (col < len) c = (unsigned char)buf[col];
        else c = ' ';
        rs_shell_put_ascii((unsigned char)(PROMPT_LEN + col), y, c, C_WHITE);
    }
}

static void edit_redraw_input_tail(const char* buf,
                                   unsigned char len,
                                   unsigned char from,
                                   unsigned char erase_one) {
    unsigned char to;
    unsigned char col;
    unsigned char c;
    unsigned char y;

    if (from >= INPUT_COLS) return;

    to = len;
    if (erase_one && to < INPUT_COLS) {
        ++to;
    }
    if (to > INPUT_COLS) {
        to = INPUT_COLS;
    }

    y = rs_shell_cursor_y();
    for (col = from; col < to; ++col) {
        if (col < len) c = (unsigned char)buf[col];
        else c = ' ';
        rs_shell_put_ascii((unsigned char)(PROMPT_LEN + col), y, c, C_WHITE);
    }
}

static void edit_draw_cursor_cell(const char* buf,
                                  unsigned char len,
                                  unsigned char pos,
                                  unsigned char on) {
    unsigned char c;
    unsigned char screen;

    if (pos >= INPUT_COLS) return;
    if (pos < len) c = (unsigned char)buf[pos];
    else c = ' ';

    screen = edit_ascii_to_screen(c);
    if (on) screen |= 0x80;
    rs_shell_put_char((unsigned char)(PROMPT_LEN + pos),
                      rs_shell_cursor_y(),
                      screen,
                      C_WHITE);
}

static int edit_read_physical_line(char* out, unsigned char maxlen) {
    unsigned char len;
    unsigned char pos;
    unsigned char key;
    unsigned char raw_key;
    unsigned char i;
    unsigned char insert_mode;
    unsigned char insert_ch;

    len = 0;
    pos = 0;
    insert_mode = 1;
    out[0] = 0;
    (void)kbrepeat(KBREPEAT_NONE);
    cbm_k_clrch();
    edit_draw_prompt(out, len);
    edit_draw_cursor_cell(out, len, pos, 1);

    for (;;) {
        key = (unsigned char)cgetc();
        if (key == 0) continue;
        raw_key = key;
        edit_draw_cursor_cell(out, len, pos, 0);

        if (key == 2 || key == KEY_RUNSTOP) {
            rs_shell_nav_to_launcher();
        }
        if (key == KEY_NEXT_APP) {
            rs_shell_nav_next_app();
        }
        if (key == KEY_PREV_APP) {
            rs_shell_nav_prev_app();
        }

        if (key == KEY_RETURN) {
            out[len] = 0;
            rs_shell_newline();
            return len;
        }

        if (key == KEY_LEFT || key == CH_CURS_LEFT) {
            if (pos > 0) {
                --pos;
            }
            edit_draw_cursor_cell(out, len, pos, 1);
            continue;
        }
        if (key == KEY_RIGHT || key == CH_CURS_RIGHT) {
            if (pos < len) {
                ++pos;
            }
            edit_draw_cursor_cell(out, len, pos, 1);
            continue;
        }
        if (key == CH_INS) {
            insert_mode = (unsigned char)!insert_mode;
            edit_draw_cursor_cell(out, len, pos, 1);
            continue;
        }

        if (key == KEY_DEL || key == 8 || key == 127) {
            if (pos > 0 && len > 0) {
                --pos;
                i = pos;
                while (i < len) {
                    out[i] = out[i + 1u];
                    ++i;
                }
                --len;
                edit_redraw_input_tail(out, len, pos, 1);
            }
            edit_draw_cursor_cell(out, len, pos, 1);
            continue;
        }

        if (edit_key_to_insert_char(raw_key, &insert_ch)) {
            if (len < maxlen) {
                if (insert_mode && pos < len) {
                    i = len;
                    while (i > pos) {
                        out[i] = out[i - 1u];
                        --i;
                    }
                    out[pos] = (char)insert_ch;
                    ++len;
                    ++pos;
                } else {
                    out[pos] = (char)insert_ch;
                    if (pos == len) {
                        ++len;
                    }
                    ++pos;
                }
                out[len] = 0;
                edit_redraw_input_tail(out, len, (unsigned char)(pos == 0 ? 0 : (pos - 1u)), 0);
            }
            edit_draw_cursor_cell(out, len, pos, 1);
            continue;
        }

        edit_draw_cursor_cell(out, len, pos, 1);
    }
}

static unsigned short edit_strlen(const char* s) {
    unsigned short n;
    n = 0;
    while (s[n] != 0) {
        ++n;
    }
    return n;
}

static int edit_append(char* dst, unsigned short max, const char* src) {
    unsigned short cur;
    unsigned short i;

    cur = 0;
    while (cur < max && dst[cur] != 0) {
        ++cur;
    }
    i = 0;
    while (src[i] != 0) {
        if ((unsigned short)(cur + 1u) >= max) {
            return -1;
        }
        dst[cur] = src[i];
        ++cur;
        ++i;
    }
    if (cur >= max) {
        return -1;
    }
    dst[cur] = 0;
    return 0;
}

int rs_vmovl_overlay9(char* out, unsigned short max) {
    char phys[PHYSICAL_MAX + 1u];
    int n;
    unsigned short len;

    if (!out || max == 0u) {
        return -1;
    }

    out[0] = 0;
    for (;;) {
        n = edit_read_physical_line(phys, PHYSICAL_MAX);
        if (n < 0) return -1;

        len = edit_strlen(phys);
        if (len > 0 && phys[len - 1u] == '`') {
            phys[len - 1u] = 0;
            if (edit_append(out, max, phys) != 0) {
                rs_shell_write_line("ERR: COMMAND TOO LONG");
                return -1;
            }
            continue;
        }
        if (edit_append(out, max, phys) != 0) {
            rs_shell_write_line("ERR: COMMAND TOO LONG");
            return -1;
        }
        break;
    }
    return (int)edit_strlen(out);
}
