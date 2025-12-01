cmake_minimum_required(VERSION 3.22.1)
project(flutter_native_libs C CXX)

# Add liblc3 subdirectory
add_subdirectory(../../../../../native/liblc3 ${CMAKE_BINARY_DIR}/liblc3)

# Ensure liblc3 is properly exported
# This ensures .so files are copied to the correct location
install(TARGETS liblc3
    LIBRARY DESTINATION ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
)
