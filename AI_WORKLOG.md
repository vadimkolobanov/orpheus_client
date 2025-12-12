# AI_WORKLOG

Р–СѓСЂРЅР°Р» РґРµР№СЃС‚РІРёР№ РР/Р°РіРµРЅС‚Р° РІ СЌС‚РѕРј СЂРµРїРѕР·РёС‚РѕСЂРёРё (РєР»РёРµРЅС‚).

---

## 2025-12-12
- Time: 00:00 local
- Task: РРЅРёС†РёР°Р»РёР·Р°С†РёСЏ РїСЂРѕС†РµСЃСЃР° СЂР°Р·СЂР°Р±РѕС‚РєРё (Cursor rules/commands, docs, hooks)
- Changes:
  - Р”РѕР±Р°РІР»РµРЅС‹ С€Р°Р±Р»РѕРЅС‹ РґРѕРєСѓРјРµРЅС‚Р°С†РёРё Рё Р¶СѓСЂРЅР°Р»РѕРІ.
  - Р”РѕР±Р°РІР»РµРЅС‹ РїСЂР°РІРёР»Р°/РєРѕРјР°РЅРґС‹ Cursor РґР»СЏ РґРёСЃС†РёРїР»РёРЅС‹ Р°СЂС‚РµС„Р°РєС‚РѕРІ.
  - Р”РѕР±Р°РІР»РµРЅ git hook, РєРѕС‚РѕСЂС‹Р№ РЅРµ РґР°СЃС‚ Р·Р°Р±С‹С‚СЊ РѕР±РЅРѕРІРёС‚СЊ `CHANGELOG.md`/`AI_WORKLOG.md`.
- Files:
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
  - `docs/README.md`
  - `docs/ARCHITECTURE.md`
  - `docs/DECISIONS/0001-ai-process.md`
  - `.cursor/rules/*`
  - `.cursor/commands/*`
  - `.githooks/pre-commit`
  - `scripts/install-hooks.ps1`
  - `.gitignore`
- Commands:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1`
  - `flutter pub get`
  - `flutter test` / `.\test_runner.ps1`

## 2025-12-12
- Time: 15:44 local
- Task: РџСЂРѕС„РёР»СЊ вЂ” РїРѕРєР°Р·С‹РІР°С‚СЊ СЂРµР°Р»СЊРЅСѓСЋ РІРµСЂСЃРёСЋ РїСЂРёР»РѕР¶РµРЅРёСЏ
- Changes:
  - Р’ СЌРєСЂР°РЅРµ РїСЂРѕС„РёР»СЏ РІРµСЂСЃРёСЏ С‚РµРїРµСЂСЊ Р±РµСЂС‘С‚СЃСЏ РёР· `package_info_plus` (СЂРµР°Р»СЊРЅС‹Рµ `version+buildNumber`) СЃ fallback РЅР° `AppConfig.appVersion`.
  - РћР±РЅРѕРІР»С‘РЅ С‚РµСЃС‚ РІРµСЂСЃРёРё `AppConfig` (SemVer/`v`-РїСЂРµС„РёРєСЃ).
- Files:
  - `lib/screens/settings_screen.dart`
  - `CHANGELOG.md`
  - `test/config_test.dart`

## 2025-12-12
- Time: 15:44 local
- Task: Android вЂ” splash + BootReceiver
- Changes:
  - Android < 12: `launch_background.xml` РїРµСЂРµРєР»СЋС‡С‘РЅ РЅР° `@drawable/splash`.
  - Android < 12: `launch_background.xml` С‚РµРїРµСЂСЊ РјР°СЃС€С‚Р°Р±РёСЂСѓРµС‚ `@drawable/splash`, С‡С‚РѕР±С‹ РєР°СЂС‚РёРЅРєР° РЅРµ РІС‹С…РѕРґРёР»Р° Р·Р° РіСЂР°РЅРёС†С‹.
  - Android 12+: РґРѕР±Р°РІР»РµРЅС‹ СЂРµСЃСѓСЂСЃС‹ `android12splash` Рё СЃС‚РёР»Рё `values-v31`.
  - Android splash: `splash.png`/`android12splash.png` РѕР±РЅРѕРІР»РµРЅС‹ РёР· `assets/images/logo.png` (С‰РёС‚ + ORPHEUS).
  - Р”РѕР±Р°РІР»РµРЅ `BootReceiver` Рё СЂРµРіРёСЃС‚СЂР°С†РёСЏ РІ `AndroidManifest.xml` (+ `RECEIVE_BOOT_COMPLETED`).
- Files:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/kotlin/com/example/orpheus_project/BootReceiver.kt`
  - `android/app/src/main/res/drawable*/launch_background.xml`
  - `android/app/src/main/res/drawable-*/splash.png`
  - `android/app/src/main/res/drawable-*/android12splash.png`
  - `android/app/src/main/res/values-v31/styles.xml`
  - `android/app/src/main/res/values-night-v31/styles.xml`
  - `docs/README.md`
  - `CHANGELOG.md`
