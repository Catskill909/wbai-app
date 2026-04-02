
class PacificaItem {
  final String title;
  final String link;
  final String excerpt;
  final String content;
  final String? imageUrl;

  PacificaItem({
    required this.title,
    required this.link,
    required this.excerpt,
    required this.content,
    this.imageUrl,
  });

  factory PacificaItem.fromJson(Map<String, dynamic> json) {
    String? imageUrl;
    
    // Parse the featured media from _embedded data
    if (json['_embedded'] != null && 
        json['_embedded']['wp:featuredmedia'] != null && 
        json['_embedded']['wp:featuredmedia'].isNotEmpty) {
      final media = json['_embedded']['wp:featuredmedia'][0];
      imageUrl = media['media_details']?['sizes']?['medium']?['source_url'];
    }

    return PacificaItem(
      title: json['title']['rendered'] ?? '',
      link: json['link'] ?? '',
      excerpt: json['excerpt']['rendered'] ?? '',
      content: json['content']['rendered'] ?? '',
      imageUrl: imageUrl,
    );
  }

  @override
  String toString() {
    return 'PacificaItem(title: $title, link: $link, imageUrl: $imageUrl)';
  }
}
