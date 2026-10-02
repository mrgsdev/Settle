import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/store.dart';
import 'about.dart';
import 'actions.dart';
import 'pages/balance_page.dart';
import 'pages/debts_page.dart';
import 'pages/dynamics_page.dart';
import 'pages/expenses_page.dart';
import 'pages/overview_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/menu_button.dart';

/// Каркас: верхняя панель с вкладками и текущая страница.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  static const _tabs = ['Обзор', 'Баланс', 'Расходы', 'Динамика', 'Долги'];

  late final AppLifecycleListener _lifecycle;

  void _go(int i) => setState(() => _tab = i);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // Перед закрытием и при сворачивании — сразу сохранить данные.
    _lifecycle = AppLifecycleListener(
      onHide: () => StoreScope.read(context).save(),
      onExitRequested: () async {
        await StoreScope.read(context).save();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lifecycle.dispose();
    super.dispose();
  }

  /// ⌘O / Ctrl+O — импорт, ⌘S / Ctrl+S — экспорт, ⌘1…5 — вкладки.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    final hk = HardwareKeyboard.instance;
    final mod = Platform.isMacOS ? hk.isMetaPressed : hk.isControlPressed;
    if (!mod || hk.isAltPressed || hk.isShiftPressed) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false; // открыт диалог
    }
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.keyO) {
      importExcel(context);
    } else if (key == LogicalKeyboardKey.keyS) {
      exportExcel(context);
    } else if (digits.contains(key)) {
      _go(digits.indexOf(key));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);

    final page = switch (_tab) {
      0 => OverviewPage(onNavigate: _go),
      1 => const BalancePage(),
      2 => const ExpensesPage(),
      3 => const DynamicsPage(),
      _ => const DebtsPage(),
    };

    return Scaffold(
      body: Column(
        children: [
          _TopBar(tab: _tab, tabs: _tabs, onTab: _go),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOut,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: KeyedSubtree(
                key: ValueKey('$_tab/${store.revision}'),
                child: page,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.tab, required this.tabs, required this.onTab});
  final int tab;
  final List<String> tabs;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final mac = Platform.isMacOS;
    final mod = mac ? '⌘' : 'Ctrl+';
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const AppLogo(),
          const SizedBox(width: 10),
          Text('Settle', style: AppText.appTitle),
          const SizedBox(width: 48),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _NavTab(
                      label: tabs[i],
                      selected: i == tab,
                      onTap: () => onTab(i),
                      shortcut: '$mod${i + 1}',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          const _SaveStatus(),
          const SizedBox(width: 16),
          MenuButton<String>(
            tooltip: 'Ещё',
            items: () => [
              menuItem(
                'import',
                'Импорт из Excel…',
                icon: Icons.file_open_outlined,
              ),
              menuItem(
                'export',
                'Экспорт в Excel…',
                icon: Icons.save_alt_rounded,
              ),
              const PopupMenuDivider(),
              menuItem(
                'folder',
                'Папка с данными приложения',
                icon: Icons.folder_open_outlined,
              ),
              menuItem(
                'reset',
                'Начать с шаблона…',
                icon: Icons.restart_alt_rounded,
              ),
              const PopupMenuDivider(),
              menuItem(
                'theme',
                'Оформление…',
                icon: AppColors.isDark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
              ),
              menuItem(
                'about',
                'О программе',
                icon: Icons.info_outline_rounded,
              ),
            ],
            onSelected: (v) {
              switch (v) {
                case 'theme':
                  showThemeDialog(context);
                case 'about':
                  showAbout(context);
                case 'import':
                  importExcel(context);
                case 'export':
                  exportExcel(context);
                case 'folder':
                  final path = StoreScope.read(context).dataPath;
                  if (path != null) revealInFiles(path);
                case 'reset':
                  resetToTemplate(context);
              }
            },
          ),
          const SizedBox(width: 10),
          AppButton(
            label: 'Импорт',
            tooltip: 'Загрузить книгу .xlsx ($mod O)',
            onPressed: () => importExcel(context),
          ),
          const SizedBox(width: 10),
          AppButton.primary(
            label: 'Экспорт',
            tooltip: 'Сохранить в Excel ($mod S)',
            onPressed: () => exportExcel(context),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.shortcut,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String shortcut;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hover;
    return Tooltip(
      message: widget.shortcut,
      waitDuration: const Duration(milliseconds: 900),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: widget.selected ? AppColors.text : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 15,
                color: active ? AppColors.text : AppColors.secondary,
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveStatus extends StatelessWidget {
  const _SaveStatus();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.saveError != null) {
      return Tooltip(
        message: store.saveError!,
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: AppColors.negative,
            ),
            SizedBox(width: 6),
            Text(
              'Не сохранено',
              style: TextStyle(fontSize: 13, color: AppColors.negative),
            ),
          ],
        ),
      );
    }
    if (store.lastSaved == null) return const SizedBox();
    final t = store.lastSaved!;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Tooltip(
      message:
          'Данные сохраняются автоматически в зашифрованном виде\n${store.dataPath ?? ''}',
      child: Row(
        children: [
          Icon(Icons.check_rounded, size: 16, color: AppColors.faint),
          const SizedBox(width: 6),
          Text(
            'Сохранено в $time',
            style: TextStyle(fontSize: 13, color: AppColors.faint),
          ),
        ],
      ),
    );
  }
}
