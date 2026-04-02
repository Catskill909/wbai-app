import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/stream_constants.dart';
import '../theme/font_constants.dart';

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

  Widget _buildSocialIcons(BuildContext context) {
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
            icon: Icon(Icons.facebook, size: iconSize, color: Colors.black),
            tooltip: 'Facebook',
            onPressed: () => _launchUrl(StreamConstants.facebookUrl),
          ),
          IconButton(
            icon: Icon(Icons.camera_alt, size: iconSize, color: Colors.black),
            tooltip: 'Instagram',
            onPressed: () => _launchUrl(StreamConstants.instagramUrl),
          ),
IconButton(
            icon: Icon(Icons.message, size: iconSize, color: Colors.black),
            tooltip: 'Twitter',
            onPressed: () => _launchUrl(StreamConstants.twitterUrl),
          ),
          IconButton(
            icon: Icon(Icons.email, size: iconSize, color: Colors.black),
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
    final headerPadding =
        isSmallPhone ? 4.0 : 16.0; // Much smaller padding for small devices
    final iconSize = isSmallPhone ? 20.0 : 28.0;
    final listTileHorizontalPadding = isSmallPhone ? 12.0 : 24.0;
    final listTileVerticalPadding =
        isSmallPhone ? 1.0 : 2.0; // Drastically reduce vertical spacing

    return Drawer(
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
              height: isSmallPhone
                  ? 60.0
                  : null, // Even smaller header for small devices
              decoration: const BoxDecoration(
                color: Colors.white,
              ),
              child: isSmallPhone
                  ? Center(
                      child: Image.asset(
                        'assets/images/header.png',
                        fit: BoxFit.contain,
                        height: 40.0, // Much smaller image for small devices
                      ),
                    )
                  : DrawerHeader(
                      decoration: const BoxDecoration(
                        color: Colors.white,
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
                      leading: Icon(Icons.home, size: iconSize, color: Colors.black),
                      title: Text(
                        'Home',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
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
                      leading: Icon(Icons.calendar_month, size: iconSize, color: Colors.black),
                      title: Text(
                        'Program Schedule',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
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
                      leading: Icon(Icons.music_note, size: iconSize, color: Colors.black),
                      title: Text(
                        'Playlist Archive',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: listTileHorizontalPadding,
                          vertical: listTileVerticalPadding),
                      onTap: () {
                        Navigator.pop(context);
                        _launchUrl(StreamConstants.playlistUrl);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.radio, size: iconSize, color: Colors.black),
                      title: Text(
                        'Show Archive',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
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
                      leading: Icon(Icons.attach_money, size: iconSize, color: Colors.black),
                      title: Text(
                        'Donate',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
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
                      leading: Icon(Icons.language, size: iconSize, color: Colors.black),
                      title: Text(
                        'WBAI Website',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
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
                      leading: Icon(Icons.info, size: iconSize, color: Colors.black),
                      title: Text(
                        'About Pacifica',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
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
                      leading: Icon(Icons.privacy_tip, size: iconSize, color: Colors.black),
                      title: Text(
                        'Privacy Policy',
                        style: AppTextStyles.drawerMenuItemForDevice(size)
                            .copyWith(
                          fontSize: isSmallPhone
                              ? 13.0
                              : 18.0, // Even smaller font for small devices
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
              color: Colors.white,
              child: Column(
                children: [
                  const Divider(height: 1, color: Colors.black26),
                  _buildSocialIcons(context),
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
