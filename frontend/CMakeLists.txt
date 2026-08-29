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

# The derived core sets these in its own directory scope; CMake does not
# propagate them sideways, so declare them here rather than relying on upstream.
set(CMAKE_AUTOMOC ON)
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

qt_add_qml_module(hz_frontend
    STATIC
    URI hz.ui
    VERSION 1.0
    SOURCES
        theme.cpp
        theme.hpp
    QML_FILES
        Main.qml
        Frame.qml
        Spectrum.qml
        SpectrumCells.qml
        StateReport.qml
        StreamPanel.qml
        Surface.qml
        ShellBare.qml
        ShellFramed.qml
)

target_link_libraries(hz_frontend PRIVATE Qt6::Core Qt6::Gui Qt6::Quick)

# Linking the generated plugin is what registers the module with the engine.
target_link_libraries(easyeffects PRIVATE hz_frontendplugin)
