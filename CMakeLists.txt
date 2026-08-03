cmake_minimum_required(VERSION 4.4.2)
project(6502)

include(cmake/Kconfig.cmake)
read_kconfig()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB SIM_SOURCES src/*.cpp)
add_executable(6502 ${SIM_SOURCES})
target_include_directories(6502 PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
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
