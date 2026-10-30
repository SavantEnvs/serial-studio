cmake_minimum_required(VERSION 3.20)
project(SerialStudioMayhem LANGUAGES C CXX)

# Builds only the parser libraries and the fuzz harnesses / unit tests that need them, straight from
# upstream's sources. Upstream's own top-level configure also pulls the whole Qt Quick application
# and fetches dependencies over the network, which an air-gapped rebuild cannot do.
#
#   MAYHEM_MODE=FUZZ        libFuzzer binaries              fuzz_<subject>
#   MAYHEM_MODE=STANDALONE  run-once reproducers            fuzz_<subject>-standalone
#   MAYHEM_MODE=TEST        upstream QTest suites, normal flags   tst_<subject>

set(MAYHEM_MODE "FUZZ" CACHE STRING "FUZZ, STANDALONE or TEST")
set(MAYHEM_OUT "" CACHE PATH "Directory the binaries are written to")
set(STANDALONE_FUZZ_MAIN "" CACHE FILEPATH "LLVM run-once driver (C)")
set(FUZZ_ENGINE "-fsanitize=fuzzer" CACHE STRING "Link flag of the fuzzing engine")
set(LSAN_OFF_SRC "${CMAKE_CURRENT_LIST_DIR}/lsan_off.cc" CACHE FILEPATH "Translator unit defining __lsan_is_turned_off()")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

get_filename_component(SS_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(SS_CORE "${SS_ROOT}/core")

find_package(Qt6 REQUIRED COMPONENTS Core Gui Network Sql Test)
find_package(ZLIB REQUIRED)
find_package(EXPAT REQUIRED)
add_library(expat::expat ALIAS EXPAT::EXPAT)

set(QT_NO_PRIVATE_MODULE_WARNING ON)

# The values the top-level CMakeLists.txt feeds every TU.
add_definitions(
  -DPROJECT_VENDOR="Alex Spataru"
  -DPROJECT_CONTACT="serial-studio.github.io"
  -DPROJECT_VERSION="4.2.1"
  -DPROJECT_COMMIT=""
  -DPROJECT_APPCAST="https://raw.githubusercontent.com/Serial-Studio/Serial-Studio/master/updates.json"
  -DPROJECT_DISPNAME="Serial Studio GPLv3"
  -DPROJECT_DESCRIPTION_SUMMARY="Flexible data visualization software for embedded devices and projects"
)

# The libraries' own CMakeLists.txt use ${CMAKE_SOURCE_DIR}/core, which is this directory here.
include_directories(
  ${SS_CORE}
  ${SS_CORE}/Api
  ${SS_CORE}/Pipeline
  ${SS_CORE}/Devices
  ${SS_CORE}/Storage
  ${SS_CORE}/Ui
)

# Selects the S7, IEC 104, Sparkplug, OPC UA wire, TLS and CAN sources of SerialStudioProtocols.
set(SS_BUILD_TESTS ON)

add_subdirectory(${SS_CORE}/Core ${CMAKE_BINARY_DIR}/core-Core)
add_subdirectory(${SS_CORE}/Protocols ${CMAKE_BINARY_DIR}/core-Protocols)

set(_mdf_dir "${SS_ROOT}/lib/mdflib")
set(BUILD_SHARED_LIBS OFF)
add_subdirectory(${_mdf_dir} ${CMAKE_BINARY_DIR}/lib-mdflib EXCLUDE_FROM_ALL)

if(MAYHEM_OUT)
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${MAYHEM_OUT}")
endif()

if(MAYHEM_MODE STREQUAL "TEST")
  enable_testing()
else()
  # Leak detection is off for every target at build time (ASan stays on).
  add_library(ss_lsan_off OBJECT ${LSAN_OFF_SRC})
  if(MAYHEM_MODE STREQUAL "STANDALONE")
    add_library(ss_standalone_main OBJECT ${STANDALONE_FUZZ_MAIN})
    set_source_files_properties(${STANDALONE_FUZZ_MAIN} PROPERTIES LANGUAGE C)
  endif()
endif()

function(ss_target NAME)
  cmake_parse_arguments(T "" "" "SOURCES;LIBS" ${ARGN})
  set(srcs "")
  foreach(s IN LISTS T_SOURCES)
    if(IS_ABSOLUTE "${s}")
      list(APPEND srcs "${s}")
    else()
      list(APPEND srcs "${SS_ROOT}/app/tests/${s}")
    endif()
  endforeach()

  if(MAYHEM_MODE STREQUAL "TEST")
    add_executable(${NAME} ${srcs})
    target_link_libraries(${NAME} PRIVATE Qt6::Test ${T_LIBS})
    add_test(NAME ${NAME} COMMAND ${NAME})
  elseif(MAYHEM_MODE STREQUAL "STANDALONE")
    add_executable(${NAME} ${srcs} $<TARGET_OBJECTS:ss_standalone_main> $<TARGET_OBJECTS:ss_lsan_off>)
    target_link_libraries(${NAME} PRIVATE ${T_LIBS})
    set_target_properties(${NAME} PROPERTIES OUTPUT_NAME ${NAME}-standalone)
  else()
    add_executable(${NAME} ${srcs} $<TARGET_OBJECTS:ss_lsan_off>)
    target_link_libraries(${NAME} PRIVATE ${T_LIBS})
    separate_arguments(_engine UNIX_COMMAND "${FUZZ_ENGINE}")
    target_link_options(${NAME} PRIVATE ${_engine})
  endif()
  target_include_directories(${NAME} PRIVATE ${SS_CORE})
endfunction()

if(MAYHEM_MODE STREQUAL "TEST")
  function(ss_harness NAME)
  endfunction()
else()
  function(ss_harness NAME)
    ss_target(${NAME} ${ARGN})
  endfunction()
endif()

function(ss_test NAME)
  if(MAYHEM_MODE STREQUAL "TEST")
    ss_target(${NAME} ${ARGN})
  endif()
endfunction()

#--------------------------------------------------------------------------------------------------
# Fuzz harnesses: the same sources and libraries app/tests/CMakeLists.txt links for each.
#--------------------------------------------------------------------------------------------------

ss_harness(fuzz_block_codec
  SOURCES fuzz/fuzz_block_codec.cpp
  LIBS Qt6::Core Qt6::Gui Qt6::Sql SerialStudio::Core)

ss_harness(fuzz_csv_row
  SOURCES fuzz/fuzz_csv_row.cpp ${SS_CORE}/Storage/CSV/Player/RowSyntax.cpp
  LIBS Qt6::Core SerialStudio::Core)

ss_harness(fuzz_mdf4_reader
  SOURCES ${CMAKE_CURRENT_LIST_DIR}/fuzz_mdf4_reader.cpp ${SS_CORE}/Storage/MDF4/PlayerLoaderWorker.cpp
  LIBS Qt6::Core mdf SerialStudio::Core)

ss_harness(fuzz_api_json
  SOURCES fuzz/fuzz_api_json.cpp ${SS_CORE}/Api/API/Server/ClientReception.cpp
  LIBS Qt6::Core Qt6::Network SerialStudio::Core)

ss_harness(fuzz_s7_pdu
  SOURCES fuzz/fuzz_s7_pdu.cpp
  LIBS Qt6::Core SerialStudio::Protocols)

ss_harness(fuzz_isotsap
  SOURCES fuzz/fuzz_isotsap.cpp
  LIBS Qt6::Core SerialStudio::Protocols)

ss_harness(fuzz_iec104_apci
  SOURCES fuzz/fuzz_iec104_apci.cpp
  LIBS Qt6::Core SerialStudio::Protocols)

ss_harness(fuzz_iec104_asdu
  SOURCES fuzz/fuzz_iec104_asdu.cpp
  LIBS Qt6::Core SerialStudio::Protocols)

ss_harness(fuzz_sparkplug_payload
  SOURCES fuzz/fuzz_sparkplug_payload.cpp
  LIBS Qt6::Core SerialStudio::Protocols)

ss_harness(fuzz_opcua_wire
  SOURCES fuzz/fuzz_opcua_wire.cpp
  LIBS Qt6::Core Qt6::Gui SerialStudio::Core)

ss_harness(fuzz_sse_reader
  SOURCES fuzz/fuzz_sse_reader.cpp
          ${SS_CORE}/Ui/AI/SseEventReader.cpp
          ${SS_CORE}/Ui/AI/Logging.cpp
  LIBS Qt6::Core SerialStudio::Core)

#--------------------------------------------------------------------------------------------------
# Upstream's QTest suites for the same parsers (registered the same way in app/tests/CMakeLists.txt).
#--------------------------------------------------------------------------------------------------

ss_test(tst_s7comm_pdu SOURCES tst_s7comm_pdu.cpp LIBS Qt6::Core SerialStudio::Protocols)
ss_test(tst_s7comm_isotsap SOURCES tst_s7comm_isotsap.cpp LIBS Qt6::Core SerialStudio::Protocols)
ss_test(tst_s7_address SOURCES tst_s7_address.cpp LIBS Qt6::Core SerialStudio::Protocols)
ss_test(tst_iec104_apci SOURCES tst_iec104_apci.cpp LIBS Qt6::Core SerialStudio::Protocols)
ss_test(tst_iec104_asdu SOURCES tst_iec104_asdu.cpp LIBS Qt6::Core SerialStudio::Protocols)
ss_test(tst_sparkplug_payload SOURCES tst_sparkplug_payload.cpp LIBS Qt6::Core SerialStudio::Protocols)
ss_test(tst_stream_block_codec SOURCES tst_stream_block_codec.cpp LIBS Qt6::Core)
ss_test(tst_csv_rows
  SOURCES tst_csv_rows.cpp ${SS_CORE}/Storage/CSV/Player/RowSyntax.cpp
  LIBS Qt6::Core SerialStudio::Core)
ss_test(tst_client_reception
  SOURCES tst_client_reception.cpp ${SS_CORE}/Api/API/Server/ClientReception.cpp
  LIBS Qt6::Core Qt6::Network SerialStudio::Core)
ss_test(tst_sse_event_reader
  SOURCES tst_sse_event_reader.cpp ${SS_CORE}/Ui/AI/SseEventReader.cpp ${SS_CORE}/Ui/AI/Logging.cpp
  LIBS Qt6::Core SerialStudio::Core)
