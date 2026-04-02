import 'package:flutter/material.dart';
import '../theme/font_constants.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/repositories/affiliate_repository.dart';
import '../../domain/models/affiliate_station.dart';

class AffiliateButtonsSection extends StatelessWidget {
  const AffiliateButtonsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AffiliateStation>>(
      future: AffiliateRepository().fetchAffiliates(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        } else if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Failed to load affiliates', style: TextStyle(color: Colors.red))));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final affiliates = snapshot.data!;
        
        // Determine column count based on screen width (same logic as main grid)
        final width = MediaQuery.of(context).size.width;
        final isTablet = width > 600;
        final isSmallDevice = width < 380; // Small device detection for this page only
        final crossAxisCount = isTablet ? 4 : 2;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
              child: Text(
                'Pacifica Network Affiliates',
                style: AppTextStyles.showTitle.copyWith(
                  fontSize: 20,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: affiliates.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                // Much taller cards for small devices (LOWER ratio = taller cards)
                childAspectRatio: isSmallDevice ? 1.8 : 2.2,
              ),
              itemBuilder: (context, i) {
                final affiliate = affiliates[i];
                return Card(
                  color: const Color(0xFF23252B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final url = Uri.parse(affiliate.link);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Padding(
                      // Adjust padding for small devices to prevent overflow
                      padding: EdgeInsets.symmetric(
                        vertical: isSmallDevice ? 8 : 12, 
                        horizontal: 12
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            affiliate.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: isSmallDevice ? 14 : 16, // Smaller font for small devices
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: isSmallDevice ? 2 : 4), // Less spacing for small devices
                          Text(
                            affiliate.description,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isSmallDevice ? 12 : 14, // Smaller font for small devices
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
