import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/stream_constants.dart';
import '../../features/news/pages/news_page.dart';
import '../theme/app_theme.dart';
import '../theme/font_constants.dart';

const _blueskySvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 530">
  <path d="M135.72 44.03C202.216 93.951 273.74 195.17 300 249.49c26.262-54.316 97.782-155.54 164.28-205.46C512.26 8.009 590-19.862 590 68.825c0 17.712-10.155 148.79-16.111 170.07-20.703 73.984-96.144 92.854-163.25 81.433 117.3 19.964 147.14 86.092 82.697 152.22-122.39 125.59-175.91-31.511-189.63-71.766-2.514-7.38-3.69-10.832-3.708-7.896-.017-2.936-1.193.516-3.707 7.896-13.714 40.255-67.233 197.36-189.63 71.766-64.444-66.128-34.605-132.26 82.697-152.22-67.108 11.421-142.55-7.449-163.25-81.433C20.15 217.613 10 86.535 10 68.825c0-88.687 77.742-60.816 125.72-24.795z"/>
</svg>
''';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: StreamConstants.emailAddress,
    );
    if (!await launchUrl(emailLaunchUri)) {
      throw Exception('Could not launch email');
    }
  }

  Widget _buildSocialIcons(BuildContext context, Color iconColor) {
    final size = MediaQuery.of(context).size;
    final isSmallPhone = size.shortestSide < 380;
    final iconSize =
        isSmallPhone ? 20.0 : 28.0; // Smaller icons for small devices
    final horizontalPadding = isSmallPhone ? 12.0 : 24.0;
    final verticalPadding =
        isSmallPhone ? 6.0 : 16.0; // Much less vertical padding

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, vertical: verticalPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.facebook, size: iconSize, color: iconColor),
            tooltip: 'Facebook',
            onPressed: () => _launchUrl(StreamConstants.facebookUrl),
          ),
          IconButton(
            icon: Icon(Icons.camera_alt, size: iconSize, color: iconColor),
            tooltip: 'Instagram',
            onPressed: () => _launchUrl(StreamConstants.instagramUrl),
          ),
IconButton(
            icon: Icon(Icons.message, size: iconSize, color: iconColor),
            tooltip: 'Twitter',
            onPressed: () => _launchUrl(StreamConstants.twitterUrl),
          ),
          IconButton(
            icon: SvgPicture.string(
              _blueskySvg,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
            tooltip: 'Bluesky',
            onPressed: () => _launchUrl(StreamConstants.blueskyUrl),
          ),
          IconButton(
            icon: Icon(Icons.email, size: iconSize, color: iconColor),
            tooltip: 'Email Us',
            onPressed: _launchEmail,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallPhone = size.shortestSide < 380;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black;
    final headerBg = isDark ? Colors.black : Colors.white;
    final dividerColor = isDark ? Colors.white24 : Colors.black26;
    final headerPadding =
        isSmallPhone ? 4.0 : 16.0; // Much smaller padding for small devices
    final iconSize = isSmallPhone ? 20.0 : 28.0;
    final listTileHorizontalPadding = isSmallPhone ? 12.0 : 24.0;
    final listTileVerticalPadding =
        isSmallPhone ? 1.0 : 2.0; // Drastically reduce vertical spacing

    return Drawer(
      backgroundColor: isDark ? WBAIColors.trueBlack : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: const Color.fromARGB(1, 255, 255, 255),
              width: 1,
            ),
          ),
        ),
        child: Column(
          children: [
            Container(
              // Paint the header background edge-to-edge, including behind
              // the status bar, so the top strip is never transparent.
              decoration: BoxDecoration(
                color: headerBg,
              ),
              child: isSmallPhone
                  ? Padding(
                      // Push the logo below the status bar on small phones;
                      // the DrawerHeader branch handles this itself.
                      padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top),
                      child: SizedBox(
                        height: 60.0,
                        child: Center(
                          child: Image.asset(
                            'assets/images/header.png',
                            fit: BoxFit.contain,
                            height:
                                40.0, // Much smaller image for small devices
                          ),
                        ),
                      ),
                    )
                  : DrawerHeader(
                      decoration: BoxDecoration(
                        color: headerBg,
                      ),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(headerPadding),
                          child: Image.asset(
                            'assets/images/header.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.home, size: iconSize, color: iconColor),
                      title: Text(
                        'Home',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.article_outlined,
                          size: iconSize, color: iconColor),
                      title: Text(
                        'News',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone ? 13.0 : 18.0,
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, newsPageRoute());
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.calendar_month, size: iconSize, color: iconColor),
                      title: Text(
                        'Program Schedule',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        _launchUrl(StreamConstants.scheduleUrl);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.radio, size: iconSize, color: iconColor),
                      title: Text(
                        'Show Archive',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        _launchUrl(StreamConstants.showArchiveUrl);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.attach_money, size: iconSize, color: iconColor),
                      title: Text(
                        'Donate',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        _launchUrl(StreamConstants.donateUrl);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.language, size: iconSize, color: iconColor),
                      title: Text(
                        'WBAI Website',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        _launchUrl(StreamConstants.aboutUrl);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.info, size: iconSize, color: iconColor),
                      title: Text(
                        'About Pacifica',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        _launchUrl(StreamConstants.pacificaUrl);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.privacy_tip, size: iconSize, color: iconColor),
                      title: Text(
                        'Privacy Policy',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                          color: iconColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        _launchUrl(StreamConstants.privacyPolicyUrl);
                      },
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: headerBg,
              child: Column(
                children: [
                  Divider(height: 1, color: dividerColor),
                  _buildSocialIcons(context, iconColor),
                  SizedBox(
                      height: isSmallPhone
                          ? 4.0
                          : 16.0), // Minimal bottom padding for small devices
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
