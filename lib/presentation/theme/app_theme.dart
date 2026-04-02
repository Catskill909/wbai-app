import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// WBAI brand colors derived from the 4-quadrant logo
class WBAIColors {
  static const Color darkBrown = Color(0xFF3B2828);   // W tile — primary background
  static const Color midGray   = Color(0xFF6E7E8C);   // B tile — surface / card
  static const Color lightGray = Color(0xFF9BA5AF);   // A tile — surface light / dividers
  static const Color blue      = Color(0xFF1BB4D8);   // I tile — accent / interactive
  static const Color white     = Color(0xFFFFFFFF);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: WBAIColors.white,
      colorScheme: const ColorScheme.light(
        primary: WBAIColors.blue,
        secondary: WBAIColors.midGray,
        surface: WBAIColors.white,
        onPrimary: WBAIColors.white,
        onSecondary: WBAIColors.white,
        onSurface: WBAIColors.darkBrown,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: WBAIColors.darkBrown,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      cardTheme: const CardThemeData(
        color: WBAIColors.midGray,
      ),
      dividerTheme: const DividerThemeData(
        color: WBAIColors.lightGray,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: WBAIColors.blue,
        selectionHandleColor: WBAIColors.blue,
      ),
      textTheme: TextTheme(
        // Oswald styles for headlines
        headlineLarge: GoogleFonts.oswald(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: WBAIColors.white,
          letterSpacing: 0.5,
        ),
        headlineSmall: GoogleFonts.oswald(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: WBAIColors.white,
          letterSpacing: 0.5,
        ),
        titleLarge: GoogleFonts.oswald(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: WBAIColors.white,
          letterSpacing: 0.5,
        ),
        // Poppins styles for content
        titleMedium: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: WBAIColors.white,
        ),
        titleSmall: GoogleFonts.poppins(
          fontSize: 16,
          color: WBAIColors.lightGray,
        ),
        bodyLarge: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: WBAIColors.white,
        ),
        bodyMedium: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: WBAIColors.white,
        ),
        bodySmall: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: WBAIColors.lightGray,
        ),
        labelLarge: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: WBAIColors.white,
          letterSpacing: 0.5,
        ),
      ),
      iconTheme: const IconThemeData(
        color: WBAIColors.white,
        size: 32,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: WBAIColors.blue,
      ),
    );
  }
}
