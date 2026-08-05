# 6502 模拟器

一个用 C++23 编写的通用 NMOS 6502 模拟器，带串口终端和调试器，目前已移植运行 16 个历史上的 6502 操作系统/系统软件。

## 特性

- 严格 NMOS 6502 指令集（65C02 扩展指令触发停机）
- 64KB 内存，镜像加载（`.bin` 从地址 0 加载 / `.hex` Intel HEX）
- 串口终端（内存映射 UART）：
  - 写 `$F001` —— 输出字符到 stdout
  - 读 `$F000` —— 输入状态（0 = 无字符，1 = 有字符）
  - 读 `$F001` —— 取出一个字符
  - 终端模式下 stdin 为逐字符、无回显；支持管道喂入实现脚本化测试
- 周期 IRQ 定时器（RTOS 用）：环境变量 `IRQ_INTERVAL=<指令数>`
- SDB 内置调试器（无参数启动即进入，linenoise 交互）
- Kconfig 构建配置（`make menuconfig`）：编译器、标准库、优化级别、LTO/PGO 等

## 构建

```sh
cmake -B build
make -C build          # 产出 build/6502
make -C build menuconfig   # 可选：调整构建配置
```

## 运行

```sh
build/6502 <镜像.bin|.hex>              # 运行系统镜像
IRQ_INTERVAL=100000 build/6502 <镜像>   # 需要周期 IRQ 的系统（RTOS）
build/6502                             # 无参数：进入 SDB 调试器
```

## 已移植的操作系统

按移植时间排序。各系统的构建脚本统一为 `OS/<目录>/tools/build_emu6502.sh`（EMU 镜像不入库，脚本可复现）。

| 移植日期 | 系统 | 上游 | 说明 | 运行 |
|---|---|---|---|---|
| 2026-08-04 | GeckOS | [fachat/GeckOS-V2](https://github.com/fachat/GeckOS-V2) | 抢占式多任务 RTOS，带 ROM shell | `IRQ_INTERVAL=100000 build/6502 OS/GeckOS/arch/emu6502/geckos.bin` |
| 2026-08-04 | CPM-65 | [Dietrich-L/CPM-65](https://github.com/Dietrich-L/CPM-65) | CP/M-80 风格 OS，`A>` 提示符 | `build/6502 OS/CPM-65/OS_EMU6502.bin` |
| 2026-08-04 | LUnix NG | [ytmytm/c64-lng](https://github.com/ytmytm/c64-lng) | 类 Unix，microshell | `IRQ_INTERVAL=100000 build/6502 OS/c64-lng/LUNIX_EMU.bin` |
| 2026-08-04 | Contiki | [contiki-os/contiki](https://github.com/contiki-os/contiki) | 物联网 OS，hello/etimer/timers 三镜像 | `IRQ_INTERVAL=30000 build/6502 OS/contiki/HELLO_EMU.bin` |
| 2026-08-04 | Sixty/5o2 | [janroesner/sixty5o2](https://github.com/janroesner/sixty5o2) | Ben Eater 面包板微内核/Bootloader | `build/6502 OS/sixty5o2/SIXTY5O2_EMU.hex` |
| 2026-08-04 | atari64 | [unbibium/atari64](https://github.com/unbibium/atari64) | 完整版 C64 KERNAL/BASIC V2 | `build/6502 OS/atari64/ATARI64_EMU.bin` |
| 2026-08-04 | EhBASIC | [Klaus2m5/6502_EhBASIC_V2.22](https://github.com/Klaus2m5/6502_EhBASIC_V2.22) | Lee Davison 的 Enhanced BASIC 2.22 | `build/6502 OS/ehbasic/EHBASIC_EMU.bin` |
| 2026-08-05 | Microsoft BASIC | [mist64/msbasic](https://github.com/mist64/msbasic) | 微软 6502 BASIC（OSI 配置），实时交互 | `build/6502 OS/msbasic/MSBASIC_EMU.bin` |
| 2026-08-05 | volksFORTH | [forth-ev/VolksForth](https://github.com/forth-ev/VolksForth) | Forth-83（py65 通用内核） | `build/6502 OS/volksforth/VOLKSFORTH_EMU.bin` |
| 2026-08-05 | JMON | [jefftranter/6502](https://github.com/jefftranter/6502) | 迷你监控器（汇编/反汇编/调试） | `build/6502 OS/jmon/JMON_EMU.bin` |
| 2026-08-05 | Apple 1 | [tebl/RC6502-Apple-1-Replica](https://github.com/tebl/RC6502-Apple-1-Replica) | WozMon + Woz 原版 Integer BASIC | `build/6502 OS/apple1/APPLE1_EMU.bin` |
| 2026-08-05 | Acorn MOS | [tom-seddon/acorn_mos_disassembly](https://github.com/tom-seddon/acorn_mos_disassembly) | BBC MOS 3.20(NT)，OSCLI 可用 | `build/6502 OS/acornmos/ACORNMOS_EMU.bin` |
| 2026-08-05 | CTMon65 | [CorshamTech/CTMon65](https://github.com/CorshamTech/CTMon65) | KIM 风格串口监控 | `build/6502 OS/ctmon65/CTMON65_EMU.bin` |
| 2026-08-05 | Tali Forth 2 | [scotws/TaliForth2](https://github.com/scotws/TaliForth2) | 现代 6502 Forth（65C02→NMOS 指令翻译） | `build/6502 OS/taliforth2/TALIFORTH2_EMU.bin` |
| 2026-08-05 | C02 Pocket SBC | [floobydust/C02-Pocket-SBC](https://github.com/floobydust/C02-Pocket-SBC) | BIOS 2.04 + Monitor 2.04 | `build/6502 OS/c02pocket/C02POCKET_EMU.bin` |
| 2026-08-05 | open-roms | [MEGA65/open-roms](https://github.com/MEGA65/open-roms) | 开源 C64 KERNAL+BASIC（整数运算子集） | `build/6502 OS/openroms/OPENROMS_EMU.bin` |

## 目录结构

```
src/            模拟器核心（CPU、内存、UART、SDB 调试器）
OS/             各操作系统移植（上游源码 + tools/build_emu6502.sh）
link/           C 程序运行时（cc65 / llvm-mos 的 crt0、UART、链接配置）
test/           测试程序
tools/kconfig/  Kconfig 构建配置工具
```

## 移植新系统

参考 `OS/ehbasic/tools/build_emu6502.sh` 或 `OS/jmon/tools/build_emu6502.sh` 的模式：

1. `OS/<名字>/` 放入上游源码
2. 写 `tools/build_emu6502.sh`：`set -e`，python3 打补丁 → 汇编 → 拼 64KB 镜像（复位向量 `$FFFC`），中间文件放 `/tmp`，产物 `<NAME>_EMU.bin` 放在系统目录下
3. 输出走 `$F001`，输入用"读 `$F000` 自旋 + 读 `$F001`"阻塞取字符
4. 严格 NMOS 指令；65C02 代码可用 `OS/acornmos`/`OS/taliforth2` 的翻译流水线处理
