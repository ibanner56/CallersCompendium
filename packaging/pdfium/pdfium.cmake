# The pdfium that the Linux and Windows builds ship, pinned and hash-checked.
#
# Why (audit finding platform-5): the `printing` plugin downloads a prebuilt
# pdfium from bblanchon/pdfium-binaries while CMake configures the app
# (its linux/ and windows/CMakeLists.txt call download_project with a URL and
# no URL_HASH). Its only knob is the PDFIUM_VERSION cache variable, which also
# accepts "latest". It has no option for a hash or a local archive, and we do
# not fork or patch the plugin, so:
#
#   compendium_pin_pdfium()       runs BEFORE the plugins are added and forces
#                                 PDFIUM_VERSION to the pinned release;
#   compendium_verify_pdfium(os)  runs straight AFTER and checks the SHA-256 of
#                                 the archive the plugin downloaded and of the
#                                 library it is about to bundle. A mismatch
#                                 stops the configure step, so nothing is
#                                 compiled, linked or installed from it.
#
# app/linux/CMakeLists.txt and app/windows/CMakeLists.txt call both. The
# release tooling reads the set(...) lines below (tools/release/pdfium_pin.py)
# for the SBOM; tools/release/test_pdfium_pin.py guards the wiring and runs the
# verifier against fake archives.
#
# Version: chromium/5200 (PDFium 106.0.5200.0, released 2022-07-25) is the
# release printing 5.15.1 asks for by default, so pinning it changes nothing the
# app does. Moving to a newer pdfium-binaries release is a separate change: the
# printing plugin's C++ is written against this release's API and archive
# layout, and it must be tested on Windows.
#
# Hashes: computed (sha256sum) from the release assets downloaded on
# 2026-10-06; the linux-x64 archive also matched an earlier, independent
# download by a previous build. pdfium-binaries publishes no checksums for
# chromium/5200 (the release page lists none, and the release predates
# GitHub's per-asset digests). The LIBRARY hashes are of lib/libpdfium.so and
# bin/pdfium.dll inside those archives.
#
# Changing any of this (a printing upgrade or a new pdfium release):
#   1. read the new plugin's linux/ and windows/CMakeLists.txt and its
#      DownloadProject.cmake: the verifier relies on PDFIUM_VERSION,
#      PDFIUM_ARCH and on where download_project leaves the archive;
#   2. download each pdfium-<os>-<arch>.tgz and record both hashes per target;
#   3. replace app/assets/licenses/pdfium-LICENSE.txt with that release's
#      LICENSE and update COMPENDIUM_PDFIUM_LICENSE_SHA256 (see below);
#   4. run python3 tools/release/test_pdfium_pin.py.
# docs/dev/releasing.md ("Pinned native dependencies") has the commands.

# The printing plugin version this file was written against (pubspec.lock).
set(COMPENDIUM_PDFIUM_PRINTING_VERSION "5.15.1")

# bblanchon/pdfium-binaries release tag chromium/<this>.
set(COMPENDIUM_PDFIUM_VERSION "5200")
set(COMPENDIUM_PDFIUM_FULL_VERSION "106.0.5200.0")

# SHA-256 of pdfium-<os>-<arch>.tgz, and of the library inside it.
set(COMPENDIUM_PDFIUM_ARCHIVE_SHA256_linux_x64 "0e68e7f0c7619a5b4a91431fad516d665cc52f0c341d701b21aad71a6c6d41d9")
set(COMPENDIUM_PDFIUM_LIBRARY_SHA256_linux_x64 "d585300f4a8ce25cfb3a290fdd16caeedf102bb89194a0d3835f27a9ca09bd24")
set(COMPENDIUM_PDFIUM_ARCHIVE_SHA256_linux_arm64 "2a888b49c5474c436da465b223fca1311cf25e542a8070df3d4096f8d6b2df4d")
set(COMPENDIUM_PDFIUM_LIBRARY_SHA256_linux_arm64 "47a642b9172e6f239a7fc454409d3cea7fb74b699d181c3390d7e65b3534ef39")
set(COMPENDIUM_PDFIUM_ARCHIVE_SHA256_win_x64 "8e900c3e5103ae9a3aa7800653e804575c687d132fcfb4deda7bb2ce04aca8d2")
set(COMPENDIUM_PDFIUM_LIBRARY_SHA256_win_x64 "0c88ebacc0393fd45fc3e7b35e31e72c9e55b633a846a7ecf4085694dba68abd")
set(COMPENDIUM_PDFIUM_ARCHIVE_SHA256_win_arm64 "0fe0eddf65e92cbc72e0d92fdd552f132c430fdb2b4ab97fed18685bc70cadd8")
set(COMPENDIUM_PDFIUM_LIBRARY_SHA256_win_arm64 "ee4827beb15312eeec4b71b91e0fe222d051d9b56aecad99146be5e3e6ddcfd1")

# SHA-256 of LICENSE in the Linux archives (the Windows archives carry the same
# text with CRLF line endings). It is UTF-8 except for one Latin-1 byte in
# FreeType's notice ("copyright \xa9 <year>"); the bundled copy,
# app/assets/licenses/pdfium-LICENSE.txt, re-encodes that one character as
# UTF-8 because the app decodes the asset strictly. Nothing else differs.
set(COMPENDIUM_PDFIUM_LICENSE_SHA256 "0f00d0bb0e8a07d499439de08e1192a88eae06b055877db098b28dc3ca0892ce")

macro(compendium_pin_pdfium)
  # FORCE: the plugin's own set(PDFIUM_VERSION ... CACHE ...) then leaves this
  # value alone, and a stray -DPDFIUM_VERSION=latest cannot unpin the build.
  set(PDFIUM_VERSION "${COMPENDIUM_PDFIUM_VERSION}" CACHE STRING
    "pdfium-binaries release used by printing (pinned by packaging/pdfium/pdfium.cmake)" FORCE)
endmacro()

# os: "linux" or "win", as in the release asset names.
function(compendium_verify_pdfium os)
  if(NOT DEFINED COMPENDIUM_PDFIUM_BUILD_DIR)
    # printing's download_project uses the top-level build directory.
    set(COMPENDIUM_PDFIUM_BUILD_DIR "${CMAKE_BINARY_DIR}")
  endif()
  if(NOT "${PDFIUM_VERSION}" STREQUAL "${COMPENDIUM_PDFIUM_VERSION}")
    message(FATAL_ERROR
      "pdfium: PDFIUM_VERSION is '${PDFIUM_VERSION}', but packaging/pdfium/pdfium.cmake "
      "pins '${COMPENDIUM_PDFIUM_VERSION}'. Call compendium_pin_pdfium() before the "
      "plugins are added.")
  endif()
  set(target "${os}-${PDFIUM_ARCH}")
  string(REPLACE "-" "_" key "${target}")
  set(expected_archive "${COMPENDIUM_PDFIUM_ARCHIVE_SHA256_${key}}")
  set(expected_library "${COMPENDIUM_PDFIUM_LIBRARY_SHA256_${key}}")
  if(expected_archive STREQUAL "" OR expected_library STREQUAL "")
    message(FATAL_ERROR
      "pdfium: no pinned SHA-256 for pdfium-${target} in packaging/pdfium/pdfium.cmake.")
  endif()

  set(archive
    "${COMPENDIUM_PDFIUM_BUILD_DIR}/pdfium-download/pdfium-download-prefix/src/pdfium-${target}.tgz")
  if(NOT EXISTS "${archive}")
    message(FATAL_ERROR
      "pdfium: ${archive} not found. The printing plugin no longer downloads pdfium "
      "where packaging/pdfium/pdfium.cmake expects; re-check the plugin's CMakeLists.txt.")
  endif()
  file(SHA256 "${archive}" actual_archive)
  if(NOT actual_archive STREQUAL expected_archive)
    message(FATAL_ERROR
      "pdfium: SHA-256 mismatch for ${archive}\n"
      "  expected ${expected_archive}\n"
      "  actual   ${actual_archive}")
  endif()

  if(os STREQUAL "win")
    set(library "${COMPENDIUM_PDFIUM_BUILD_DIR}/pdfium-src/bin/pdfium.dll")
  else()
    set(library "${COMPENDIUM_PDFIUM_BUILD_DIR}/pdfium-src/lib/libpdfium.so")
  endif()
  if(NOT EXISTS "${library}")
    message(FATAL_ERROR "pdfium: ${library} not found after extraction.")
  endif()
  file(SHA256 "${library}" actual_library)
  if(NOT actual_library STREQUAL expected_library)
    message(FATAL_ERROR
      "pdfium: SHA-256 mismatch for ${library} (a stale or altered extraction; "
      "delete the build directory and rebuild)\n"
      "  expected ${expected_library}\n"
      "  actual   ${actual_library}")
  endif()

  message(STATUS
    "pdfium chromium/${COMPENDIUM_PDFIUM_VERSION} (${target}) verified: ${actual_archive}")
endfunction()
