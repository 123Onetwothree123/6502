cmake_minimum_required(VERSION 3.21)
project(kconfig LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)

set(BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR}/build)

# === Compiler detection and std setup ===
# kconfig 工具是构建期工具，统一使用 libstdc++ + 头文件聚合
# （clang + libc++ 与 glibc 头文件 regex.h/struct_stat.h 等存在冲突）
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libstdc++")
endif()
file(WRITE ${BUILD_DIR}/std_compat.h
    "#ifndef _STD_COMPAT_H_\n"
    "#define _STD_COMPAT_H_\n"
    "#include <bits/stdc++.h>\n"
    "#endif\n"
)
set(STD_COMPAT_FLAGS -include ${BUILD_DIR}/std_compat.h)

# === Flex and Bison ===
find_package(FLEX REQUIRED)
find_package(BISON REQUIRED)

# Bison: parser.y -> parser.tab.c + parser.tab.h
add_custom_command(
    OUTPUT ${BUILD_DIR}/parser.tab.c ${BUILD_DIR}/parser.tab.h
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_DIR}
    COMMAND ${BISON_EXECUTABLE} -v ${CMAKE_CURRENT_SOURCE_DIR}/parser.y
            --defines=${BUILD_DIR}/parser.tab.h -o ${BUILD_DIR}/parser.tab.c
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/parser.y
    COMMENT "Bison: parser.y"
)

# Post-process parser.tab.c -> parser.tab.cpp
add_custom_command(
    OUTPUT ${BUILD_DIR}/parser.tab.cpp
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/kconfig_postprocess.sh ${BUILD_DIR}/parser.tab.c ${BUILD_DIR}/parser.tab.cpp
    DEPENDS ${BUILD_DIR}/parser.tab.c
    COMMENT "Post-process parser.tab.c -> parser.tab.cpp"
)

# Flex: lexer.l -> lexer.lex.c
add_custom_command(
    OUTPUT ${BUILD_DIR}/lexer.lex.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_DIR}
    COMMAND ${FLEX_EXECUTABLE} -o ${BUILD_DIR}/lexer.lex.c ${CMAKE_CURRENT_SOURCE_DIR}/lexer.l
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/lexer.l ${BUILD_DIR}/parser.tab.h
    COMMENT "Flex: lexer.l"
)

# Post-process lexer.lex.c -> lexer.lex.cpp
add_custom_command(
    OUTPUT ${BUILD_DIR}/lexer.lex.cpp
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/kconfig_lexer_postprocess.sh ${BUILD_DIR}/lexer.lex.c ${BUILD_DIR}/lexer.lex.cpp
    DEPENDS ${BUILD_DIR}/lexer.lex.c
    COMMENT "Post-process lexer.lex.c -> lexer.lex.cpp"
)

# === Generated sources library (compiled once, shared by both targets) ===
add_library(kconfig_generated OBJECT
    ${BUILD_DIR}/parser.tab.cpp
    ${BUILD_DIR}/lexer.lex.cpp
)
target_include_directories(kconfig_generated PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(kconfig_generated PRIVATE ${STD_COMPAT_FLAGS} -Wno-sign-compare -Wno-unused-function)

# === Core library (shared between conf and mconf) ===
set(CORE_SRCS
    confdata.cpp
    expr.cpp
    preprocess.cpp
    symbol.cpp
    util.cpp
    menu.cpp
)

add_library(kconfig_core OBJECT ${CORE_SRCS})
target_include_directories(kconfig_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/lxdialog)
target_compile_options(kconfig_core PRIVATE ${STD_COMPAT_FLAGS})

# === conf executable ===
add_executable(c_conf conf.cpp
    $<TARGET_OBJECTS:kconfig_core>
    $<TARGET_OBJECTS:kconfig_generated>
)
target_include_directories(c_conf PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_options(c_conf PRIVATE ${STD_COMPAT_FLAGS})
set_target_properties(c_conf PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../build)

# === mconf executable (with ncurses) ===
find_package(Curses REQUIRED)

set(LXDIALOG_SRCS
    lxdialog/checklist.cpp
    lxdialog/inputbox.cpp
    lxdialog/menubox.cpp
    lxdialog/textbox.cpp
    lxdialog/util.cpp
    lxdialog/yesno.cpp
)

add_executable(c_mconf mconf.cpp ${LXDIALOG_SRCS}
    $<TARGET_OBJECTS:kconfig_core>
    $<TARGET_OBJECTS:kconfig_generated>
)
target_include_directories(c_mconf PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/lxdialog ${CURSES_INCLUDE_DIRS})
target_compile_options(c_mconf PRIVATE ${STD_COMPAT_FLAGS})
target_link_libraries(c_mconf ${CURSES_LIBRARIES} tinfo)
set_target_properties(c_mconf PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../build)
