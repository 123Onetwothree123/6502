/*
 * ucitest_format.h - UCI tester response formatters
 */

#ifndef UCITEST_FORMAT_H
#define UCITEST_FORMAT_H

#include "../../lib/tui_output.h"
#include "ucitest_catalog.h"
#include "ucitest_uci.h"

void ucitest_format_response(TuiOutput *out,
                             const UciTestCommandSpec *cmd,
                             const UciTestTransfer *xfer,
                             unsigned char raw_mode);
void ucitest_format_hex8(char *dst, unsigned char value);
void ucitest_format_hex16(char *dst, unsigned int value);

#endif /* UCITEST_FORMAT_H */
