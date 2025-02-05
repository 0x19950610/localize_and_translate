import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:localize_and_translate/src/assets/asset_loader_base.dart';
import 'package:localize_and_translate/src/constants/db_keys.dart';
import 'package:localize_and_translate/src/constants/enums.dart';
import 'package:localize_and_translate/src/constants/error_messages.dart';
import 'package:localize_and_translate/src/db/db_box.dart';
import 'package:localize_and_translate/src/db/usecases.dart';
import 'package:localize_and_translate/src/exceptions/not_found_exception.dart';
import 'package:localize_and_translate/src/mappers/json_mapper_base.dart';

/// [LocalizeAndTranslate] is the main class of the package.
/// It is used to initialize the package and to translate the words.
/// It is a singleton class.
/// It is used as follows:
/// ```dart
class LocalizeAndTranslate {
  /// [LocalizeAndTranslate] constructor
  factory LocalizeAndTranslate() => _instance;
  LocalizeAndTranslate._internal();
  static final LocalizeAndTranslate _instance = LocalizeAndTranslate._internal();

  /// [notifyUI] is the function that is used to notify the UI.
  static void Function()? notifyUI;

  ///---
  /// ### setLocale
  /// ---
  static Future<void> setLocale(Locale locale) async {
    await DBUseCases.write(DBKeys.languageCode, locale.languageCode);

    if (locale.countryCode == 'null') {
      await DBUseCases.write(DBKeys.countryCode, '');
    } else {
      await DBUseCases.write(DBKeys.countryCode, locale.countryCode ?? '');
    }

    await DBUseCases.write(
      DBKeys.isRTL,
      isRtlLanguage(locale.languageCode) ? 'true' : 'false',
    );

    notifyUI?.call();
  }

  /// ---
  /// ###  setHivePath
  /// ---
  static Future<void> setHivePath(String path) async {
    await DBUseCases.write(DBKeys.hivePath, path);
  }

  ///---
  /// ### setLanguageCode
  /// ---
  static Future<void> setLanguageCode(String languageCode) async {
    await setLocale(
      Locale(languageCode),
    );
  }

  ///---
  /// ###  Returns app locales.
  ///
  /// used in app entry point e.g. MaterialApp()
  /// ---
  static List<Locale> getLocals() {
    return DBUseCases.localesFromDBString(
      DBUseCases.readNullable(DBKeys.locales) ?? _getDeviceLanguageCode(),
    );
  }

  /// ---
  /// ###  Ensures that the package is initialized.
  /// ---
  static Future<void> init({
    required AssetLoaderBase assetLoader,
    List<AssetLoaderBase>? assetLoadersExtra,
    List<Locale>? supportedLocales,
    List<String>? supportedLanguageCodes,
    LocalizationDefaultType defaultType = LocalizationDefaultType.device,
    String? hivePath,
    HiveStorageBackendPreference? hiveBackendPreference,
    JsonMapperBase? mapper,
  }) async {
    if (hivePath != null && hiveBackendPreference != null) {
      Hive.init(hivePath, backendPreference: hiveBackendPreference);
    } else if (hivePath != null && hiveBackendPreference == null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }

    await DBBox.openBox();

    await _writeSettings(
      supportedLocales: supportedLocales,
      supportedLanguageCodes: supportedLanguageCodes,
      type: defaultType,
    );

    Map<String, dynamic> primaryTranslations = <String, dynamic>{};
    Map<String, dynamic> fallbackTranslations = <String, dynamic>{};
    Map<String, dynamic> finalTranslations = <String, dynamic>{};

    try {
      // Attempt to load translations using the primary asset loader
      primaryTranslations = await assetLoader.load(mapper);
      debugPrint('--LocalizeAndTranslate-- Primary asset loader succeeded');
    } catch (e) {
      debugPrint('--LocalizeAndTranslate-- Primary asset loader failed: $e');
    }

    if (assetLoadersExtra != null) {
      for (final AssetLoaderBase loader in assetLoadersExtra) {
        try {
          // Attempt to load translations using the secondary asset loader
          final Map<String, dynamic> secondaryTranslations = await loader.load(mapper);
          debugPrint('--LocalizeAndTranslate-- Secondary asset loader succeeded');
          fallbackTranslations = secondaryTranslations;
          break;
        } catch (e) {
          debugPrint('--LocalizeAndTranslate-- Secondary asset loader failed: $e');
        }
      }
    }

    // Merge primary and fallback translations
    finalTranslations = <String, dynamic>{...fallbackTranslations, ...primaryTranslations};

    await _writeTranslations(data: finalTranslations);

    debugPrint(
      '--LocalizeAndTranslate-- init | LanguageCode: ${getLanguageCode()}'
      ' | CountryCode: ${getCountryCode()} | isRTL: ${isRTL()}',
    );
  }

  /// ---
  /// ###  Returns Locale
  /// ---
  static Locale getLocale() {
    return Locale(
      getLanguageCode(),
      getCountryCode(),
    );
  }

  /// ---
  /// ###  Returns language code
  /// ---
  static String? getCountryCode() => DBUseCases.readNullable(DBKeys.countryCode);

  /// ---
  /// ###  Returns language code
  /// ---
  static String getLanguageCode() {
    final String? langCode = DBUseCases.readNullable(DBKeys.languageCode);

    if (langCode == null) {
      return _getDeviceLocale().split('-').first;
    }

    return langCode;
  }

  /// ---
  /// ###  Returns boolean value for isRTL
  /// ---
  static bool isRTL() {
    return DBUseCases.read(DBKeys.isRTL) == 'true';
  }

  /// ---
  /// ###  Returns translated string
  ///
  /// It takes the key and the default value.
  /// It returns the translated string.
  /// If the key is not found, it returns the default value.
  ///
  /// ---
  static String translate(String key, {String? defaultValue}) {
    final String? text = DBUseCases.readNullable(DBKeys.appendPrefix(key));

    return text ?? defaultValue ?? ErrorMessages.keyNotFound(key);
  }

  ///---
  /// ###  Returns app delegates.
  ///
  /// used in app entry point e.g. MaterialApp()
  /// ---
  static Iterable<LocalizationsDelegate<dynamic>> get delegates => <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ];

  ///---
  /// ###  builder directionality
  /// ---
  static Widget directionBuilder(BuildContext context, Widget? child) {
    return Directionality(
      textDirection: isRTL() ? TextDirection.rtl : TextDirection.ltr,
      child: child ?? const SizedBox(),
    );
  }

  ///---
  /// ###  Sets app locales.
  /// It takes the list of locales.
  /// It saves the list of locales to the database.
  /// ---
  static Future<void> _setLocales(List<Locale> locales) async {
    await DBUseCases.write(
      DBKeys.locales,
      DBUseCases.dbStringFromLocales(locales),
    );
  }

  /// ---
  /// ###  Ensures that the package is initialized.
  /// ---
  static Future<void> _writeSettings({
    List<Locale>? supportedLocales,
    List<String>? supportedLanguageCodes,
    LocalizationDefaultType? type = LocalizationDefaultType.device,
    String? hivePath,
  }) async {
    final List<Locale>? locales = supportedLocales ?? supportedLanguageCodes?.map(Locale.new).toList();

    if (locales == null) {
      throw NotFoundException('Locales not provided');
    }

    if (hivePath != null) {
      await setHivePath(hivePath);
    }

    await _setLocales(locales);

    if (_getSavedLanguageCode() != null) {
      await setLocale(getLocale());
      return;
    }

    if (type == LocalizationDefaultType.device) {
      await setLanguageCode(
        _getDeviceLanguageCode(),
      );
      return;
    }

    if (locales.isNotEmpty) {
      await setLocale(locales.first);
      return;
    }
  }

  /// ---
  /// ###  Writes translations to the database.
  /// ---
  static Future<void> _writeTranslations({
    required Map<String, dynamic> data,
  }) async {
    await DBUseCases.writeMap(
      data.map((String key, dynamic value) {
        return MapEntry<String, String>(key, value.toString());
      }),
    );
  }

  static String? _getSavedLanguageCode() {
    return DBUseCases.readNullable(DBKeys.languageCode);
  }

  /// ---
  /// ###  Returns device locale.
  /// ---
  static String _getDeviceLocale() {
    if (kIsWeb) {
      // Use `window.locale` for web
      return ui.window.locale.toString();
    }
    // Fallback for non-web platforms
    return Platform.localeName;
  }

  /// ---
  /// ###  Returns device language code.
  /// ---
  static String _getDeviceLanguageCode() {
    // split on - or _ to support locales like en-US or en_US
    return _getDeviceLocale().split(RegExp('[-_]+')).first;
  }

  /// ---
  /// ###  Determines if a language is written right-to-left based on its language code.
  /// ---
  static List<String> getKeys() {
    return DBUseCases.getKeys();
  }

  /// Determines if a language is written right-to-left based on its language code.
  static bool isRtlLanguage(String languageCode) {
    const Set<String> rtlLanguages = <String>{
      'ar', // Arabic
      'fa', // Persian
      'he', // Hebrew
      'ur', // Urdu
      'ps', // Pashto
      'sd', // Sindhi
    };

    return rtlLanguages.contains(languageCode);
  }
}
