import 'dart:math' as math;

/// A pure, Flutter-free value type describing a desktop window's geometry:
/// its logical size, optional top-left position, and whether it was maximized.
///
/// This is the serialization unit persisted under the `window_frame` settings
/// key and restored on the next desktop launch. Keeping it pure (no
/// `window_manager` / `dart:ui` imports) makes the interesting logic —
/// JSON round-tripping and [clampToBounds] — trivially unit-testable without a
/// real window, which the flutter test harness cannot provide.
///
/// All plugin wiring lives in `window_service.dart`; this file holds only data
/// and math.
class WindowFrame {
  const WindowFrame({
    required this.width,
    required this.height,
    this.x,
    this.y,
    this.maximized = false,
  });

  /// Minimum window width (logical px) we ever restore or request. Also fed to
  /// `windowManager.setMinimumSize` so the OS enforces it during live resizing.
  static const double minWidth = 640;

  /// Minimum window height (logical px). See [minWidth].
  static const double minHeight = 480;

  /// Default size used when no frame has been persisted yet. The window is
  /// centered rather than positioned in this case (see [x]/[y] being null).
  static const double defaultWidth = 1024;

  /// Default height. See [defaultWidth].
  static const double defaultHeight = 768;

  /// The default frame for a first launch: a sensible size, centered (null
  /// position), not maximized.
  static const WindowFrame defaultFrame = WindowFrame(
    width: defaultWidth,
    height: defaultHeight,
  );

  final double width;
  final double height;

  /// Top-left X of the window in the display coordinate space, or `null` when
  /// unknown — in which case the caller should center the window instead of
  /// positioning it.
  final double? x;

  /// Top-left Y. See [x].
  final double? y;

  /// Whether the window was maximized when last persisted. When true the caller
  /// should maximize on restore, keeping [width]/[height] (and [x]/[y]) as the
  /// restored ("un-maximized") bounds to fall back to.
  final bool maximized;

  /// True when both [x] and [y] are known, so the window can be positioned
  /// rather than centered.
  bool get hasPosition => x != null && y != null;

  WindowFrame copyWith({
    double? width,
    double? height,
    double? x,
    double? y,
    bool? maximized,
  }) {
    return WindowFrame(
      width: width ?? this.width,
      height: height ?? this.height,
      x: x ?? this.x,
      y: y ?? this.y,
      maximized: maximized ?? this.maximized,
    );
  }

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'maximized': maximized,
  };

  /// Decodes a [WindowFrame] from a previously persisted JSON map, tolerating
  /// missing or malformed keys: absent/invalid width/height fall back to the
  /// defaults, absent position stays null (→ center), and a missing
  /// `maximized` flag is treated as `false`. Returns `null` only when [json]
  /// is not a map at all.
  static WindowFrame? fromJson(Object? json) {
    if (json is! Map) return null;
    final width = _asPositiveDouble(json['width']) ?? defaultWidth;
    final height = _asPositiveDouble(json['height']) ?? defaultHeight;
    return WindowFrame(
      width: width,
      height: height,
      x: _asFiniteDouble(json['x']),
      y: _asFiniteDouble(json['y']),
      maximized: json['maximized'] == true,
    );
  }

  /// Returns a frame guaranteed to fit within [visible] (a display's visible
  /// frame, with [visibleX]/[visibleY] its top-left origin) and to be no
  /// smaller than [minWidth]×[minHeight]:
  ///
  ///  * size is clamped up to the minimum and down to the display size (a
  ///    window saved on a large monitor never reopens larger than a smaller
  ///    display),
  ///  * position (when known) is nudged so the whole window sits inside the
  ///    visible bounds — pulling an off-screen frame back on-screen. If a
  ///    minimum-sized window still cannot fit (tiny display), it is pinned to
  ///    the visible origin.
  ///
  /// [maximized] is preserved unchanged.
  WindowFrame clampToBounds({
    required double visibleWidth,
    required double visibleHeight,
    double visibleX = 0,
    double visibleY = 0,
  }) {
    // Clamp size: at least the minimum, at most the visible display size.
    final clampedWidth = math.min(
      math.max(width, minWidth),
      math.max(visibleWidth, minWidth),
    );
    final clampedHeight = math.min(
      math.max(height, minHeight),
      math.max(visibleHeight, minHeight),
    );

    double? clampedX = x;
    double? clampedY = y;
    if (hasPosition) {
      // Largest origin that keeps the window fully on-screen. If the window is
      // wider/taller than the display this goes below visibleX/Y, so we floor
      // at the visible origin (pin to top-left).
      final maxX = visibleX + visibleWidth - clampedWidth;
      final maxY = visibleY + visibleHeight - clampedHeight;
      clampedX = math.min(math.max(x!, visibleX), math.max(maxX, visibleX));
      clampedY = math.min(math.max(y!, visibleY), math.max(maxY, visibleY));
    }

    return WindowFrame(
      width: clampedWidth,
      height: clampedHeight,
      x: clampedX,
      y: clampedY,
      maximized: maximized,
    );
  }

  static double? _asFiniteDouble(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  static double? _asPositiveDouble(Object? value) {
    final d = _asFiniteDouble(value);
    if (d == null || d <= 0) return null;
    return d;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowFrame &&
      other.width == width &&
      other.height == height &&
      other.x == x &&
      other.y == y &&
      other.maximized == maximized;

  @override
  int get hashCode => Object.hash(width, height, x, y, maximized);

  @override
  String toString() =>
      'WindowFrame(width: $width, height: $height, x: $x, y: $y, '
      'maximized: $maximized)';
}
