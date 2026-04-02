import 'package:equatable/equatable.dart';
import '../../core/utils/string_utils.dart';

class StreamMetadata extends Equatable {
  final String currentShow;
  final String currentHost;
  final String currentTime;
  final String currentSong;
  final String artist;
  final String nextShow;
  final String nextHost;
  final String nextTime;
  final String? hostImageUrl;

  const StreamMetadata({
    this.currentShow = '',
    this.currentHost = '',
    this.currentTime = '',
    this.currentSong = '',
    this.artist = '',
    this.nextShow = '',
    this.nextHost = '',
    this.nextTime = '',
    this.hostImageUrl,
  });

  // Create from JSON response
  factory StreamMetadata.fromJson(List<dynamic> json) {
    final currentData = json[1]['current'] as Map<String, dynamic>;
    final nextData = json[2]['next'] as Map<String, dynamic>;

    return StreamMetadata(
      currentShow: StringUtils.decodeHtmlEntities(currentData['show_name'] ?? ''),
      currentHost: StringUtils.decodeHtmlEntities(currentData['host'] ?? ''),
      currentTime: currentData['time'] ?? '',
      currentSong: StringUtils.decodeHtmlEntities(currentData['pl_song'] ?? ''),
      artist: StringUtils.decodeHtmlEntities(currentData['pl_artist'] ?? ''),
      nextShow: StringUtils.decodeHtmlEntities(nextData['show_name'] ?? ''),
      nextHost: StringUtils.decodeHtmlEntities(nextData['host'] ?? ''),
      nextTime: nextData['time'] ?? '',
      hostImageUrl: currentData['host_pix'],
    );
  }

  // Empty metadata instance
  static const empty = StreamMetadata();

  // Copy with method for immutability
  StreamMetadata copyWith({
    String? currentShow,
    String? currentHost,
    String? currentTime,
    String? currentSong,
    String? artist,
    String? nextShow,
    String? nextHost,
    String? nextTime,
    String? hostImageUrl,
  }) {
    return StreamMetadata(
      currentShow: currentShow ?? this.currentShow,
      currentHost: currentHost ?? this.currentHost,
      currentTime: currentTime ?? this.currentTime,
      currentSong: currentSong ?? this.currentSong,
      artist: artist ?? this.artist,
      nextShow: nextShow ?? this.nextShow,
      nextHost: nextHost ?? this.nextHost,
      nextTime: nextTime ?? this.nextTime,
      hostImageUrl: hostImageUrl ?? this.hostImageUrl,
    );
  }

  @override
  List<Object?> get props => [
        currentShow,
        currentHost,
        currentTime,
        currentSong,
        artist,
        nextShow,
        nextHost,
        nextTime,
        hostImageUrl,
      ];
}
