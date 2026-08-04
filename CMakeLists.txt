cmake_minimum_required(VERSION 4.4.2)

include(cmake/Kconfig.cmake)
read_kconfig()

# .config 变化时自动重新 configure，使 KCONFIG_* 编译选项生效
set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/.config")

# 编译器选择必须在 project() 之前生效
if(KCONFIG_CC)
  set(CMAKE_CXX_COMPILER "${KCONFIG_CC}" CACHE STRING "C++ compiler chosen by Kconfig" FORCE)
endif()

project(6502)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------- 工具链 ----------
if(KCONFIG_CC STREQUAL "g++")
  # g++ 没有 -stdlib 标志：用 libc++ 时手动指定头文件和库
  if(KCONFIG_STDLIB_LIBCXX)
    string(APPEND _CXX_KCONFIG_FLAGS " -nostdinc++ -isystem ${KCONFIG_LIBCXX_INCLUDE_DIR}")
    string(APPEND _LINK_KCONFIG_FLAGS " -Wno-alloc-size-larger-than -Wno-stringop-overflow")
    string(APPEND _LINK_KCONFIG_FLAGS " -lc++ -lc++abi")
  endif()
else()
  # -stdlib 是 clang 专用选项，编译和链接都要传
  if(KCONFIG_STDLIB_FLAG)
    string(APPEND _CXX_KCONFIG_FLAGS " ${KCONFIG_STDLIB_FLAG}")
    string(APPEND _LINK_KCONFIG_FLAGS " ${KCONFIG_STDLIB_FLAG}")
  endif()
endif()

# ---------- 性能优化 ----------
string(APPEND _CXX_KCONFIG_FLAGS " ${KCONFIG_CC_OPT}")
if(KCONFIG_CC_LTO)
  string(APPEND _CXX_KCONFIG_FLAGS " -flto")
  string(APPEND _LINK_KCONFIG_FLAGS " -flto")
endif()
if(KCONFIG_PGO_GENERATE)
  string(APPEND _CXX_KCONFIG_FLAGS " -fprofile-generate")
  string(APPEND _LINK_KCONFIG_FLAGS " -fprofile-generate")
elseif(KCONFIG_PGO_USE)
  string(APPEND _CXX_KCONFIG_FLAGS " -fprofile-use")
  string(APPEND _LINK_KCONFIG_FLAGS " -fprofile-use")
endif()
if(KCONFIG_MARCH_NATIVE)
  string(APPEND _CXX_KCONFIG_FLAGS " -march=native")
elseif(KCONFIG_MARCH_CUSTOM AND KCONFIG_MARCH_CUSTOM_VALUE)
  string(APPEND _CXX_KCONFIG_FLAGS " -march=${KCONFIG_MARCH_CUSTOM_VALUE}")
endif()
if(KCONFIG_CC_IPA_PTA)
  string(APPEND _CXX_KCONFIG_FLAGS " -fipa-pta")
endif()
if(KCONFIG_CC_PREFETCH)
  string(APPEND _CXX_KCONFIG_FLAGS " -fprefetch-loop-arrays")
endif()
if(KCONFIG_CC_PIPE)
  string(APPEND _CXX_KCONFIG_FLAGS " -pipe")
endif()
if(KCONFIG_CC_SPLIT_DWARF)
  string(APPEND _CXX_KCONFIG_FLAGS " -gsplit-dwarf")
endif()

# ---------- 大小优化 ----------
if(KCONFIG_CC_GC_SECTIONS)
  string(APPEND _CXX_KCONFIG_FLAGS " -ffunction-sections -fdata-sections")
  string(APPEND _LINK_KCONFIG_FLAGS " -Wl,--gc-sections")
endif()
if(KCONFIG_CC_STRIP)
  string(APPEND _LINK_KCONFIG_FLAGS " -s")
endif()
if(KCONFIG_CC_VISIBILITY_HIDDEN)
  string(APPEND _CXX_KCONFIG_FLAGS " -fvisibility=hidden")
endif()

separate_arguments(_CXX_KCONFIG_FLAGS)
separate_arguments(_LINK_KCONFIG_FLAGS)

file(GLOB_RECURSE SIM_SOURCES src/*.cpp)
add_executable(6502 ${SIM_SOURCES} third_party/linenoise/linenoise.c)
# 仅对 C++ 文件应用 Kconfig 编译选项（如 -nostdinc++ 对 C 无效）
target_compile_options(6502 PRIVATE $<$<COMPILE_LANGUAGE:CXX>:${_CXX_KCONFIG_FLAGS}>)
target_link_options(6502 PRIVATE ${_LINK_KCONFIG_FLAGS})
target_include_directories(6502 PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/third_party/linenoise)
add_dependencies(6502 syncconfig)

add_subdirectory(tools/kconfig)

add_custom_target(menuconfig
  COMMAND ${CMAKE_COMMAND} -E env TERM=xterm LC_ALL=C.utf8
          $<TARGET_FILE:c_mconf> ${CMAKE_CURRENT_SOURCE_DIR}/Kconfig
  COMMAND $<TARGET_FILE:c_conf> -s --syncconfig ${CMAKE_CURRENT_SOURCE_DIR}/Kconfig
  DEPENDS c_mconf c_conf
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "运行 menuconfig"
)

add_custom_target(syncconfig
  COMMAND $<TARGET_FILE:c_conf> -s --syncconfig ${CMAKE_CURRENT_SOURCE_DIR}/Kconfig
  DEPENDS c_conf
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMENT "根据 .config 重新生成配置"
)
