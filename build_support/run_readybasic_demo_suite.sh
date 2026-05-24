#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READYOS_ROOT="${READYOS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HARNESS_REPO="${VICE_TASKS_REPO:-$(cd "$READYOS_ROOT/../agenticdevharness" && pwd)}"
VICE_TOOL_ROOT="$HARNESS_REPO/tools/vice_tasks_dotnet"
PROJECT="$VICE_TOOL_ROOT/src/ViceTasks.Binary/ViceTasks.Binary.csproj"
PLAN="${READYBASIC_DEMO_PLAN:-$READYOS_ROOT/logs/readybasic_demo_suite.generated.yaml}"

READYBASIC_VISIBLE="${READYBASIC_VISIBLE:-1}"
READYBASIC_KEEP_VICE="${READYBASIC_KEEP_VICE:-0}"
VICE_HEADLESS="true"
VICE_CLOSE="true"
CLI_CLOSE_ARG="--close-vice"
if [ "$READYBASIC_VISIBLE" = "1" ]; then
  VICE_HEADLESS="false"
fi
if [ "$READYBASIC_KEEP_VICE" = "1" ]; then
  VICE_CLOSE="false"
  CLI_CLOSE_ARG=""
fi

if [ "${READYBASIC_DEMO_FAST:-0}" = "1" ]; then
  READ_PAUSE="${READYBASIC_DEMO_READ_PAUSE:-0.25}"
  STEP_POST="${READYBASIC_DEMO_STEP_POST:-0.45}"
  RUN_POST="${READYBASIC_DEMO_RUN_POST:-0.8}"
else
  READ_PAUSE="${READYBASIC_DEMO_READ_PAUSE:-2.0}"
  STEP_POST="${READYBASIC_DEMO_STEP_POST:-2.0}"
  RUN_POST="${READYBASIC_DEMO_RUN_POST:-2.5}"
fi

keys() {
  python3 - "$1" <<'PY'
import sys
s = sys.argv[1]
print(",".join(str(ord(ch)) for ch in s))
PY
}

emit_type_step() {
  local id="$1"
  local text="$2"
  local post="${3:-$STEP_POST}"
  cat >>"$PLAN" <<YAML
  - id: $id
    type: input.sequence
    params:
      keys: [$(keys "$text")]
      inter_key_delay_s: 0.03
      post_delay_s: $post
YAML
}

emit_key_step() {
  local id="$1"
  local key_list="$2"
  local post="${3:-$STEP_POST}"
  cat >>"$PLAN" <<YAML
  - id: $id
    type: input.sequence
    params:
      keys: [$key_list]
      inter_key_delay_s: 0.05
      post_delay_s: $post
YAML
}

emit_wait_step() {
  local id="$1"
  local text="$2"
  local timeout="${3:-60}"
  cat >>"$PLAN" <<YAML
  - id: $id
    type: screen.wait_contains
    params:
      text: "$text"
      wait_timeout_s: $timeout
YAML
}

emit_assert_step() {
  local id="$1"
  local text="$2"
  cat >>"$PLAN" <<YAML
  - id: $id
    type: assert.screen
    params:
      contains: "$text"
YAML
}

mkdir -p "$(dirname "$PLAN")"

cd "$READYOS_ROOT"
if [ "${READYBASIC_SKIP_BUILD:-0}" != "1" ]; then
  RUN_VERSION_TEXT="$(python3 build_support/update_build_version.py --next)"
  make -B \
    BUILD_SUPPORT_DIR=build_support \
    PROFILE=precog-d81 \
    READYOS_VERSION_TEXT="$RUN_VERSION_TEXT" \
    READYOS_CONFIG_RUN_FIRST=readybasic \
    profile
fi

D81_REL="$(ls -t Releases/0.2.4/precog-d81/*.d81 | head -1)"
PREBOOT_REL="$(ls -t Releases/0.2.4/precog-d81/*-preboot.prg | head -1)"
D81="$(cd "$(dirname "$D81_REL")" && pwd)/$(basename "$D81_REL")"
PREBOOT="$(cd "$(dirname "$PREBOOT_REL")" && pwd)/$(basename "$PREBOOT_REL")"

cat >"$PLAN" <<YAML
version: 1
kind: vice_task_plan
plan_id: readybasic_demo_suite
run_mode: gui_vice
global_defaults:
  monitor_host: 127.0.0.1
  monitor_port_start: 6502
  monitor_port_span: 40
  retry_policy:
    max_attempts: 2
    backoff_ms: 250
    jitter: false
  timeouts:
    launch_s: 45
    step_s: 240
    read_s: 2
  artifact_policy:
    capture_screen: true
    capture_state: true
    capture_dump: false
  vice:
    disk8: "$D81"
    disk9: "$D81"
    autostart_prg: "$PREBOOT"
    drive8_type: 1581
    drive9_type: 1581
    true_drive: false
    close_vice: $VICE_CLOSE
    headless: $VICE_HEADLESS
    speed_percent: 100
steps:
  - id: launch_preboot
    type: vice.launch
    params:
      kill_stale: true
  - id: wait_readybasic_prompt
    type: screen.wait_contains
    params:
      text: "FREE:"
      wait_timeout_s: 180
      capture_label: demo_readybasic_prompt
YAML

emit_type_step "demo_01_basics" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 1: FREEMEM, A VARIABLE, AND A TWO LINE PROGRAM\rREM THIS SHOWS READYBASIC IS STILL NORMAL BASIC PLUS NEW COMMANDS\rPRINT CHR$(5)\rFREEMEM()\rNEW\rA%=42\r10 B%=ZADD16(42,8)\r20 PRINT "PROGRAM SUM";B%\rLIST\rPRINT CHR$(158)\rREM EXPECTED: FREEMEM PRINTS FREE SPACE, THEN RUN PRINTS 50\rPRINT CHR$(5)\rRUN\rA%=42\r' "$RUN_POST"
emit_assert_step "assert_demo_01_program_sum" "PROGRAM SUM 50"

emit_type_step "demo_02_exit_to_launcher" $'PRINT CHR$(158)\rREM NEXT: LEAVE READYBASIC, VISIT EDITOR, THEN RETURN\rREM THIS PROVES READYBASIC CAN BE SUSPENDED AND RESTORED\rPRINT CHR$(5)\rEXIT\r' "$STEP_POST"
emit_wait_step "wait_launcher_after_demo_02_exit" "READY OS" "30"
emit_key_step "move_readybasic_to_editor_demo" "145,145,145,145,13" "$STEP_POST"
emit_wait_step "wait_editor_demo" "editor" "60"
emit_type_step "type_editor_demo_sentence" $'READYBASIC DEMO VISITED EDITOR AND RETURNED.\r' "$RUN_POST"
emit_key_step "ctrl_b_editor_demo" "2" "$STEP_POST"
emit_wait_step "wait_launcher_after_editor_demo" "READY OS" "30"
emit_key_step "move_editor_to_readybasic_demo" "17,17,17,17,13" "$STEP_POST"
emit_wait_step "wait_readybasic_after_editor_demo" "READY." "60"
emit_type_step "demo_03_resume_proof" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 2: BACK FROM EDITOR TO READYBASIC\rREM THE VARIABLE AND PROGRAM SHOULD STILL BE PRESENT\rPRINT CHR$(5)\rFREEMEM()\rPRINT "A STILL";A%\rLIST\rPRINT CHR$(158)\rREM EXPECTED: A% IS STILL 42 AND THE PROGRAM STILL RUNS\rPRINT CHR$(5)\rRUN\r' "$RUN_POST"
emit_assert_step "assert_demo_03_var_restored" "A STILL 42"
emit_assert_step "assert_demo_03_program_restored" "PROGRAM SUM 50"

emit_type_step "demo_04_assembler_commands" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 3: ASSEMBLER COMMANDS AS BASIC EXPRESSIONS\rREM THESE DISPATCH TO READYBASIC COMMAND CODE, THEN RETURN VALUES\rPRINT CHR$(5)\rN%=ZADD16(7,8)\rT$=UPPER("ready")\rL$=LOWER("LOUD")\rH%=ZHIDDENRAM("AB")\rPRINT CHR$(158)\rREM EXPECTED: 15, READY, loud ASCII VALUES, AND HIDDEN RESULT 131\rPRINT CHR$(5)\rPRINT "ZADD";N%\rPRINT "UPPER ";T$\rPRINT "LOWASC";ASC(L$);ASC(MID$(L$,2,1));ASC(MID$(L$,3,1));ASC(MID$(L$,4,1))\rPRINT "HIDDEN";H%\r' "$READ_PAUSE"
emit_assert_step "assert_demo_04_zadd" "ZADD 15"
emit_assert_step "assert_demo_04_upper" "UPPER READY"
emit_assert_step "assert_demo_04_hidden" "HIDDEN 131"

emit_type_step "demo_05_proc_func" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 4: PROC HAS PARAMETERS AND NO RETURN VALUE\rREM FUNC HAS PARAMETERS AND RETURNS WITH RET\rPRINT CHR$(5)\rNEW\r10 EXEC SHOW("READY")\r20 A%=ADDI(4,5)\r30 PRINT "ADDI";A%\r40 T$=HELLO("KARL")\r50 PRINT T$\r60 F=SCALE(2.5)\r70 PRINT "SCALE";F\r80 END\r100 PROC SHOW(S$)\r110 PRINT "PROC ";S$\r120 ENDP\r130 FUNC ADDI(X%,Y%)\r140 RET X%+Y%\r150 ENDP\r160 FUNC HELLO(N$)\r170 RET "HI "+N$\r180 ENDP\r190 FUNC SCALE(X)\r200 RET X*1.5\r210 ENDP\rLIST\rPRINT CHR$(158)\rREM EXPECTED: PROC PRINTS READY; FUNCS RETURN 9, HI KARL, AND 3.75\rPRINT CHR$(5)\rRUN\r' "$RUN_POST"
emit_assert_step "assert_demo_05_proc" "PROC READY"
emit_assert_step "assert_demo_05_addi" "ADDI 9"
emit_assert_step "assert_demo_05_hello" "HI KARL"
emit_assert_step "assert_demo_05_scale" "SCALE 3.75"

emit_type_step "demo_06_parameter_groups" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 5: COMMAND PARAMETER GROUPS\rREM INTEGERS, STRINGS, ARRAYS, FLOATS, AND OUTPUT ARRAYS\rPRINT CHR$(5)\rDIM A%(3):A%(0)=1:A%(1)=2:A%(2)=3\rS%=ZSUMNUMARRAY(A%(0),3)\rDIM R%(4):ZRANGENUMARRAY(7,4,R%(0))\rF=FADD(1.2,2.3)\rPRINT CHR$(158)\rREM EXPECTED: ARRAY SUM 6, RANGE 7..10, FLOAT ADD 3.5\rPRINT CHR$(5)\rPRINT "SUM";S%\rPRINT "RANGE";R%(0);R%(3)\rPRINT "FADD";F\r' "$READ_PAUSE"
emit_assert_step "assert_demo_06_sum" "SUM 6"
emit_assert_step "assert_demo_06_range" "RANGE 7  10"
emit_assert_step "assert_demo_06_fadd" "FADD 3.5"

emit_type_step "demo_07_reu" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 6: REU RESOURCE COMMANDS\rREM BUFNEW RETURNS A HANDLE; BUFFILL AND BUFFREE ARE SIDE EFFECTS\rPRINT CHR$(5)\rH%=BUFNEW(64)\rBUFFILL(H%,170)\rPRINT CHR$(158)\rREM EXPECTED: HANDLE 1, FILL SUCCEEDS, FREE SUCCEEDS WITH NO ERROR\rPRINT CHR$(5)\rPRINT "HANDLE";H%\rBUFFREE(H%)\rPRINT "FREED";H%\r' "$READ_PAUSE"
emit_assert_step "assert_demo_07_handle" "HANDLE 1"
emit_assert_step "assert_demo_07_freed" "FREED 1"

emit_type_step "demo_08_screen_reu" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 7: SCREEN SNAPSHOT THROUGH REU\rREM SCRCAP RETURNS A HANDLE; SCRPUT RESTORES THE SAVED SCREEN\rPRINT CHR$(5)\rPRINT "SCREEN BEFORE"\rS%=SCRCAP()\rPRINT "SCREEN CHANGED"\rPRINT CHR$(158)\rREM EXPECTED: SCRPUT RESTORES SCREEN BEFORE, THEN PRINTS HANDLE\rPRINT CHR$(5)\rSCRPUT(S%)\rPRINT "SCR HANDLE";S%\r' "$READ_PAUSE"
emit_assert_step "assert_demo_08_screen_before" "SCREEN BEFORE"
emit_assert_step "assert_demo_08_handle" "SCR HANDLE 1"

emit_type_step "demo_09_expected_errors" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 8: EXPECTED ERRORS\rREM OLD SPACE SYNTAX AND DELIBERATE COMMAND FAILURE SHOULD ERROR\rPRINT CHR$(5)\rPRINT CHR$(158)\rREM EXPECTED: THE NEXT LINE SHOWS SYNTAX ERROR ON PURPOSE\rPRINT CHR$(5)\rZADD16 1,2,A%\r' "$STEP_POST"
emit_assert_step "assert_demo_09_syntax" "SYNTAX"
emit_type_step "demo_09_zfail" $'PRINT CHR$(158)\rREM EXPECTED: ZFAIL RAISES RB ERROR 7 AND CLEARS X% TO ZERO\rPRINT CHR$(5)\rX%=99\rZFAIL(7,X%)\rPRINT "AFTER FAIL";X%\r' "$STEP_POST"
emit_assert_step "assert_demo_09_rb_error" "RB ERROR 7"
emit_assert_step "assert_demo_09_fail_clear" "AFTER FAIL 0"

emit_type_step "demo_10_expressions" $'PRINT CHR$(147);CHR$(158)\rREM DEMO 9: COMMANDS AND FUNCS INSIDE EXPRESSIONS\rREM READYBASIC VALUES CAN FEED BUILT IN FUNCTIONS AND OTHER CALLS\rPRINT CHR$(5)\rNEW\r10 FUNC ADDI(X%,Y%)\r20 RET X%+Y%\r30 ENDP\r40 FUNC GREET(N$)\r50 RET "HI "+N$\r60 ENDP\r70 PRINT "ABS";ABS(ZADD16(1,6)-10)\r80 PRINT "LEFT ";LEFT$(UPPER("ready"),2)\r90 PRINT "NEST";ZADD16(1,ZADD16(2,3))\r100 PRINT "FABS";ABS(FADD(1.2,2.3)-3)\r110 PRINT "FLEFT ";LEFT$(GREET("READY")+"!",3)\rLIST\rPRINT CHR$(158)\rREM EXPECTED: ABS 3, LEFT RE, NEST 6, FABS .5, FLEFT HI\rPRINT CHR$(5)\rRUN\r' "$RUN_POST"
emit_assert_step "assert_demo_10_abs" "ABS 3"
emit_assert_step "assert_demo_10_left" "LEFT RE"
emit_assert_step "assert_demo_10_nest" "NEST 6"
emit_assert_step "assert_demo_10_fleft" "FLEFT HI"

emit_type_step "demo_done" $'PRINT CHR$(147);CHR$(158)\rREM DEMO COMPLETE\rREM READYBASIC COMMANDS, PROC/FUNC, REU, ERRORS, AND EXPRESSIONS PASSED\rPRINT CHR$(5)\rPRINT "READYBASIC DEMO COMPLETE"\r' "$READ_PAUSE"
emit_assert_step "assert_demo_done" "READYBASIC DEMO COMPLETE"

cat >>"$PLAN" <<YAML
  - id: regs_final
    type: monitor.command
    params:
      command: "r"
YAML

cd "$HARNESS_REPO"
dotnet build "$PROJECT"
dotnet run --project "$PROJECT" -- run-plan --plan "$PLAN" $CLI_CLOSE_ARG
