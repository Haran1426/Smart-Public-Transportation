import 'package:material_ui/material_ui.dart';

class TransitPalette {
  const TransitPalette({
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.divider,
    required this.accent,
    required this.accentContainer,
    required this.onAccent,
    required this.subway,
    required this.subwayContainer,
    required this.bus,
    required this.busContainer,
  });

  static const marker = Color(0xffffb887);
  static const markerInk = Color(0xff271d2b);

  static const light = TransitPalette(
    canvas: Color(0xfff9f2eb),
    surface: Color(0xfffffcf8),
    ink: Color(0xff292030),
    muted: Color(0xff635669),
    divider: Color(0xffe5d6d5),
    accent: Color(0xffa33924),
    accentContainer: Color(0xffffe9db),
    onAccent: Colors.white,
    subway: Color(0xff633b81),
    subwayContainer: Color(0xfff1e5fa),
    bus: Color(0xff274c94),
    busContainer: Color(0xffe5edff),
  );

  static const dark = TransitPalette(
    canvas: Color(0xff191627),
    surface: Color(0xff272136),
    ink: Color(0xfffff6ee),
    muted: Color(0xffd0c2db),
    divider: Color(0xff584968),
    accent: Color(0xffffc19a),
    accentContainer: Color(0xff493038),
    onAccent: markerInk,
    subway: Color(0xffead3ff),
    subwayContainer: Color(0xff463653),
    bus: Color(0xffc7daff),
    busContainer: Color(0xff303b59),
  );

  static TransitPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  final Color canvas;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color divider;
  final Color accent;
  final Color accentContainer;
  final Color onAccent;
  final Color subway;
  final Color subwayContainer;
  final Color bus;
  final Color busContainer;

  ThemeData theme(Brightness brightness) => ThemeData(
    scaffoldBackgroundColor: canvas,
    colorScheme: ColorScheme.fromSeed(seedColor: marker, brightness: brightness)
        .copyWith(
          primary: accent,
          onPrimary: onAccent,
          primaryContainer: accentContainer,
          onPrimaryContainer: accent,
          secondaryContainer: accentContainer,
          onSecondaryContainer: accent,
          surfaceContainerHighest: Color.alphaBlend(
            divider.withValues(alpha: 0.35),
            surface,
          ),
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: divider,
          outlineVariant: divider,
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: divider),
      ),
      filled: true,
      fillColor: surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
  );
}
