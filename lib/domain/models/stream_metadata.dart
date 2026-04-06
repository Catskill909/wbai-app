import 'dart:convert';
import 'package:equatable/equatable.dart';
import '../../core/utils/string_utils.dart';

class ShowInfo extends Equatable {
  final String showName;
  final String host;
  final String time;
  final String? songTitle;
  final String? songArtist;
  final String? hostImage;
  final String? description;

  const ShowInfo({
    required this.showName,
    required this.host,
    required this.time,
    this.songTitle,
    this.songArtist,
    this.hostImage,
    this.description,
  });

  factory ShowInfo.fromJson(Map<String, dynamic> json) {
    // Construct full image URL from big_pix filename
    // big_pix contains just the filename (e.g., "friedman_it_210.jpg")
    // We need to prepend the base URL from gl_pixurl
    String? imageUrl;
    final bigPix = json['big_pix'];
    if (bigPix != null && bigPix.toString().isNotEmpty) {
      // Use the base URL from the feed's global settings
      imageUrl = 'https://confessor.kpfk.org/pix/$bigPix';
    }

    return ShowInfo(
      showName: StringUtils.decodeHtmlEntities(json['sh_name'] ?? ''),
      host: StringUtils.decodeHtmlEntities(json['sh_djname'] ?? ''),
      time:
          '${json['cur_start'] ?? ''}${json['cur_end'] != null ? ' - ${json['cur_end']}' : ''}',
      songTitle: json['pl_song'] != null
          ? StringUtils.decodeHtmlEntities(json['pl_song'])
          : null,
      songArtist: json['pl_artist'] != null
          ? StringUtils.decodeHtmlEntities(json['pl_artist'])
          : null,
      hostImage: imageUrl,
      description: json['sh_desc'] != null
          ? StringUtils.decodeHtmlEntities(json['sh_desc'])
          : null,
    );
  }

  /// Returns true if this show has song information
  bool get hasSongInfo =>
      songTitle != null &&
      songTitle!.isNotEmpty &&
      songArtist != null &&
      songArtist!.isNotEmpty;

  /// Returns true if there is a host image available
  bool get hasHostImage => hostImage != null && hostImage!.isNotEmpty;

  @override
  List<Object?> get props =>
      [showName, host, time, songTitle, songArtist, hostImage, description];

  @override
  String toString() {
    return 'ShowInfo(name: $showName, time: $time${hasSongInfo ? ', song: $songTitle by $songArtist' : ''})';
  }
}

class StreamMetadata extends Equatable {
  final ShowInfo previous;
  final ShowInfo current;
  final ShowInfo next;
  final String? stationFallbackImage;

  const StreamMetadata({
    required this.previous,
    required this.current,
    required this.next,
    this.stationFallbackImage,
  });

  factory StreamMetadata.fromJson(dynamic jsonData) {
    if (jsonData is String) {
      jsonData = json.decode(jsonData);
    }

    if (jsonData is! List || jsonData.length < 3) {
      throw FormatException('Invalid API response format');
    }

    final global = jsonData[0]['global'];
    final pixUrl = global?['gl_pixurl'] as String? ?? 'https://confessor.kpfk.org/pix';
    final stapixBig = global?['gl_stapix_big'] as String?;
    final fallback = stapixBig != null && stapixBig.isNotEmpty
        ? '$pixUrl/$stapixBig'
        : null;

    return StreamMetadata(
      previous: ShowInfo.fromJson({}), // We don't use previous show info
      current: ShowInfo.fromJson(jsonData[1]['current']),
      next: ShowInfo.fromJson(jsonData[2]['next']),
      stationFallbackImage: fallback,
    );
  }

  /// Returns true if the current show has song information
  bool get hasSongInfo =>
      current.songTitle != null &&
      current.songTitle!.isNotEmpty &&
      current.songArtist != null &&
      current.songArtist!.isNotEmpty;

  /// Returns true if there is a host image available
  bool get hasHostImage =>
      current.hostImage != null && current.hostImage!.isNotEmpty;

  @override
  List<Object?> get props => [previous, current, next, stationFallbackImage];

  @override
  String toString() {
    return 'StreamMetadata(current: $current, next: $next)';
  }
}
