/*
 * readyshell.c - ReadyShell for ReadyOS
 *
 * For Commodore 64, compiled with CC65
 */

#include "core/rs_config.h"
#include "core/rs_errors.h"
#include "core/rs_token.h"
#include "core/rs_ui_state.h"
#include "core/rs_vm.h"
#include "platform/rs_edit.h"
#include "platform/rs_overlay.h"
#include "platform/rs_platform.h"
#include "../../lib/resume_state.h"
#include "../../lib/tui.h"
#include <cbm.h>
#include <c64.h>
#include <conio.h>
#include <_heap.h>
#include <stdlib.h>
#include <string.h>

#define SCREEN_WIDTH 40
#define SCREEN_HEIGHT 25
#define SCREEN_MEM ((unsigned char*)0x0400)
#define COLOR_MEM ((unsigned char*)0xD800)

#define TITLE_Y 0
#define BODY_TOP 3
#define BODY_BOTTOM 24

#define PROMPT_TEXT ">"
#define PROMPT_LEN 1
#define LOGICAL_MAX 160
#define INPUT_COLS (SCREEN_WIDTH - PROMPT_LEN)
#define PHYSICAL_MAX INPUT_COLS
#define PAUSE_TEXT "PAUSED - PRESS ANY KEY"

/* Key codes */
/* Shim ABI */
#define SHIM_CURRENT_BANK (*(unsigned char*)0xC834)

/* KERNAL keyboard state */
#define RS_KBD_BUFFER_COUNT (*(volatile unsigned char*)0x00C6)
#define RS_KBD_CURRENT_KEY (*(volatile unsigned char*)0x00CB)
#define RS_KBD_MODIFIERS (*(volatile unsigned char*)0x028D)
#define RS_KBD_NO_KEY 0x40u
#define RS_KBD_SPACE_KEY 0x3Cu

/* PETSCII box chars (screen codes) */
#define BOX_TL 0x70
#define BOX_TR 0x6E
#define BOX_BL 0x6D
#define BOX_BR 0x7D
#define BOX_H 0x40
#define BOX_V 0x5D

/* C64 colors */
#define C_BLACK 0
#define C_WHITE 1
#define C_LIGHTRED 10
#define C_LIGHTBLUE 14
#define C_CYAN 3
#define C_YELLOW 7
#define C_GRAY3 15
#define C_BLUE 6

/* Keep runtime VM state in fixed RAM outside the overlay execution window. */
typedef struct {
    RSVM vm;
    RSVMPlatform platform;
    RSError err;
    unsigned char resume_ready;
    unsigned char cursor_y;
    unsigned char cursor_x;
    unsigned int off;
    unsigned char i;
} ReadyShellRuntimeState;

#define RS_RUNTIME_ADDR 0xCA00u
#define RS_RUNTIME_LIMIT_ADDR 0xD000u
#define RS_REU_HEAP_SESSION_FLAG (*(unsigned char*)0xCFF0)
#define RS_CMD_SESSION_EPOCH (*(unsigned char*)0xCFF1)

#define RS_RUNTIME ((ReadyShellRuntimeState*)RS_RUNTIME_ADDR)
#define g_vm (RS_RUNTIME->vm)
#define g_platform (RS_RUNTIME->platform)
#define g_err (RS_RUNTIME->err)
#define resume_ready (RS_RUNTIME->resume_ready)
#define g_cursor_y (RS_RUNTIME->cursor_y)
#define g_cursor_x (RS_RUNTIME->cursor_x)
#define g_off (RS_RUNTIME->off)
#define g_i (RS_RUNTIME->i)

static char g_line[LOGICAL_MAX];
typedef struct {
    char last_line[LOGICAL_MAX];
} ReadyShellResumeV1;
static ReadyShellResumeV1 resume_blob;
static const char g_shell_help_hint[] = "run: cat \"rshelp\" | more";

static void clear_line(unsigned char y, unsigned char color);
static void draw_text(unsigned char x, unsigned char y, const char *s, unsigned char color);
static void resume_save_state(void);
static void shell_overlay_progress(unsigned char stage, void *user);
void rs_set_c_stack_top(void);

extern unsigned char rs_heap_bss_run[];
extern unsigned char rs_heap_bss_size[];
extern unsigned char rs_heap_overlay_loadaddr[];

static void shell_init_runtime_regions(void) {
    unsigned int heap_start;
    unsigned int heap_end;
    unsigned int heap_size;

    /* High RAM at $CA00 is scratch and is not part of the app REU snapshot. */
    memset(RS_RUNTIME, 0, sizeof(*RS_RUNTIME));
    RS_REU_HEAP_SESSION_FLAG = 0u;
    RS_CMD_SESSION_EPOCH = 0u;
    rs_set_c_stack_top();
    heap_start = (unsigned int)rs_heap_bss_run + (unsigned int)rs_heap_bss_size;
    if (heap_start & 1u) {
        ++heap_start;
    }
    heap_end = (unsigned int)rs_heap_overlay_loadaddr;
    heap_size = (heap_end > heap_start) ? (heap_end - heap_start) : 0u;
    _heaporg = (unsigned*)heap_start;
    _heapptr = (unsigned*)heap_start;
    _heapend = (unsigned*)heap_end;
    _heapfirst = 0;
    _heaplast = 0;
    if (heap_size != 0u) {
        _heapadd((void*)heap_start, heap_size);
    }
}

static unsigned char ascii_to_screen(unsigned char ascii) {
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
        /*
         * On cc65/C64 the source literal '|' follows the target charset, while
         * generated SEQ help files currently carry raw ASCII 124. Accept both.
         */
        case 124u:
        case '|':
            return BOX_V;
        case '_': return 100;
        default: return 32;
    }
}

static void put_char(unsigned char x, unsigned char y, unsigned char ch, unsigned char color) {
    g_off = (unsigned int)y * SCREEN_WIDTH + x;
    SCREEN_MEM[g_off] = ch;
    COLOR_MEM[g_off] = color;
}

static void put_ascii(unsigned char x, unsigned char y, unsigned char ch, unsigned char color) {
    put_char(x, y, ascii_to_screen(ch), color);
}

static void clear_line(unsigned char y, unsigned char color) {
    g_off = (unsigned int)y * SCREEN_WIDTH;
    for (g_i = 0; g_i < SCREEN_WIDTH; ++g_i) {
        SCREEN_MEM[g_off + g_i] = 32;
        COLOR_MEM[g_off + g_i] = color;
    }
}

static unsigned char shell_pause_flags(void) {
    unsigned char flags;
    flags = 0u;
    (void)rs_reu_read(RS_REU_UI_FLAGS_OFF, &flags, 1u);
    return flags;
}

static void shell_pause_set_flags(unsigned char flags) {
    (void)rs_reu_write(RS_REU_UI_FLAGS_OFF, &flags, 1u);
}

static void shell_draw_pause_notice(void) {
    clear_line(g_cursor_y, C_WHITE);
    draw_text(0, g_cursor_y, PAUSE_TEXT, C_YELLOW);
}

static void shell_pause_clear_buffer(void) {
    RS_KBD_BUFFER_COUNT = 0u;
}

static unsigned char shell_pause_key_down(void) {
    cbm_k_scnkey();
    return (unsigned char)(
        RS_KBD_CURRENT_KEY != RS_KBD_NO_KEY ||
        (RS_KBD_MODIFIERS & 0x07u) != 0u
    );
}

static void shell_pause_arm_poll(void) {
    unsigned char flags;
    cbm_k_scnkey();
    if (RS_KBD_CURRENT_KEY != RS_KBD_SPACE_KEY) {
        return;
    }

    shell_pause_clear_buffer();
    flags = (unsigned char)(shell_pause_flags() | RS_UI_FLAG_PAUSED);
    shell_pause_set_flags(flags);
}

static void shell_wait_if_paused(void) {
    unsigned char flags;

    flags = shell_pause_flags();
    if ((flags & RS_UI_FLAG_PAUSED) == 0u) {
        return;
    }

    /* Make the keyboard the active input stream before we block here. */
    cbm_k_clrch();
    shell_draw_pause_notice();
    shell_pause_clear_buffer();

    while (shell_pause_key_down()) {
        waitvsync();
    }
    shell_pause_clear_buffer();

    while (!shell_pause_key_down()) {
        waitvsync();
    }
    while (shell_pause_key_down()) {
        waitvsync();
    }

    flags = (unsigned char)(shell_pause_flags() & (unsigned char)~RS_UI_FLAG_PAUSED);
    shell_pause_set_flags(flags);
    cbm_k_clrch();
    shell_pause_clear_buffer();
    clear_line(g_cursor_y, C_WHITE);
}

static void draw_text(unsigned char x, unsigned char y, const char *s, unsigned char color) {
    unsigned char cx;

    cx = x;
    while (s != 0 && *s != 0 && cx < SCREEN_WIDTH) {
        put_ascii(cx, y, (unsigned char)*s, color);
        ++s;
        ++cx;
    }
}

static void draw_window(unsigned char x, unsigned char y, unsigned char w, unsigned char h, unsigned char color) {
    unsigned char x2;
    unsigned char y2;
    unsigned char i;
    unsigned char j;

    x2 = (unsigned char)(x + w - 1);
    y2 = (unsigned char)(y + h - 1);

    put_char(x, y, BOX_TL, color);
    put_char(x2, y, BOX_TR, color);
    put_char(x, y2, BOX_BL, color);
    put_char(x2, y2, BOX_BR, color);

    for (i = (unsigned char)(x + 1); i < x2; ++i) {
        put_char(i, y, BOX_H, color);
        put_char(i, y2, BOX_H, color);
    }
    for (j = (unsigned char)(y + 1); j < y2; ++j) {
        put_char(x, j, BOX_V, color);
        put_char(x2, j, BOX_V, color);
    }
}

static void clear_screen_color(unsigned char bg, unsigned char fg) {
    unsigned int i;

    VIC.bordercolor = bg;
    VIC.bgcolor0 = bg;
    textcolor(fg);
    clrscr();

    for (i = 0; i < 1000; ++i) {
        SCREEN_MEM[i] = 32;
        COLOR_MEM[i] = fg;
    }
}

static void scroll_body_up(void) {
    unsigned char row;
    unsigned int src;
    unsigned int dst;

    for (row = (unsigned char)(BODY_TOP + 1); row <= BODY_BOTTOM; ++row) {
        src = (unsigned int)row * SCREEN_WIDTH;
        dst = (unsigned int)(row - 1) * SCREEN_WIDTH;
        memcpy(SCREEN_MEM + dst, SCREEN_MEM + src, SCREEN_WIDTH);
        memcpy(COLOR_MEM + dst, COLOR_MEM + src, SCREEN_WIDTH);
    }

    clear_line(BODY_BOTTOM, C_WHITE);
}

static void shell_newline(void) {
    if (g_cursor_y >= BODY_BOTTOM) {
        scroll_body_up();
    } else {
        ++g_cursor_y;
    }
    g_cursor_x = 0;
}

static void shell_write_text_color(const char *s, unsigned char color) {
    unsigned char c;

    while (s != 0 && *s != 0) {
        c = (unsigned char)*s++;
        if (c == '\n') {
            shell_newline();
            continue;
        }
        put_ascii(g_cursor_x, g_cursor_y, c, color);
        ++g_cursor_x;
        if (g_cursor_x >= SCREEN_WIDTH) {
            shell_newline();
        }
    }
}

static void shell_write_line_color(const char *s, unsigned char color) {
    clear_line(g_cursor_y, color);
    g_cursor_x = 0;
    if (s != 0) {
        shell_write_text_color(s, color);
    }
    shell_newline();
}

static void shell_write_line(const char *s) {
    shell_write_line_color(s, C_WHITE);
}

unsigned char rs_shell_cursor_y(void) {
    return g_cursor_y;
}

void rs_shell_put_char(unsigned char x, unsigned char y, unsigned char ch, unsigned char color) {
    put_char(x, y, ch, color);
}

void rs_shell_put_ascii(unsigned char x, unsigned char y, unsigned char ch, unsigned char color) {
    put_ascii(x, y, ch, color);
}

void rs_shell_clear_line(unsigned char y, unsigned char color) {
    clear_line(y, color);
}

void rs_shell_draw_text(unsigned char x, unsigned char y, const char *s, unsigned char color) {
    draw_text(x, y, s, color);
}

void rs_shell_newline(void) {
    shell_newline();
}

void rs_shell_write_line(const char *s) {
    shell_write_line(s);
}

static int shell_writer(void *user, const char *line) {
    unsigned char color;
    (void)user;
    color = (rs_vm_current_output_kind() == RS_VM_OUTPUT_PRT) ? C_CYAN : C_GRAY3;
    shell_write_line_color(line, color);

    shell_pause_arm_poll();
    shell_wait_if_paused();
    return 0;
}

static void shell_trim(char *s) {
    unsigned int n;
    unsigned int i;
    unsigned int j;

    if (!s) return;

    n = strlen(s);
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t')) {
        s[n - 1] = 0;
        --n;
    }

    i = 0;
    while (s[i] == ' ' || s[i] == '\t') ++i;
    if (i == 0) return;

    j = 0;
    while (s[i] != 0) s[j++] = s[i++];
    s[j] = 0;
}

static void shell_print_u16(unsigned short n) {
    char rev[8];
    char out[8];
    unsigned char i;
    unsigned char j;

    if (n == 0) {
        shell_write_text_color("0", C_WHITE);
        return;
    }

    i = 0;
    while (n > 0 && i < sizeof(rev)) {
        rev[i++] = (char)('0' + (n % 10u));
        n = (unsigned short)(n / 10u);
    }

    j = 0;
    while (i > 0) out[j++] = rev[--i];
    out[j] = 0;
    shell_write_text_color(out, C_WHITE);
}

static void shell_overlay_progress(unsigned char stage, void *user) {
    (void)user;
    clear_line(g_cursor_y, C_WHITE);
    g_cursor_x = 0;
    shell_write_text_color("Loading", C_GRAY3);
    switch (stage) {
        case 1:
            shell_write_text_color(".", C_WHITE);
            break;
        case 2:
            shell_write_text_color("..", C_WHITE);
            break;
        case 3:
            shell_write_text_color("...", C_WHITE);
            break;
        case 4:
            shell_write_text_color("+", C_WHITE);
            break;
        case 5:
            shell_write_text_color("++", C_WHITE);
            break;
        default:
            shell_write_text_color(" done", C_LIGHTBLUE);
            break;
    }
}

static void resume_save_state(void) {
    if (!resume_ready) {
        return;
    }
    memcpy(resume_blob.last_line, g_line, sizeof(g_line));
    (void)resume_save(&resume_blob, sizeof(resume_blob));
}

static void shell_nav_to_launcher(void) {
    resume_save_state();
    tui_return_to_launcher();
}

static void shell_nav_switch(unsigned char bank) {
    if (bank == 0) {
        return;
    }
    resume_save_state();
    tui_switch_to_app(bank);
}

void rs_shell_nav_to_launcher(void) {
    shell_nav_to_launcher();
}

void rs_shell_nav_next_app(void) {
    shell_nav_switch(tui_get_next_app(SHIM_CURRENT_BANK));
}

void rs_shell_nav_prev_app(void) {
    shell_nav_switch(tui_get_prev_app(SHIM_CURRENT_BANK));
}

static void shell_draw_chrome(void) {
    unsigned char row;

    clear_screen_color(C_BLUE, C_WHITE);
    draw_window(0, TITLE_Y, 40, 3, C_LIGHTBLUE);
    draw_text(11, 0, "READYOS READYSHELL", C_YELLOW);
    draw_text(8, 1, "readyshell v0.2 (beta)", C_CYAN);

    for (row = BODY_TOP; row <= BODY_BOTTOM; ++row) {
        clear_line(row, C_WHITE);
    }

    g_cursor_y = BODY_TOP;
    g_cursor_x = 0;
}

static void shell_show_help(void) {
    shell_write_line(g_shell_help_hint);
}

static void shell_print_error(const RSError *err) {
    clear_line(g_cursor_y, C_WHITE);
    g_cursor_x = 0;
    shell_write_text_color("ERR[", C_LIGHTRED);
    shell_print_u16((unsigned short)err->code);
    shell_write_text_color("] line=", C_LIGHTRED);
    shell_print_u16(err->line);
    shell_write_text_color(" col=", C_LIGHTRED);
    shell_print_u16(err->column);
    shell_write_text_color(": ", C_LIGHTRED);
    if (err->message) shell_write_text_color(err->message, C_LIGHTRED);
    if (err->message && strncmp(err->message, "overlay ", 8u) == 0) {
        shell_write_text_color(" rc=", C_LIGHTRED);
        shell_print_u16((unsigned short)rs_overlay_last_rc());
    }
    shell_newline();
}

int main(void) {
    unsigned char bank;
    unsigned int payload_len = 0;

    shell_init_runtime_regions();
    (void)kbrepeat(KBREPEAT_NONE);

    g_line[0] = 0;
    resume_ready = 0;
    bank = SHIM_CURRENT_BANK;
    if (bank >= 1 && bank <= 23) {
        resume_init_for_app(bank, bank, RESUME_SCHEMA_V1);
        resume_ready = 1;
        if (resume_try_load(&resume_blob, sizeof(resume_blob), &payload_len) &&
            payload_len == sizeof(resume_blob)) {
            memcpy(g_line, resume_blob.last_line, sizeof(g_line));
            g_line[LOGICAL_MAX - 1] = 0;
        } else {
            g_line[0] = 0;
        }
    }

    rs_vm_init(&g_vm);
    shell_pause_set_flags(0u);
    shell_pause_clear_buffer();

    g_platform.user = 0;
    g_platform.file_read = 0;
    g_platform.file_write = 0;
    g_platform.list_dir = 0;
    g_platform.drive_info = 0;
    rs_vm_set_platform(&g_vm, &g_platform);
    rs_vm_set_writer(&g_vm, shell_writer, 0);

    shell_draw_chrome();
    rs_overlay_debug_mark('M');

    if (rs_overlay_active()) {
        rs_overlay_debug_mark('J');
    } else if (rs_overlay_boot_with_progress(shell_overlay_progress, 0) == 0) {
        rs_overlay_debug_mark('K');
        shell_newline();
        shell_show_help();
    } else {
        rs_overlay_debug_mark('k');
        shell_write_line("overlay failed");
    }

    for (;;) {
        signed char exec_rc;
        if (rs_overlay_read_logical_line(g_line, sizeof(g_line)) < 0) break;

        shell_trim(g_line);
        if (g_line[0] == 0) continue;
        rs_overlay_debug_mark('L');

        if (rs_ci_equal(g_line, "HELP")) {
            shell_show_help();
            continue;
        }
        if (rs_ci_equal(g_line, "VER")) {
            clear_line(g_cursor_y, C_WHITE);
            g_cursor_x = 0;
            shell_write_text_color("version ", C_WHITE);
            shell_write_text_color(RS_VERSION, C_WHITE);
            shell_newline();
            continue;
        }
        if (rs_ci_equal(g_line, "CLEAR")) {
            shell_draw_chrome();
            continue;
        }

        rs_error_init(&g_err);
        ++RS_CMD_SESSION_EPOCH;
        if (RS_CMD_SESSION_EPOCH == 0u) {
            RS_CMD_SESSION_EPOCH = 1u;
        }
        rs_overlay_debug_mark('V');
        if (((exec_rc = rs_vm_exec_source(&g_vm, g_line, &g_err)) != 0) ||
            g_err.code != RS_ERR_NONE) {
            rs_overlay_debug_mark('X');
            shell_print_error(&g_err);
        } else {
            rs_overlay_debug_mark('v');
        }
    }

    rs_vm_free(&g_vm);
    return 0;
}
