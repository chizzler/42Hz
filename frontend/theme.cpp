#include "theme.hpp"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QTextStream>
#include <algorithm>
#include <cmath>

namespace {

// Built-in fallbacks. These are Omarchy's own neutral defaults rather than a
// 42Hz invention, so an unthemed run still looks like it belongs on the
// desktop instead of announcing itself.
constexpr auto kFallbackBackground = "#101315";
constexpr auto kFallbackForeground = "#cacccc";
constexpr auto kFallbackAccent = "#cacccc";
constexpr auto kFallbackMuted = "#707880";
constexpr auto kFallbackUrgent = "#a55555";

QColor toColor(const QString& raw, const QColor& fallback) {
  if (raw.isEmpty()) {
    return fallback;
  }

  const QColor c = QColor::fromString(raw.trimmed());

  return c.isValid() ? c : fallback;
}

// WCAG relative luminance, used only to decide whether a theme has produced an
// illegible pairing -- not to grade it.
double luminance(const QColor& c) {
  auto channel = [](double v) { return v <= 0.03928 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4); };

  return 0.2126 * channel(c.redF()) + 0.7152 * channel(c.greenF()) + 0.0722 * channel(c.blueF());
}

double contrast(const QColor& a, const QColor& b) {
  const double la = luminance(a);
  const double lb = luminance(b);

  return (std::max(la, lb) + 0.05) / (std::min(la, lb) + 0.05);
}

// Signal clarity and readable contrast take priority over literal colour
// reuse, so a pairing below this ratio is replaced rather than honoured.
constexpr double kMinContrast = 4.5;

// Secondary text -- the legend, the state report's qualifier, the media-name
// column, an unselected stream's name -- is dimmer on purpose, so the body-text
// ratio would overcorrect it into the very foreground it exists to sit below.
// It is held to the large-text ratio instead.
constexpr double kMinSecondaryContrast = 3.0;

// How much of the accent's chroma each end of the spectrum ramp carries.
constexpr double kSpectrumFloorChroma = 0.55;
constexpr double kSpectrumPeakChroma = 0.85;

// Saturation at which a colour counts as having a hue worth keeping, and the
// saturation below which it has none to lend.
constexpr double kOwnHueSaturation = 0.15;
constexpr double kAchromatic = 0.01;

QColor mix(const QColor& a, const QColor& b, double t) {
  return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t,
                          a.blueF() + (b.blueF() - a.blueF()) * t);
}

QColor legibleOn(const QColor& fg, const QColor& bg) {
  if (contrast(fg, bg) >= kMinContrast) {
    return fg;
  }

  const QColor white(Qt::white);
  const QColor black(Qt::black);

  return contrast(white, bg) >= contrast(black, bg) ? white : black;
}

// The same guard for secondary text, applied gently.
//
// `legibleOn` replaces a failing colour outright with white or black, which is
// right for body text and wrong here: `muted` and `dark_foreground` carry the
// theme's hue as much as anything in the palette, and a theme whose muted grey
// sits at 3:1 would have it swapped for pure white and lose that. This lifts
// the colour toward the nearer of white or black and stops at the first step
// that clears the ratio, so the hue survives and only the lightness moves.
QColor liftedOn(const QColor& fg, const QColor& bg) {
  if (contrast(fg, bg) >= kMinSecondaryContrast) {
    return fg;
  }

  const QColor toward = luminance(bg) > 0.5 ? QColor(Qt::black) : QColor(Qt::white);

  constexpr int kSteps = 20;

  for (int step = 1; step <= kSteps; ++step) {
    const QColor lifted = mix(fg, toward, static_cast<double>(step) / kSteps);

    if (contrast(lifted, bg) >= kMinSecondaryContrast) {
      return lifted;
    }
  }

  return toward;
}

// Give the spectrum ramp the theme's colour, keeping the lightness it has.
//
// The spectrum is the largest surface in the application and the state it rests
// in, so it is where a theme is either recognisable or not. Ramping it between
// two *foreground* levels made it nearly achromatic: across the shipped themes
// those levels average about 0.16 saturation against an accent averaging 0.43,
// and several -- matte-black's orange, lupine's blue -- put their whole
// identity in an accent the spectrum never showed.
//
// Taking the accent wholesale would be worse. The foreground levels already
// encode the thing that is hard to get right: how far from the background each
// end should sit, in the correct direction for a light theme as well as a dark
// one. So lightness is kept exactly, and only the colour is decided here.
//
// Three rules, each of which a theme broke when it was missing:
//
//   - An achromatic accent lends nothing, and a monochrome theme stays
//     monochrome rather than being handed a colour it did not choose.
//   - The accent is not always the more colourful of the two. Gruvbox's is a
//     pale teal at 0.16 saturation while its bright foreground is a warm cream
//     at 0.59, so overwriting the hue turned a spectrum that already looked
//     like gruvbox into a duller, colder one. A hue that exists is kept, and
//     saturation only ever rises.
//   - The hue is decided ONCE, for the ramp, not per end. Deciding per end gave
//     gruvbox a cool floor and a warm peak, which reads as two colours rather
//     than as one signal getting louder.
void tintRamp(QColor& floorColor, QColor& peakColor, const QColor& accent, double floorChroma,
              double peakChroma) {
  const double accentSaturation = static_cast<double>(accent.hslSaturationF());

  if (accentSaturation <= kAchromatic) {
    return;
  }

  // The peak carries the ramp's identity, so it chooses the hue for both ends.
  const bool peakHasHue = static_cast<double>(peakColor.hslSaturationF()) >= kOwnHueSaturation;
  const double hue = static_cast<double>(peakHasHue ? peakColor.hslHueF() : accent.hslHueF());

  auto apply = [hue, accentSaturation](QColor& c, double chroma) {
    const double own = static_cast<double>(c.hslSaturationF());
    const double saturation = std::clamp(std::max(own, accentSaturation * chroma), 0.0, 1.0);

    c = QColor::fromHslF(static_cast<float>(hue), static_cast<float>(saturation),
                         static_cast<float>(c.lightnessF()));
  };

  apply(floorColor, floorChroma);
  apply(peakColor, peakChroma);
}

qreal alphaOf(const QHash<QString, QString>& shell, const QString& key, qreal fallback) {
  const auto it = shell.constFind(key);

  if (it == shell.constEnd()) {
    return fallback;
  }

  bool ok = false;
  const double v = it.value().toDouble(&ok);

  return ok ? std::clamp(v, 0.0, 1.0) : fallback;
}

}  // namespace

Theme::Theme(QObject* parent) : QObject(parent) {
  const QString home = QDir::homePath();

  m_statePath = home + QStringLiteral("/.local/state/omarchy/current");
  m_themePath = m_statePath + QStringLiteral("/theme");
  m_userShell = home + QStringLiteral("/.config/omarchy/shell.toml");

  // A theme switch is `rm -rf theme && mv next-theme theme` followed by a
  // rewrite of theme.name, so a single switch produces a burst of events.
  m_coalescer.setSingleShot(true);
  m_coalescer.setInterval(100);
  connect(&m_coalescer, &QTimer::timeout, this, &Theme::reload);

  connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &Theme::scheduleReload);
  connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &Theme::scheduleReload);

  reload();
}

void Theme::scheduleReload() {
  m_coalescer.start();
}

QString Theme::readFile(const QString& path) {
  QFile f(path);

  if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return {};
  }

  return QString::fromUtf8(f.readAll());
}

// colors.toml is flat `key = "value"`. Values may be quoted or bare.
QHash<QString, QString> Theme::parseColors(const QString& text) {
  static const QRegularExpression re(QStringLiteral(R"RX(^\s*([A-Za-z0-9_-]+)\s*=\s*["']?([^"'#\s]+|#[0-9A-Fa-f]{3,8})["']?)RX"));

  QHash<QString, QString> out;
  const QStringList lines = text.split('\n');

  for (const QString& line : lines) {
    const QString trimmed = line.trimmed();

    if (trimmed.isEmpty() || trimmed.startsWith('#')) {
      continue;
    }

    const auto m = re.match(trimmed);

    if (m.hasMatch()) {
      out.insert(m.captured(1), m.captured(2));
    }
  }

  return out;
}

// shell.toml is sectioned; keys are flattened to "section.key". Values are
// kept as raw strings and coerced by the reader, matching how Omarchy's own
// resolver treats them.
QHash<QString, QString> Theme::parseShell(const QString& text) {
  static const QRegularExpression sectionRe(QStringLiteral(R"RX(^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$)RX"));
  static const QRegularExpression kvRe(
      QStringLiteral(R"RX(^([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^#\s][^#]*?))\s*(?:#.*)?$)RX"));

  QHash<QString, QString> out;
  QString section;
  const QStringList lines = text.split('\n');

  for (const QString& line : lines) {
    const QString trimmed = line.trimmed();

    if (trimmed.isEmpty() || trimmed.startsWith('#')) {
      continue;
    }

    const auto sm = sectionRe.match(trimmed);

    if (sm.hasMatch()) {
      section = sm.captured(1);
      continue;
    }

    if (section.isEmpty()) {
      continue;
    }

    const auto km = kvRe.match(trimmed);

    if (!km.hasMatch()) {
      continue;
    }

    QString value = km.captured(2);

    if (value.isEmpty()) {
      value = km.captured(3);
    }

    if (value.isEmpty()) {
      value = km.captured(4).trimmed();
    }

    out.insert(section + '.' + km.captured(1), value);
  }

  return out;
}

void Theme::reload() {
  const QHash<QString, QString> colors = parseColors(readFile(m_themePath + QStringLiteral("/colors.toml")));

  // User keys win over the theme's, so a machine-level override survives a
  // theme switch -- this is where the Omarchy font-size CLI writes.
  QHash<QString, QString> shell = parseShell(readFile(m_themePath + QStringLiteral("/shell.toml")));
  const QHash<QString, QString> userShell = parseShell(readFile(m_userShell));

  for (auto it = userShell.constBegin(); it != userShell.constEnd(); ++it) {
    shell.insert(it.key(), it.value());
  }

  m_ready = !colors.isEmpty();
  m_name = readFile(m_statePath + QStringLiteral("/theme.name")).trimmed();
  m_dark = colors.value(QStringLiteral("mode"), QStringLiteral("dark")).compare(QStringLiteral("light"),
                                                                                Qt::CaseInsensitive) != 0;

  auto colorOf = [&colors](const char* key, const QColor& fallback) {
    return toColor(colors.value(QString::fromLatin1(key)), fallback);
  };

  // Foundational palette. `color0/4/7/8` are the terminal-palette fallbacks
  // Omarchy itself uses when a theme predates the named keys.
  m_background = colorOf("background", toColor(colors.value(QStringLiteral("color0")), QColor(kFallbackBackground)));
  m_foreground = colorOf("foreground", toColor(colors.value(QStringLiteral("color7")), QColor(kFallbackForeground)));
  m_accent = colorOf("accent", toColor(colors.value(QStringLiteral("color4")), QColor(kFallbackAccent)));
  m_muted = colorOf("muted", toColor(colors.value(QStringLiteral("color8")), QColor(kFallbackMuted)));

  // A theme that omits a level gets one derived from the level it does have,
  // rather than an unrelated constant.
  m_backgroundDark = colorOf("dark_background", m_background.darker(130));
  m_backgroundDarker = colorOf("darker_background", m_background.darker(160));
  m_backgroundLight = colorOf("lighter_background", m_background.lighter(140));

  m_foregroundDim = colorOf("dark_foreground", m_muted);
  m_foregroundLight = colorOf("light_foreground", m_foreground);
  m_foregroundBright = colorOf("bright_foreground", m_foregroundLight);

  m_error = colorOf("red", toColor(colors.value(QStringLiteral("color1")), QColor(kFallbackUrgent)));
  m_warning = colorOf("orange", colorOf("yellow", m_error));
  m_success = colorOf("green", m_accent);

  m_selection = colorOf("selection", mix(m_background, m_accent, 0.35));

  // The spectrum ramps from a quiet floor to a peak that must stay separable
  // from both the background and the resting foreground. The foreground levels
  // set how far each end sits from the background; the accent sets what colour
  // it is.
  QColor spectrumFloor = colorOf("dark_foreground", m_accent);
  QColor spectrumPeak = colorOf("bright_foreground", m_foregroundBright);

  // A theme supplying neither foreground level collapses the ramp to a single
  // colour, which leaves amplitude unreadable. Derive a floor from the
  // background rather than shipping a flat spectrum.
  if (spectrumFloor == spectrumPeak) {
    spectrumFloor = mix(m_background, spectrumPeak, 0.45);
  }

  // The floor carries less of the accent than the peak. Most bars are quiet
  // most of the time, and a floor at full chroma turns the resting spectrum
  // into a block of solid colour -- which is loud rather than punchy, and
  // leaves the peaks nothing to be.
  tintRamp(spectrumFloor, spectrumPeak, m_accent, kSpectrumFloorChroma, kSpectrumPeakChroma);

  m_spectrumLow = spectrumFloor;
  m_spectrumHigh = spectrumPeak;

  // Contrast guard, after the spectrum is derived so the ramp keeps the
  // theme's own levels: the spectrum and the drawn chrome are allowed to sit
  // close to the background by design.
  //
  // Both tiers are text-bearing. `muted` and `foregroundDim` are not
  // decoration -- between them they carry the legend, the state report's
  // qualifier, the media-name column and every unselected stream name -- so
  // they are guarded too, at the secondary ratio and by lifting rather than
  // replacement.
  m_foreground = legibleOn(m_foreground, m_background);
  m_foregroundLight = legibleOn(m_foregroundLight, m_background);
  m_foregroundBright = legibleOn(m_foregroundBright, m_background);

  m_muted = liftedOn(m_muted, m_background);
  m_foregroundDim = liftedOn(m_foregroundDim, m_background);

  m_controlFillAlpha = alphaOf(shell, QStringLiteral("controls.normal-fill-alpha"), 0.04);
  m_controlBorderAlpha = alphaOf(shell, QStringLiteral("controls.normal-border-alpha"), 0.4);
  m_hoverFillAlpha = alphaOf(shell, QStringLiteral("controls.hover-cursor-fill-alpha"), 0.08);
  m_focusBorderAlpha = alphaOf(shell, QStringLiteral("controls.focus-border-alpha"), 0.25);
  m_selectedFillAlpha = alphaOf(shell, QStringLiteral("controls.selected-fill-alpha"), 0.18);
  m_pressedFillAlpha = alphaOf(shell, QStringLiteral("controls.pressed-fill-alpha"), 0.22);

  bool ok = false;
  const int base = shell.value(QStringLiteral("font.base-size")).toInt(&ok);
  m_fontBaseSize = (ok && base > 0) ? base : 12;

  // Omarchy manages the family system-wide through a fontconfig alias; naming
  // a concrete family here would defeat `omarchy font set`.
  m_fontFamily = QStringLiteral("monospace");

  rewatch();

  Q_EMIT changed();
}

// Re-establish watches after every load. A theme switch removes the directory
// being watched, which silently drops the watch even though a new directory
// appears at the same path moments later.
void Theme::rewatch() {
  const QStringList existing = m_watcher.files() + m_watcher.directories();

  if (!existing.isEmpty()) {
    m_watcher.removePaths(existing);
  }

  // The state directory outlives the swap and is therefore the only reliable
  // signal that a theme changed; the rest are low-latency extras for in-place
  // edits and may be absent.
  const QStringList candidates = {m_statePath,
                                  m_themePath,
                                  m_themePath + QStringLiteral("/colors.toml"),
                                  m_themePath + QStringLiteral("/shell.toml"),
                                  QFileInfo(m_userShell).absolutePath(),
                                  m_userShell};

  for (const QString& path : candidates) {
    if (QFileInfo::exists(path)) {
      m_watcher.addPath(path);
    }
  }
}

QColor Theme::withAlpha(const QColor& c, qreal a) {
  QColor out = c;

  out.setAlphaF(static_cast<float>(std::clamp(a, 0.0, 1.0)));

  return out;
}
