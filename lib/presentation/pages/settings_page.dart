import 'package:flutter/material.dart';
import '../../core/constants/stream_constants.dart';
import '../theme/font_constants.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget _buildSettingHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.sectionTitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: AppTextStyles.drawerTitle,
        ),
      ),
      body: ListView(
        children: [
          _buildSettingHeader('Streaming'),
          ListTile(
            title: Text(
              'Stream Quality',
              style: AppTextStyles.bodyLarge,
            ),
            subtitle: Text(
              '128 kbps',
              style: AppTextStyles.bodySmall,
            ),
            leading: const Icon(Icons.high_quality),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Currently streaming at 128 kbps',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              );
            },
          ),
          const Divider(),
          SwitchListTile(
            title: Text(
              'Background Playback',
              style: AppTextStyles.bodyLarge,
            ),
            subtitle: Text(
              'Keep playing when app is in background',
              style: AppTextStyles.bodySmall,
            ),
            value: true, // Always true as this is a core feature
            onChanged: (_) {}, // No changes allowed
            secondary: const Icon(Icons.play_circle),
          ),
          const Divider(),
          _buildSettingHeader('Storage'),
          ListTile(
            title: Text(
              'Cache Management',
              style: AppTextStyles.bodyLarge,
            ),
            subtitle: Text(
              'Clear temporary files',
              style: AppTextStyles.bodySmall,
            ),
            leading: const Icon(Icons.cleaning_services),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Storage space optimization in progress',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              );
            },
          ),
          const Divider(),
          _buildSettingHeader('Information'),
          ListTile(
            title: Text(
              'About Station',
              style: AppTextStyles.bodyLarge,
            ),
            subtitle: Text(
              StreamConstants.stationName,
              style: AppTextStyles.bodySmall,
            ),
            leading: const Icon(Icons.info),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: StreamConstants.stationName,
                applicationVersion: '1.0.0',
                applicationLegalese: '©2024 ${StreamConstants.stationName}',
                children: [
                  const SizedBox(height: 16),
                  Text(
                    '${StreamConstants.stationName} - ${StreamConstants.stationSlogan}',
                    style: AppTextStyles.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Listen live at ${StreamConstants.streamUrl}',
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
