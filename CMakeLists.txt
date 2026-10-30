# 42Hz -- build root.
#
# The EasyEffects-derived core lives under upstream/, which is fetched by
# spike/fetch.sh, patched by spike/reduce-deps.py, and DISPOSABLE: never edit
# it. 42Hz's own sources live in frontend/ and are tracked here.
#
#     ./spike/fetch.sh
#     ./spike/reduce-deps.py upstream/easyeffects-8.2.8
#     cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release
#     ninja -C build

cmake_minimum_required(VERSION 3.28)

project(42hz LANGUAGES CXX C)

# 42Hz's own version, distinct from the core it is derived from. Bump it here
# and nowhere else: reduce-deps.py wires this into the patched tree's project()
# call, so it reaches --version, KAboutData and the AppStream metadata.
set(HZ_VERSION 0.7.0)

set(HZ_UPSTREAM_VERSION 8.2.8)
set(HZ_UPSTREAM_DIR upstream/easyeffects-${HZ_UPSTREAM_VERSION})

if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${HZ_UPSTREAM_DIR}/CMakeLists.txt)
    message(FATAL_ERROR
        "No patched upstream tree at ${HZ_UPSTREAM_DIR}.\n"
        "Run:  ./spike/fetch.sh && ./spike/reduce-deps.py ${HZ_UPSTREAM_DIR}")
endif()

# KDECMakeSettings probes git for a remote to fetch KDE translations from
# whenever the source root has no po/. 42Hz ships no catalogues, so claim the
# target first and skip the probe -- in a checkout, an archive or a chroot.
add_custom_target(fetch-translations)

# The derived core. Declares the `easyeffects` target (OUTPUT_NAME 42hz) and
# its QML module (URI hz.ui).
add_subdirectory(${HZ_UPSTREAM_DIR})

# Keep the binary at a stable path that does not move with the upstream version.
set_target_properties(easyeffects PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

# 42Hz's own frontend. Its QML is a separate module (hz.ui) linked into the
# core's target -- see frontend/CMakeLists.txt for why it cannot be merged into
# the core's own module.
add_subdirectory(frontend)

# The GPL obliges 42Hz to carry its licence to whoever receives the binary, and
# an Arch package is expected to place it here. The derived core installs no
# licence of its own.
include(GNUInstallDirs)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/licenses/42hz)
