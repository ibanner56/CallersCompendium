# Windows OCR for From an image... (#2327): a library shared by the runner and
# the native tests in tests/. It sets its own compile options rather than
# APPLY_STANDARD_SETTINGS, which defines _HAS_EXCEPTIONS=0: C++/WinRT reports
# failures as exceptions, which this library catches and turns into errors.
cmake_minimum_required(VERSION 3.14)

add_library(text_recognizer STATIC text_recognizer.cpp)
target_compile_features(text_recognizer PUBLIC cxx_std_17)
target_compile_options(text_recognizer PRIVATE /W4 /WX /EHsc /permissive- /bigobj)
target_compile_definitions(text_recognizer PRIVATE UNICODE _UNICODE NOMINMAX)
target_include_directories(text_recognizer PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
# The Windows Runtime (C++/WinRT projections live in the Windows SDK).
target_link_libraries(text_recognizer PUBLIC windowsapp)
