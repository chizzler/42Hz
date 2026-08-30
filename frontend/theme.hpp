/*
 * 42Hz — Omarchy theme adapter.
 *
 * Resolves the active Omarchy theme into semantic UI tokens and keeps them
 * live. Theme integration is functional behaviour, not a one-time
 * approximation at launch, so every token is a bindable property and a single
 * `changed()` signal re-evaluates the lot.
 *
 * Sources, in increasing precedence:
 *
 *   ~/.local/state/omarchy/current/theme/colors.toml   foundational palette
 *   ~/.local/state/omarchy/current/theme/shell.toml    per-surface roles
 *   ~/.config/omarchy/shell.toml                       machine-level override
 *
 * The last of these survives theme switches and is where `omarchy display text
 * size` writes [font] base-size, so it must win over the theme's own file.
 *
 * This file reads Omarchy state and never writes it.
 */

#pragma once

#include <QColor>
#include <QtGlobal>
#include <algorithm>
#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

class Theme : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

  // Provenance. `ready` is false when no Omarchy state could be read and the
  // built-in fallback tokens are in force; the UI may surface that, but must
  // remain legible either way.
  Q_PROPERTY(bool ready READ ready NOTIFY changed)
  Q_PROPERTY(QString name READ name NOTIFY changed)
  Q_PROPERTY(bool dark READ dark NOTIFY changed)

  // Background levels, darkest to lightest.
  Q_PROPERTY(QColor backgroundDarker READ backgroundDarker NOTIFY changed)
  Q_PROPERTY(QColor backgroundDark READ backgroundDark NOTIFY changed)
  Q_PROPERTY(QColor background READ background NOTIFY changed)
  Q_PROPERTY(QColor backgroundLight READ backgroundLight NOTIFY changed)

  // Foreground levels, dimmest to brightest.
  Q_PROPERTY(QColor foregroundDim READ foregroundDim NOTIFY changed)
  Q_PROPERTY(QColor foreground READ foreground NOTIFY changed)
  Q_PROPERTY(QColor foregroundLight READ foregroundLight NOTIFY changed)
  Q_PROPERTY(QColor foregroundBright READ foregroundBright NOTIFY changed)

  Q_PROPERTY(QColor muted READ muted NOTIFY changed)
  Q_PROPERTY(QColor accent READ accent NOTIFY changed)
  Q_PROPERTY(QColor selection READ selection NOTIFY changed)

  // State colours. `error` is the one the runtime-state reporting leans on.
  Q_PROPERTY(QColor error READ error NOTIFY changed)
  Q_PROPERTY(QColor warning READ warning NOTIFY changed)
  Q_PROPERTY(QColor success READ success NOTIFY changed)

  // Spectrum ramp: low amplitude to peak.
  Q_PROPERTY(QColor spectrumLow READ spectrumLow NOTIFY changed)
  Q_PROPERTY(QColor spectrumHigh READ spectrumHigh NOTIFY changed)

  // Control chrome, from shell.toml [controls]. Alphas are 0..1 and are
  // applied by the caller over `foreground`, matching Omarchy's own scheme.
  Q_PROPERTY(qreal controlFillAlpha READ controlFillAlpha NOTIFY changed)
  Q_PROPERTY(qreal controlBorderAlpha READ controlBorderAlpha NOTIFY changed)
  Q_PROPERTY(qreal hoverFillAlpha READ hoverFillAlpha NOTIFY changed)
  Q_PROPERTY(qreal focusBorderAlpha READ focusBorderAlpha NOTIFY changed)
  Q_PROPERTY(qreal selectedFillAlpha READ selectedFillAlpha NOTIFY changed)
  Q_PROPERTY(qreal pressedFillAlpha READ pressedFillAlpha NOTIFY changed)

  // Typography. The family is the fontconfig alias Omarchy manages system-wide;
  // resolving it is fontconfig's job, not ours.
  Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY changed)
  Q_PROPERTY(int fontBaseSize READ fontBaseSize NOTIFY changed)

  // 42Hz's one line weight, derived from the type scale the way foot derives
  // rule thickness from cell size. Every drawn line reads this, so a frame and
  // a divider cannot drift to different weights.
  Q_PROPERTY(int lineThickness READ lineThickness NOTIFY changed)

 public:
  explicit Theme(QObject* parent = nullptr);

  [[nodiscard]] bool ready() const { return m_ready; }
  [[nodiscard]] QString name() const { return m_name; }
  [[nodiscard]] bool dark() const { return m_dark; }

  [[nodiscard]] QColor backgroundDarker() const { return m_backgroundDarker; }
  [[nodiscard]] QColor backgroundDark() const { return m_backgroundDark; }
  [[nodiscard]] QColor background() const { return m_background; }
  [[nodiscard]] QColor backgroundLight() const { return m_backgroundLight; }

  [[nodiscard]] QColor foregroundDim() const { return m_foregroundDim; }
  [[nodiscard]] QColor foreground() const { return m_foreground; }
  [[nodiscard]] QColor foregroundLight() const { return m_foregroundLight; }
  [[nodiscard]] QColor foregroundBright() const { return m_foregroundBright; }

  [[nodiscard]] QColor muted() const { return m_muted; }
  [[nodiscard]] QColor accent() const { return m_accent; }
  [[nodiscard]] QColor selection() const { return m_selection; }

  [[nodiscard]] QColor error() const { return m_error; }
  [[nodiscard]] QColor warning() const { return m_warning; }
  [[nodiscard]] QColor success() const { return m_success; }

  [[nodiscard]] QColor spectrumLow() const { return m_spectrumLow; }
  [[nodiscard]] QColor spectrumHigh() const { return m_spectrumHigh; }

  [[nodiscard]] qreal controlFillAlpha() const { return m_controlFillAlpha; }
  [[nodiscard]] qreal controlBorderAlpha() const { return m_controlBorderAlpha; }
  [[nodiscard]] qreal hoverFillAlpha() const { return m_hoverFillAlpha; }
  [[nodiscard]] qreal focusBorderAlpha() const { return m_focusBorderAlpha; }
  [[nodiscard]] qreal selectedFillAlpha() const { return m_selectedFillAlpha; }
  [[nodiscard]] qreal pressedFillAlpha() const { return m_pressedFillAlpha; }

  [[nodiscard]] QString fontFamily() const { return m_fontFamily; }
  [[nodiscard]] int fontBaseSize() const { return m_fontBaseSize; }

  [[nodiscard]] int lineThickness() const { return std::max(1, qRound(m_fontBaseSize * 0.09)); }

  // Apply an alpha to a token. QML has Qt.alpha() only from 6.x in some
  // builds; this keeps call sites explicit and testable.
  Q_INVOKABLE static QColor withAlpha(const QColor& c, qreal a);

  // Re-read every source now. Exposed for `42hzctl theme reload` and tests.
  Q_INVOKABLE void reload();

 Q_SIGNALS:
  void changed();

 private:
  void scheduleReload();
  void rewatch();

  static QHash<QString, QString> parseColors(const QString& text);
  static QHash<QString, QString> parseShell(const QString& text);
  static QString readFile(const QString& path);

  QString m_statePath;   // ~/.local/state/omarchy/current
  QString m_themePath;   // ...           /current/theme
  QString m_userShell;   // ~/.config/omarchy/shell.toml

  QFileSystemWatcher m_watcher;
  QTimer m_coalescer;

  bool m_ready = false;
  QString m_name;
  bool m_dark = true;

  QColor m_backgroundDarker, m_backgroundDark, m_background, m_backgroundLight;
  QColor m_foregroundDim, m_foreground, m_foregroundLight, m_foregroundBright;
  QColor m_muted, m_accent, m_selection;
  QColor m_error, m_warning, m_success;
  QColor m_spectrumLow, m_spectrumHigh;

  qreal m_controlFillAlpha = 0.04;
  qreal m_controlBorderAlpha = 0.4;
  qreal m_hoverFillAlpha = 0.08;
  qreal m_focusBorderAlpha = 0.25;
  qreal m_selectedFillAlpha = 0.18;
  qreal m_pressedFillAlpha = 0.22;

  QString m_fontFamily = QStringLiteral("monospace");
  int m_fontBaseSize = 12;
};
