import 'package:flutter/material.dart';

import '../app_info.dart';
import 'actions.dart';
import 'settings.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// «О программе»: значок, версия, ссылка на разработчика.
Future<void> showAbout(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const AppLogo(size: 72),
          const SizedBox(height: 16),
          Text('Settle', style: AppText.pageTitle.copyWith(fontSize: 24)),
          const SizedBox(height: 4),
          Text('Версия $appVersion', style: AppText.muted),
          const SizedBox(height: 12),
          Text(
            'Учёт бюджета: баланс, расходы, динамика и долги '
            'в формате книги Excel.',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Разработчик: ', style: AppText.muted),
              DevLink(),
            ],
          ),
        ],
      ),
    ),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    actions: [AppButton(label: 'Закрыть', onPressed: () => Navigator.pop(ctx))],
  ),
);

/// Ссылка на страницу разработчика.
class DevLink extends StatefulWidget {
  const DevLink({super.key});

  @override
  State<DevLink> createState() => _DevLinkState();
}

class _DevLinkState extends State<DevLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: developerUrl,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => openUrl(developerUrl),
          child: Text(
            developerName,
            style: AppText.bodyMedium.copyWith(
              decoration: _hover
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Выбор темы: системная, светлая или тёмная.
Future<void> showThemeDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Оформление'),
    content: Builder(
      builder: (context) {
        final scope = ThemeScope.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Segmented<ThemeMode>(
              items: const [
                (ThemeMode.system, 'Как в системе'),
                (ThemeMode.light, 'Светлая'),
                (ThemeMode.dark, 'Тёмная'),
              ],
              value: scope.mode,
              onChanged: scope.onChanged,
            ),
            const SizedBox(height: 12),
            Text(
              'Тема сохраняется и действует с экрана входа.',
              style: AppText.small,
            ),
          ],
        );
      },
    ),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    actions: [
      AppButton.primary(label: 'Готово', onPressed: () => Navigator.pop(ctx)),
    ],
  ),
);
