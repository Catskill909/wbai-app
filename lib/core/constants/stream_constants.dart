class StreamConstants {
  // Live stream URL
  static const String streamUrl = 'https://streaming.wbai.org/wbai_verizon';

  // Legacy URLs kept for reference (no longer used for streaming)
  static const String legacyBaseUrl = 'https://streams.pacifica.org:9000';
  static const String legacyStreamUrl =
      'https://streams.pacifica.org:9000/wbai_128';

  static const String metadataUrl = 'http://localhost:8000/proxy.php';
  static const String proxyUrl = 'http://localhost:8000/proxy.php';
  static const String hostImageUrl = 'https://www.wbai.org/';

  // Audio Configuration
  static const int defaultBufferSize = 20; // seconds
  static const int preBufferSize = 5; // seconds
  static const int metadataRefreshInterval = 30; // seconds
  static const int metadataCacheDuration = 300; // seconds (5 minutes)

  // Notification Configuration
  static const String notificationChannelId = 'com.wbaifm.radio.audio';
  static const String notificationChannelName = 'WBAI Radio';
  static const bool notificationOngoing = true;

  // Station Information
  static const String stationName = 'WBAI';
  static const String stationSlogan = 'Pacifica Radio';
  static const String stationWebsite = 'https://www.wbai.org';
  static const String stationLogo = 'https://www.wbai.org/wp-content/uploads/2020/01/wbai-logo.png';

  // Menu URLs
  static const String scheduleUrl = 'https://www.wbai.org/schedule/';
  static const String playlistUrl = 'https://www.wbai.org/playlist/';
  static const String showArchiveUrl = 'https://www.wbai.org/archive/';
  static const String donateUrl = 'https://www.wbai.org/donate/';
  static const String aboutUrl = 'https://www.wbai.org/about/';
  static const String pacificaUrl =
      'https://pacificanetwork.org/about-pacifica-foundation/pacifica-foundation/';
  static const String privacyPolicyUrl = 'https://www.wbai.org/privacy/';

  // Social Media URLs — update with confirmed WBAI handles
  static const String facebookUrl = 'https://www.facebook.com/wbai/';
  static const String twitterUrl = 'https://x.com/wbai/';
  static const String instagramUrl = 'https://www.instagram.com/wbai/';
  static const String youtubeUrl = 'https://www.youtube.com/@wbai/videos/';
  static const String emailAddress = 'gm@wbai.org';

  // Error Messages
  static const String connectionError =
      'Connection lost. Attempting to reconnect...';
  static const String bufferError = 'Buffering... Please wait.';
  static const String playbackError = 'Playback error. Retrying...';
  static const String metadataError = 'Unable to fetch station information';
}
