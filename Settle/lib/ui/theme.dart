import 'package:flutter/material.dart';

/// Цвета одной темы.
class AppPalette {
  const AppPalette({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.border,
    required this.divider,
    required this.text,
    required this.secondary,
    required this.muted,
    required this.faint,
    required this.subtle,
    required this.raised,
    required this.hover,
    required this.today,
    required this.onPrimary,
    required this.primaryHover,
    required this.secondaryHover,
    required this.shadow,
    required this.chartGrid,
    required this.chartSecondary,
    required this.chartArea,
    required this.chartSeries,
    required this.positive,
    required this.negative,
    required this.consumption,
    required this.consumptionInk,
    required this.savings,
    required this.savingsInk,
    required this.investments,
    required this.investmentsInk,
    required this.investmentsChart,
    required this.remainder,
    required this.remainderInk,
    required this.avatars,
  });

  final bool dark;
  final Color bg, surface, border, divider;
  final Color text, secondary, muted, faint;
  final Color subtle, raised, hover, today;
  final Color onPrimary, primaryHover, secondaryHover, shadow;
  final Color chartGrid, chartSecondary, chartArea;
  final List<Color> chartSeries;
  final Color positive, negative;
  final Color consumption, consumptionInk, savings, savingsInk;
  final Color investments, investmentsInk, investmentsChart;
  final Color remainder, remainderInk;
  final List<(Color, Color)> avatars;

  /// Монохром как в референсе + мягкие заливки статей из исходного Excel.
  static const light = AppPalette(
    dark: false,
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE4E4E4),
    divider: Color(0xFFEDEDED),
    text: Color(0xFF0A0A0A),
    secondary: Color(0xFF525252),
    muted: Color(0xFF737373),
    faint: Color(0xFFA3A3A3),
    subtle: Color(0xFFF2F2F2),
    raised: Color(0xFFFFFFFF),
    hover: Color(0xFFF7F7F7),
    today: Color(0xFFF5F5F5),
    onPrimary: Color(0xFFFFFFFF),
    primaryHover: Color(0xFF262626),
    secondaryHover: Color(0xFFE8E8E8),
    shadow: Color(0x14000000),
    chartGrid: Color(0xFFEBEBEB),
    chartSecondary: Color(0xFFBDBDBD),
    chartArea: Color(0x0F000000),
    chartSeries: [
      Color(0xFF0A0A0A),
      Color(0xFFBDBDBD),
      Color(0xFF7A7A7A),
      Color(0xFFDEDEDE),
      Color(0xFF404040),
    ],
    positive: Color(0xFF15803D),
    negative: Color(0xFFC62828),
    consumption: Color(0xFFFBE4D5),
    consumptionInk: Color(0xFF8A3D0C),
    savings: Color(0xFFDDEBF7),
    savingsInk: Color(0xFF1F4E79),
    investments: Color(0xFFECECEC),
    investmentsInk: Color(0xFF3D3D3D),
    investmentsChart: Color(0xFF404040),
    remainder: Color(0xFFE2EFDA),
    remainderInk: Color(0xFF375623),
    avatars: [
      (Color(0xFFFBE4D5), Color(0xFF8A3D0C)),
      (Color(0xFFDDEBF7), Color(0xFF1F4E79)),
      (Color(0xFFE2EFDA), Color(0xFF375623)),
      (Color(0xFFFFF2CC), Color(0xFF7F6000)),
      (Color(0xFFEDEDED), Color(0xFF262626)),
      (Color(0xFFD9E1F2), Color(0xFF203864)),
    ],
  );

  static const darkPalette = AppPalette(
    dark: true,
    bg: Color(0xFF111111),
    surface: Color(0xFF191919),
    border: Color(0xFF2E2E2E),
    divider: Color(0xFF262626),
    text: Color(0xFFEDEDED),
    secondary: Color(0xFFB4B4B4),
    muted: Color(0xFF9A9A9A),
    faint: Color(0xFF6B6B6B),
    subtle: Color(0xFF242424),
    raised: Color(0xFF333333),
    hover: Color(0xFF202020),
    today: Color(0xFF232323),
    onPrimary: Color(0xFF111111),
    primaryHover: Color(0xFFD4D4D4),
    secondaryHover: Color(0xFF2E2E2E),
    shadow: Color(0x66000000),
    chartGrid: Color(0xFF2A2A2A),
    chartSecondary: Color(0xFF5A5A5A),
    chartArea: Color(0x14FFFFFF),
    chartSeries: [
      Color(0xFFEDEDED),
      Color(0xFF5A5A5A),
      Color(0xFF9A9A9A),
      Color(0xFF3A3A3A),
      Color(0xFFC4C4C4),
    ],
    positive: Color(0xFF4ADE80),
    negative: Color(0xFFF87171),
    consumption: Color(0xFF3B2618),
    consumptionInk: Color(0xFFF4B084),
    savings: Color(0xFF172A3D),
    savingsInk: Color(0xFF9DC3E6),
    investments: Color(0xFF2A2A2A),
    investmentsInk: Color(0xFFD0D0D0),
    investmentsChart: Color(0xFFA0A0A0),
    remainder: Color(0xFF1D2C18),
    remainderInk: Color(0xFFA9D18E),
    avatars: [
      (Color(0xFF3B2618), Color(0xFFF4B084)),
      (Color(0xFF172A3D), Color(0xFF9DC3E6)),
      (Color(0xFF1D2C18), Color(0xFFA9D18E)),
      (Color(0xFF332A12), Color(0xFFFFD966)),
      (Color(0xFF2A2A2A), Color(0xFFD9D9D9)),
      (Color(0xFF1B2337), Color(0xFFB4C6E7)),
    ],
  );
}

/// Цвета текущей темы. Переключение темы меняет [palette] и перестраивает
/// всё дерево виджетов (см. SettleApp).
abstract final class AppColors {
  static AppPalette palette = AppPalette.light;

  static bool get isDark => palette.dark;
  static Color get bg => palette.bg;
  static Color get surface => palette.surface;
  static Color get border => palette.border;
  static Color get divider => palette.divider;
  static Color get text => palette.text;
  static Color get secondary => palette.secondary;
  static Color get muted => palette.muted;
  static Color get faint => palette.faint;
  static Color get subtle => palette.subtle;
  static Color get raised => palette.raised;
  static Color get hover => palette.hover;
  static Color get today => palette.today;
  static Color get onPrimary => palette.onPrimary;
  static Color get primaryHover => palette.primaryHover;
  static Color get secondaryHover => palette.secondaryHover;
  static Color get shadow => palette.shadow;
  static Color get chartGrid => palette.chartGrid;
  static Color get chartSecondary => palette.chartSecondary;
  static Color get chartArea => palette.chartArea;
  static List<Color> get chartSeries => palette.chartSeries;
  static Color get positive => palette.positive;
  static Color get negative => palette.negative;

  // Заливки из «Бюджет.xlsx»: Потребление — оранжевая, Сбережение — голубая.
  static Color get consumption => palette.consumption;
  static Color get consumptionInk => palette.consumptionInk;
  static Color get savings => palette.savings;
  static Color get savingsInk => palette.savingsInk;
  static Color get investments => palette.investments;
  static Color get investmentsInk => palette.investmentsInk;
  static Color get investmentsChart => palette.investmentsChart;
  static Color get remainder => palette.remainder;
  static Color get remainderInk => palette.remainderInk;
  static List<(Color, Color)> get avatars => palette.avatars;
}

abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle get appTitle => TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
    letterSpacing: -0.3,
  );
  static TextStyle get pageTitle => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
    letterSpacing: -0.6,
    height: 1.15,
  );
  static TextStyle get cardTitle => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
    letterSpacing: -0.1,
  );
  static TextStyle get kpi => TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
    letterSpacing: -1.1,
    height: 1.1,
    fontFeatures: _tabular,
  );
  static TextStyle get body =>
      TextStyle(fontSize: 15, color: AppColors.text, height: 1.35);
  static TextStyle get bodyMedium => TextStyle(
    fontSize: 15,
    color: AppColors.text,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
  static TextStyle get num => TextStyle(
    fontSize: 15,
    color: AppColors.text,
    height: 1.35,
    fontFeatures: _tabular,
  );
  static TextStyle get numBold => TextStyle(
    fontSize: 15,
    color: AppColors.text,
    fontWeight: FontWeight.w600,
    height: 1.35,
    fontFeatures: _tabular,
  );
  static TextStyle get muted =>
      TextStyle(fontSize: 15, color: AppColors.muted, height: 1.35);
  static TextStyle get small =>
      TextStyle(fontSize: 13, color: AppColors.muted, height: 1.3);
  static TextStyle get axis =>
      TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: _tabular);
  static TextStyle get header => TextStyle(
    fontSize: 14,
    color: AppColors.muted,
    fontWeight: FontWeight.w500,
  );
}

ThemeData buildTheme() {
  final dark = AppColors.isDark;
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
        primary: AppColors.text,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.text,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        outline: AppColors.border,
        error: AppColors.negative,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: AppColors.hover,
    dividerColor: AppColors.divider,
    visualDensity: VisualDensity.standard,
  );
  // Всплывающие элементы (подсказки, уведомления) — контрастные к фону.
  final inverse = AppColors.text, onInverse = AppColors.onPrimary;
  return base.copyWith(
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.text,
      selectionColor: dark ? const Color(0xFF4A4A4A) : const Color(0xFFD6D6D6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: inverse,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(fontFamily: 'Inter', color: onInverse, fontSize: 13),
      waitDuration: const Duration(milliseconds: 500),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: dark ? Colors.black : Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      textStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: AppColors.text,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: AppText.cardTitle.copyWith(
        fontFamily: 'Inter',
        fontSize: 18,
      ),
      contentTextStyle: AppText.body.copyWith(fontFamily: 'Inter'),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: inverse,
      behavior: SnackBarBehavior.floating,
      width: 520,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: onInverse,
        fontSize: 14,
      ),
      actionTextColor: onInverse,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.text
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(AppColors.onPrimary),
      side: BorderSide(color: AppColors.faint, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: AppColors.text,
      headerForegroundColor: AppColors.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      todayBorder: BorderSide(color: AppColors.text),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
        dark ? const Color(0x44FFFFFF) : const Color(0x33000000),
      ),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
  );
}
