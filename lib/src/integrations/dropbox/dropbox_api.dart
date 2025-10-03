import 'dart:convert';
import 'dart:typed_data';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'dropbox_auth.dart';

class DbxEntry {
  const DbxEntry({
    required this.id,
    required this.name,
    required this.pathLower,
    required this.pathDisplay,
    required this.isFolder,
    this.size,
  });

  final String id;
  final String name;
  final String pathLower;
  final String pathDisplay;
  final bool isFolder;
  final int? size;
}

class DropboxApi {
  DropboxApi(this._auth, {http.Client? client})
    : _client = client ?? http.Client();

  static const _apiBase = 'https://api.dropboxapi.com/2';
  static const _contentBase = 'https://content.dropboxapi.com/2';

  final DropboxAuth _auth;
  final http.Client _client;

  Future<List<DbxEntry>> listFolder({String path = ''}) async {
    final token = await _ensureToken();
    final entries = <DbxEntry>[];
    String? cursor;

    Map<String, dynamic> body = {
      'path': path,
      'recursive': false,
      'include_deleted': false,
      'limit': 200,
    };

    Map<String, dynamic> responseJson;
    bool hasMore;
    do {
      if (cursor == null) {
        responseJson = await _postApi(
          '/files/list_folder',
          token: token,
          body: body,
          operation: 'list_folder',
        );
      } else {
        responseJson = await _postApi(
          '/files/list_folder/continue',
          token: token,
          body: {'cursor': cursor},
          operation: 'list_folder/continue',
        );
      }

      final List<dynamic> respEntries =
          responseJson['entries'] as List<dynamic>? ?? const [];
      for (final item in respEntries) {
        final map = item as Map<String, dynamic>;
        final tag = map['.tag'] as String?;
        entries.add(
          DbxEntry(
            id: map['id'] as String? ?? '',
            name: map['name'] as String? ?? '',
            pathLower: map['path_lower'] as String? ?? '',
            pathDisplay: map['path_display'] as String? ?? '',
            isFolder: tag == 'folder',
            size: tag == 'file' ? (map['size'] as num?)?.toInt() : null,
          ),
        );
      }

      hasMore = responseJson['has_more'] as bool? ?? false;
      cursor = responseJson['cursor'] as String?;
    } while (hasMore && cursor != null);

    return entries;
  }

  Future<Uint8List> download(String path) async {
    final token = await _ensureToken();
    final uri = Uri.parse('$_contentBase/files/download');
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({'path': path}),
        'Content-Type': 'application/octet-stream',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Dropbox download failed: ${response.statusCode} ${response.body}',
      );
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  Future<void> upload({required String path, required Uint8List bytes}) async {
    final token = await _ensureToken();
    final uri = Uri.parse('$_contentBase/files/upload');
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({
          'path': path,
          'mode': 'add',
          'autorename': true,
          'mute': false,
          'strict_conflict': false,
        }),
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Dropbox upload failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> deletePath(String path) async {
    final token = await _ensureToken();
    await _postApi(
      '/files/delete_v2',
      token: token,
      body: {'path': path},
      operation: 'delete_v2',
    );
  }

  Future<void> createFolder(String path) async {
    final token = await _ensureToken();
    await _postApi(
      '/files/create_folder_v2',
      token: token,
      body: {'path': path, 'autorename': true},
      operation: 'create_folder_v2',
    );
  }

  Future<Uri> getTemporaryLink(String path) async {
    final token = await _ensureToken();
    final json = await _postApi(
      '/files/get_temporary_link',
      token: token,
      body: {'path': path},
      operation: 'get_temporary_link',
    );
    final link = json['link'] as String?;
    if (link == null || link.isEmpty) {
      throw Exception('Dropbox get_temporary_link failed: missing link');
    }
    return Uri.parse(link);
  }

  Future<Map<String, dynamic>> _postApi(
    String path, {
    required String token,
    required Map<String, dynamic> body,
    required String operation,
  }) async {
    final uri = Uri.parse('$_apiBase$path');
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Dropbox $operation failed: ${response.statusCode} ${response.body}',
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      developer.log(
        'Failed parsing Dropbox response',
        error: e,
        stackTrace: stackTrace,
        name: 'DropboxApi',
      );
      throw Exception('Dropbox $operation failed: invalid JSON response');
    }
  }

  Future<String> _ensureToken() async {
    final token = await _auth.getValidAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Dropbox authentication required');
    }
    return token;
  }
}
