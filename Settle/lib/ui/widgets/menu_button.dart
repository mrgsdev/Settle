import 'package:flutter/material.dart';

import 'common.dart';

/// Кнопка, открывающая выпадающее меню под собой.
class MenuButton<T> extends StatelessWidget {
  const MenuButton({
    super.key,
    this.icon = Icons.more_horiz_rounded,
    this.label,
    required this.items,
    required this.onSelected,
    this.kind = BtnKind.secondary,
    this.tooltip,
    this.dense = false,
  });

  final IconData? icon;
  final String? label;
  final List<PopupMenuEntry<T>> Function() items;
  final ValueChanged<T> onSelected;
  final BtnKind kind;
  final String? tooltip;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) {
        return AppButton(
          icon: icon,
          label: label,
          kind: kind,
          dense: dense,
          tooltip: tooltip,
          onPressed: () async {
            final box = ctx.findRenderObject() as RenderBox;
            final overlay =
                Overlay.of(ctx).context.findRenderObject() as RenderBox;
            final topLeft = box.localToGlobal(
              Offset(0, box.size.height + 6),
              ancestor: overlay,
            );
            final bottomRight = box.localToGlobal(
              box.size.bottomRight(const Offset(0, 6)),
              ancestor: overlay,
            );
            final v = await showMenu<T>(
              context: ctx,
              position: RelativeRect.fromRect(
                Rect.fromPoints(topLeft, bottomRight),
                Offset.zero & overlay.size,
              ),
              items: items(),
            );
            if (v != null) onSelected(v);
          },
        );
      },
    );
  }
}

PopupMenuItem<T> menuItem<T>(
  T value,
  String label, {
  IconData? icon,
  Color? color,
}) => PopupMenuItem<T>(
  value: value,
  height: 38,
  child: Row(
    children: [
      if (icon != null) ...[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
      ],
      Text(label, style: TextStyle(color: color)),
    ],
  ),
);
