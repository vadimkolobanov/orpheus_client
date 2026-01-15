import 'package:flutter/material.dart';
import 'package:orpheus_project/theme/app_tokens.dart';

/// Базовый каркас экранов для единого визуального языка.
///
/// - Единый фон/поверхность
/// - Единые отступы
/// - Без декоративных анимаций по умолчанию
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.padding,
    this.safeArea = true,
    this.backgroundColor,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final EdgeInsets? padding;
  final bool safeArea;
  final Color? backgroundColor;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    Widget content = padding == null
        ? body
        : Padding(
            padding: padding!,
            child: body,
          );

    if (safeArea) {
      content = SafeArea(child: content);
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.bg,
      appBar: appBar,
      body: content,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

