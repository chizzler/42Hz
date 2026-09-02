# 42Hz frontend.
#
# These sources are 42Hz's own and are tracked in this repository, outside the
# disposable upstream tree -- which is why no frontend content needs to live in
# the patch inventory.
#
# The frontend is its OWN QML module (hz.ui), not an addition to the derived
# core's module (ee.ui). That is a hard constraint, not a preference: Qt
# finalizes a QML module at the end of the directory scope that declared it, so
# qt_target_qml_sources() called from here would embed the file but never add it
# to the core module's qmldir -- a clean build that fails at load time.
#
# The split is also the facade boundary made visible: every `import ee.ui` in
# 42Hz QML is a direct reach into upstream, and is greppable as such.

find_package(Qt6 REQUIRED COMPONENTS Qml Quick)

# The diagnostics report asks PipeWire and LV2 directly rather than through the
# core -- see frontend/diagnostics.hpp for why it must not build a graph. Both
# are already runtime dependencies of the package; neither is new.
find_package(PkgConfig REQUIRED)
pkg_check_modules(HZ_PIPEWIRE libpipewire-0.3>=1.0.6 IMPORTED_TARGET REQUIRED)
pkg_check_modules(HZ_LILV lilv-0>=0.24 IMPORTED_TARGET REQUIRED)

# The derived core sets these in its own directory scope; CMake does not
# propagate them sideways, so declare them here rather than relying on upstream.
set(CMAKE_AUTOMOC ON)
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

# The spectrum's dB window is shared between the renderer and the window that
# reports silence, so it is a singleton rather than a constant restated in two
# components that have no parent/child relationship to pass it through.
set_source_files_properties(SpectrumScale.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# The shipped audio profiles are one table with no per-instance state, read by
# the editor and by nothing else that should be able to hold a second copy.
set_source_files_properties(AudioProfiles.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(hz_frontend
    STATIC
    URI hz.ui
    VERSION 1.0
    SOURCES
        theme.cpp
        theme.hpp
        diagnostics.cpp
        diagnostics.hpp
    QML_FILES
        Main.qml
        Frame.qml
        Spectrum.qml
        SpectrumCells.qml
        SpectrumDots.qml
        SpectrumScale.qml
        Stepper.qml
        StateReport.qml
        TooSmall.qml
        StreamPanel.qml
        ProfileBar.qml
        EqPanel.qml
        AudioProfiles.qml
        Surface.qml
        ShellFramed.qml
)

target_link_libraries(hz_frontend PRIVATE Qt6::Core Qt6::Gui Qt6::Quick PkgConfig::HZ_PIPEWIRE PkgConfig::HZ_LILV)

# Linking the generated plugin is what registers the module with the engine.
# hz_frontend itself is linked too: the patched main.cpp calls hz::report()
# directly, and that is a plain C++ entry point with no QML type behind it.
target_link_libraries(easyeffects PRIVATE hz_frontendplugin hz_frontend)

# So the patched main.cpp can #include "diagnostics.hpp". This is the only
# place the core reaches into 42Hz's own sources, and it is one header.
target_include_directories(easyeffects PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
