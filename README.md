# Orpheus Client (Flutter)

РљР»РёРµРЅС‚СЃРєРѕРµ РїСЂРёР»РѕР¶РµРЅРёРµ РЅР° Flutter РґР»СЏ РїСЂРѕРµРєС‚Р° Orpheus.

## Р‘С‹СЃС‚СЂС‹Р№ СЃС‚Р°СЂС‚

### РўСЂРµР±РѕРІР°РЅРёСЏ
- Flutter SDK (СЃРј. `environment` РІ `pubspec.yaml`)
- Android SDK / Android Studio (РґР»СЏ Android)

### РЈСЃС‚Р°РЅРѕРІРєР° Р·Р°РІРёСЃРёРјРѕСЃС‚РµР№
```powershell
flutter pub get
```

### Р—Р°РїСѓСЃРє
```powershell
flutter run
```

## РўРµСЃС‚С‹ Рё РѕС‚С‡С‘С‚С‹
РЎРј.:
- `QUICK_START_TESTS.md`
- `TEST_REPORTS_GUIDE.md`

РћСЃРЅРѕРІРЅС‹Рµ РєРѕРјР°РЅРґС‹:
```powershell
flutter test
```
РР»Рё СЃ РіРµРЅРµСЂР°С†РёРµР№ РѕС‚С‡С‘С‚РѕРІ:
```powershell
.\test_runner.ps1
```

## Р”РѕРєСѓРјРµРЅС‚Р°С†РёСЏ
- РћСЃРЅРѕРІРЅР°СЏ: `docs/README.md`
- РђСЂС…РёС‚РµРєС‚СѓСЂР°: `docs/ARCHITECTURE.md`
- Р РµС€РµРЅРёСЏ (ADR): `docs/DECISIONS/`

## РџСЂРѕС†РµСЃСЃ РёР·РјРµРЅРµРЅРёР№ (С‡С‚РѕР±С‹ РР РЅРµ Р·Р°Р±С‹РІР°Р»)
- РѕР±РЅРѕРІРёС‚СЊ `CHANGELOG.md` (СЃРµРєС†РёСЏ `Unreleased`)
- РґРѕР±Р°РІРёС‚СЊ Р·Р°РїРёСЃСЊ РІ `AI_WORKLOG.md`
- РѕР±РЅРѕРІРёС‚СЊ `docs/*` РїСЂРё РЅРµРѕР±С…РѕРґРёРјРѕСЃС‚Рё

### Cursor
- РџСЂР°РІРёР»Р°: `.cursor/rules/`
- РљРѕРјР°РЅРґС‹-С€Р°Р±Р»РѕРЅС‹: `.cursor/commands/` (РЅР°РїСЂРёРјРµСЂ: `update-artifacts`, `update-changelog`, `log-work`, `commit-ready`)

### Git hooks (СЂРµРєРѕРјРµРЅРґСѓРµС‚СЃСЏ)
Р§С‚РѕР±С‹ РєРѕРјРјРёС‚ РЅРµР»СЊР·СЏ Р±С‹Р»Рѕ СЃРґРµР»Р°С‚СЊ Р±РµР· `CHANGELOG.md` Рё `AI_WORKLOG.md`:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```
