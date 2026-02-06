import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_button.dart';

/// Кастомный диалог Orpheus — Quiet Premium.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.content,
    this.contentWidget,
    this.primaryLabel,
    this.primaryOnPressed,
    this.secondaryLabel,
    this.secondaryOnPressed,
    this.isDanger = false,
  });

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? content;
  final Widget? contentWidget;
  final String? primaryLabel;
  final VoidCallback? primaryOnPressed;
  final String? secondaryLabel;
  final VoidCallback? secondaryOnPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final accent = isDanger ? AppColors.danger : AppColors.action;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lg,
        side: BorderSide(
          color: isDanger
              ? AppColors.danger.withOpacity(0.20)
              : AppColors.outline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (iconColor ?? accent).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor ?? accent, size: 28),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (content != null) ...[
              const SizedBox(height: 8),
              Text(
                content!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (contentWidget != null) ...[
              const SizedBox(height: 12),
              contentWidget!,
            ],
            if (primaryLabel != null || secondaryLabel != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  if (secondaryLabel != null)
                    Expanded(
                      child: AppButton(
                        label: secondaryLabel!,
                        variant: AppButtonVariant.secondary,
                        onPressed:
                            secondaryOnPressed ?? () => Navigator.pop(context),
                      ),
                    ),
                  if (secondaryLabel != null && primaryLabel != null)
                    const SizedBox(width: 10),
                  if (primaryLabel != null)
                    Expanded(
                      child: AppButton(
                        label: primaryLabel!,
                        variant: isDanger
                            ? AppButtonVariant.danger
                            : AppButtonVariant.primary,
                        onPressed: primaryOnPressed,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Показывает диалог и возвращает true если нажата primary кнопка.
  static Future<bool> show({
    required BuildContext context,
    IconData? icon,
    Color? iconColor,
    required String title,
    String? content,
    Widget? contentWidget,
    String? primaryLabel,
    String? secondaryLabel,
    bool isDanger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        icon: icon,
        iconColor: iconColor,
        title: title,
        content: content,
        contentWidget: contentWidget,
        primaryLabel: primaryLabel,
        primaryOnPressed: () => Navigator.pop(context, true),
        secondaryLabel: secondaryLabel,
        secondaryOnPressed: () => Navigator.pop(context, false),
        isDanger: isDanger,
      ),
    );
    return result ?? false;
  }
}

/// Диалог с полем ввода.
class AppInputDialog extends StatefulWidget {
  const AppInputDialog({
    super.key,
    this.icon,
    required this.title,
    this.content,
    required this.hintText,
    this.initialValue,
    this.maxLines = 1,
    this.prefixIcon,
    this.primaryLabel = 'Done',
    this.secondaryLabel = 'Cancel',
  });

  final IconData? icon;
  final String title;
  final String? content;
  final String hintText;
  final String? initialValue;
  final int maxLines;
  final IconData? prefixIcon;
  final String primaryLabel;
  final String secondaryLabel;

  @override
  State<AppInputDialog> createState() => _AppInputDialogState();

  static Future<String?> show({
    required BuildContext context,
    IconData? icon,
    required String title,
    String? content,
    required String hintText,
    String? initialValue,
    int maxLines = 1,
    IconData? prefixIcon,
    String primaryLabel = 'Done',
    String secondaryLabel = 'Cancel',
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => AppInputDialog(
        icon: icon,
        title: title,
        content: content,
        hintText: hintText,
        initialValue: initialValue,
        maxLines: maxLines,
        prefixIcon: prefixIcon,
        primaryLabel: primaryLabel,
        secondaryLabel: secondaryLabel,
      ),
    );
  }
}

class _AppInputDialogState extends State<AppInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.lg,
        side: BorderSide(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.icon != null) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.action.withOpacity(0.12),
                      borderRadius: AppRadii.sm,
                    ),
                    child:
                        Icon(widget.icon, color: AppColors.action, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            if (widget.content != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.content!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: widget.maxLines,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon:
                    widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: widget.secondaryLabel,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: widget.primaryLabel,
                    onPressed: () {
                      final text = _controller.text.trim();
                      Navigator.pop(context, text.isEmpty ? null : text);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
