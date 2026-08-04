#ifndef RS_EDIT_H
#define RS_EDIT_H

int rs_vmovl_overlay9(char* out, unsigned short max);

unsigned char rs_shell_cursor_y(void);
void rs_shell_put_char(unsigned char x, unsigned char y, unsigned char ch, unsigned char color);
void rs_shell_put_ascii(unsigned char x, unsigned char y, unsigned char ch, unsigned char color);
void rs_shell_clear_line(unsigned char y, unsigned char color);
void rs_shell_draw_text(unsigned char x, unsigned char y, const char* s, unsigned char color);
void rs_shell_newline(void);
void rs_shell_write_line(const char* s);
void rs_shell_nav_to_launcher(void);
void rs_shell_nav_next_app(void);
void rs_shell_nav_prev_app(void);

#endif
