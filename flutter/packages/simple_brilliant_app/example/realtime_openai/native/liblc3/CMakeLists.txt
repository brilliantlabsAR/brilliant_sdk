cmake_minimum_required(VERSION 3.22.1)
project(liblc3 C)

file(GLOB LC3_SOURCES
    "${CMAKE_CURRENT_LIST_DIR}/*.c"
)

add_library(liblc3 SHARED ${LC3_SOURCES})

target_include_directories(liblc3 PUBLIC
    "${CMAKE_CURRENT_LIST_DIR}"
)

set_target_properties(liblc3 PROPERTIES
    LIBRARY_OUTPUT_NAME "lc3"
)
