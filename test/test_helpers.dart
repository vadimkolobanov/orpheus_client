import 'package:flutter/material.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';

Widget testApp(Widget home) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: home,
    );
