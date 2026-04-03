class NewsArticle {
  final String title;
  final String date;
  final String author;
  final String category;
  final String? imageUrl;
  final String articleUrl;

  const NewsArticle({
    required this.title,
    required this.date,
    required this.author,
    required this.category,
    required this.articleUrl,
    this.imageUrl,
  });
}
