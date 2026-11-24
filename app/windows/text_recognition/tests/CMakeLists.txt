# Native tests for the Windows OCR recognizer (#2327). A standalone project,
# built and run by CI's Windows build leg (.github/workflows/ci.yml):
#
#   cmake -S app/windows/text_recognition/tests -B <build dir>
#   cmake --build <build dir> --config Release
#   <build dir>/Release/text_recognizer_tests.exe
cmake_minimum_required(VERSION 3.14)
project(text_recognizer_tests LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/.."
                 "${CMAKE_CURRENT_BINARY_DIR}/text_recognition")

add_executable(text_recognizer_tests text_recognizer_tests.cpp)
target_compile_features(text_recognizer_tests PRIVATE cxx_std_17)
target_compile_options(text_recognizer_tests PRIVATE /W4 /WX /EHsc /permissive- /bigobj)
target_compile_definitions(text_recognizer_tests PRIVATE UNICODE _UNICODE NOMINMAX)
target_link_libraries(text_recognizer_tests PRIVATE text_recognizer gdiplus ole32)
