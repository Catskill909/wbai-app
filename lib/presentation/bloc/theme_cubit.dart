import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's light/dark choice across app launches.
/// Dark is the default the first time the app is opened.
class ThemeCubit extends Cubit<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  ThemeCubit() : super(ThemeMode.dark);

  /// Loads the saved preference, if any. Call before runApp so the first
  /// frame already reflects the user's last choice.
  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    emit(saved == 'light' ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    emit(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next == ThemeMode.dark ? 'dark' : 'light');
  }
}
