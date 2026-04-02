import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Defines the text styles used throughout the app using Google Fonts
class AppTextStyles {
  /// Helper method to detect small phones that need aggressive scaling
  static bool _isSmallPhone(Size size) {
    return size.shortestSide < 380; // Targets phones smaller than iPhone XR
  }
  /// Headline styles using Oswald font
  static TextStyle get drawerTitle => GoogleFonts.oswald(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 0.5,
      );

  static TextStyle get showTitle => GoogleFonts.oswald(
        fontSize: 28, // Base size for phones
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 0.5,
        height: 1.08, // Slightly more spacing to eliminate overlap
        decoration: TextDecoration.none,
      );
      
  /// Show title with responsive sizing for tablets and small phones
  static TextStyle showTitleForDevice(Size size) => GoogleFonts.oswald(
        fontSize: _isSmallPhone(size) ? 20.0 : (size.shortestSide > 600 ? 36.0 : 28.0),
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 0.5,
        height: 1.08,
        decoration: TextDecoration.none,
      );

  static TextStyle get sectionTitle => GoogleFonts.oswald(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        letterSpacing: 0.5,
      );

  /// Drawer menu item style using Oswald
  static TextStyle get drawerMenuItem => GoogleFonts.oswald(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: Colors.white,
        letterSpacing: 0.5,
      );

  /// Drawer menu item with responsive sizing for tablets and small phones
  static TextStyle drawerMenuItemForDevice(Size size) => GoogleFonts.oswald(
        fontSize: _isSmallPhone(size) ? 13.0 : (size.shortestSide > 600 ? 20.0 : 16.0),
        fontWeight: FontWeight.w400,
        color: Colors.white,
        letterSpacing: 0.5,
      );

  /// Body text styles using Poppins font
  static TextStyle get showTime => GoogleFonts.poppins(
        fontSize: 16, // Base size for phones
        fontWeight: FontWeight.w500,
        color: Colors.white,
      );
      
  /// Show time with responsive sizing for tablets and small phones
  static TextStyle showTimeForDevice(Size size) => GoogleFonts.poppins(
        fontSize: _isSmallPhone(size) ? 13.0 : (size.shortestSide > 600 ? 20.0 : 16.0),
        fontWeight: FontWeight.w500,
        color: Colors.white,
      );

  static TextStyle get bodyLarge => GoogleFonts.poppins(
        fontSize: 16, // Base size for phones
        fontWeight: FontWeight.normal,
        color: Colors.white,
      );
      
  /// Body large with responsive sizing for tablets and small phones
  static TextStyle bodyLargeForDevice(Size size) => GoogleFonts.poppins(
        fontSize: _isSmallPhone(size) ? 13.0 : (size.shortestSide > 600 ? 20.0 : 16.0),
        fontWeight: FontWeight.normal,
        color: Colors.white,
      );

  static TextStyle get bodyMedium => GoogleFonts.poppins(
        fontSize: 14, // Base size for phones
        fontWeight: FontWeight.normal,
        color: Colors.white,
        decoration: TextDecoration.none,
      );
      
  /// Body medium with responsive sizing for tablets and small phones
  static TextStyle bodyMediumForDevice(Size size) => GoogleFonts.poppins(
        fontSize: _isSmallPhone(size) ? 12.0 : (size.shortestSide > 600 ? 18.0 : 14.0),
        fontWeight: FontWeight.normal,
        color: Colors.white,
        decoration: TextDecoration.none,
      );

  static TextStyle get bodySmall => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: Colors.white70,
      );

  static TextStyle get button => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        letterSpacing: 0.5,
      );
}
