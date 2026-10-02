import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'model/store.dart';
import 'security/vault.dart';
import 'ui/lock_screen.dart';
import 'ui/settings.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await BudgetStore.dataDirectory();
  runApp(SettleApp(dataDir: dir, themeMode: await AppSettings.loadTheme(dir)));
}

class SettleApp extends StatefulWidget {
  const SettleApp({
    super.key,
    this.store,
    this.dataDir,
    this.kdf = PasswordKdf.standard,
    this.themeMode = ThemeMode.light,
  }) : assert(store != null || dataDir != null);

  /// Тема при запуске: системная, светлая или тёмная.
  final ThemeMode themeMode;

  /// Уже открытые данные — без экрана пароля (тесты, скриншоты).
  final BudgetStore? store;

  /// Папка с зашифрованными данными: сначала пароль, потом приложение.
  final Directory? dataDir;

  /// Сложность ключа из пароля для нового файла данных.
  final PasswordKdf kdf;

  @override
  State<SettleApp> createState() => _SettleAppState();
}

class _SettleAppState extends State<SettleApp> with WidgetsBindingObserver {
  late BudgetStore? _store = widget.store;
  late ThemeMode _themeMode = widget.themeMode;

  void _unlocked(BudgetStore store) => setState(() => _store = store);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyPalette();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system) setState(_applyPalette);
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
      _applyPalette();
    });
    final dir = widget.dataDir;
    if (dir != null) AppSettings.saveTheme(dir, mode);
  }

  /// Цвета берутся из [AppColors.palette], поэтому при смене темы
  /// перестраиваем все виджеты — их состояние (вкладка, ввод) сохраняется.
  void _applyPalette() {
    final dark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    final palette = dark ? AppPalette.darkPalette : AppPalette.light;
    if (identical(AppColors.palette, palette)) return;
    AppColors.palette = palette;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    if (mounted) (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Settle',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeAnimationDuration: Duration.zero,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Хранилище — над навигатором, чтобы его видели и диалоги.
      builder: (context, child) => ThemeScope(
        mode: _themeMode,
        onChanged: _setThemeMode,
        child: StoreScope(store: _store, child: child!),
      ),
      home: _Home(
        dataDir: widget.dataDir,
        kdf: widget.kdf,
        onUnlocked: _unlocked,
      ),
    );
  }
}

/// Экран пароля, пока данные не открыты, затем — само приложение.
class _Home extends StatelessWidget {
  const _Home({
    required this.dataDir,
    required this.kdf,
    required this.onUnlocked,
  });

  final Directory? dataDir;
  final PasswordKdf kdf;
  final ValueChanged<BudgetStore> onUnlocked;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.maybeOf(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: store != null
          ? const AppShell()
          : LockScreen(dataDir: dataDir!, kdf: kdf, onUnlocked: onUnlocked),
    );
  }
}
