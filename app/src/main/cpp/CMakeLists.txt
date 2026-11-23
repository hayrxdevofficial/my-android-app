cmake_minimum_required(VERSION 3.22.1)
project(pshere LANGUAGES CXX)

add_library(pshere SHARED
    native_bridge.cpp
    pshere_core.cpp
)

target_compile_features(pshere PRIVATE cxx_std_17)
target_compile_options(pshere PRIVATE -Wall -Wextra -Wpedantic -Werror=return-type)
target_link_libraries(pshere PRIVATE android log)
