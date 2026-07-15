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
    // WBAI's feed provides sh_photo as a full URL; big_pix (a bare filename
    // needing the pix base URL prepended) only exists on some Confessor feeds.
    String? imageUrl;
    final shPhoto = json['sh_photo'];
    final bigPix = json['big_pix'];
    if (shPhoto != null && shPhoto.toString().isNotEmpty) {
      imageUrl = shPhoto.toString();
    } else if (bigPix != null && bigPix.toString().isNotEmpty) {
      imageUrl = 'https://confessor2.wbai.org/pix/$bigPix';
    }

    // The feed names the time fields cur_start/cur_end on the current show
    // but nxt_start/nxt_end on the next show.
    final start = json['cur_start'] ?? json['nxt_start'];
    final end = json['cur_end'] ?? json['nxt_end'];

    return ShowInfo(
      showName: StringUtils.decodeHtmlEntities(json['sh_name'] ?? ''),
      host: StringUtils.decodeHtmlEntities(json['sh_djname'] ?? ''),
      time: '${start ?? ''}${end != null ? ' - $end' : ''}',
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
    final pixUrl =
        global?['gl_pixurl'] as String? ?? 'https://confessor2.wbai.org/pix';
    // WBAI's feed only has gl_stapix ("WBAI.png"); gl_stapix_big is not present.
    final stapix =
        (global?['gl_stapix_big'] as String?) ?? (global?['gl_stapix'] as String?);
    final fallback =
        stapix != null && stapix.isNotEmpty ? '$pixUrl/$stapix' : null;

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
