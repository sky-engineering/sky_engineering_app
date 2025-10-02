import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:developer' as developer;

const dropboxAppKey = String.fromEnvironment('DROPBOX_APP_KEY');
const dropboxRedirectUri = String.fromEnvironment('DROPBOX_REDIRECT_URI');

class DropboxAuthException implements Exception {
  DropboxAuthException(this.message, [this.code]);

  final String message;
  final String? code;

  @override
  String toString() =>
      'DropboxAuthException(code: \'$code\', message: $message)';
}

class DropboxAuth {
  DropboxAuth({FlutterSecureStorage? storage, http.Client? client})
    : _storage = storage ?? const FlutterSecureStorage(),
      _client = client ?? http.Client();

  static const _authorizeHost = 'www.dropbox.com';
  static const _authorizePath = '/oauth2/authorize';
  static const _tokenEndpoint = 'https://api.dropboxapi.com/oauth2/token';
  static const _accessTokenKey = 'dbx_access_token';
  static const _refreshTokenKey = 'dbx_refresh_token';
  static const _expiresAtKey = 'dbx_expires_at';
  static const _scopes =
      'account_info.read files.metadata.read files.content.read files.metadata.write files.content.write';
  static const _expiryBuffer = Duration(seconds: 60);
  static final _pkceRandom = Random.secure();

  final FlutterSecureStorage _storage;
  final http.Client _client;

  Future<String?> signIn() async {
    _ensureConfig();
    final redirect = Uri.parse(dropboxRedirectUri);

    final pkce = _generatePkcePair();
    final state = _randomString(40);

    final authorizeUri = Uri.https(_authorizeHost, _authorizePath, {
      'client_id': dropboxAppKey,
      'response_type': 'code',
      'redirect_uri': dropboxRedirectUri,
      'code_challenge': pkce.codeChallenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'scope': _scopes,
      'state': state,
    });

    late String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: authorizeUri.toString(),
        callbackUrlScheme: redirect.scheme,
      );
    } on Exception catch (e) {
      throw DropboxAuthException(
        'Authentication failed: ${e.toString()}',
        'auth_cancelled',
      );
    }

    final redirected = Uri.parse(result);
    final returnedState = redirected.queryParameters['state'];
    final authCode = redirected.queryParameters['code'];
    final error = redirected.queryParameters['error'];

    if (returnedState != state) {
      throw DropboxAuthException('State mismatch detected.', 'state_mismatch');
    }

    if (error != null || authCode == null) {
      throw DropboxAuthException(
        'Authorization failed: ${error ?? 'missing_code'}',
        error,
      );
    }

    final token = await _exchangeCodeForToken(
      code: authCode,
      codeVerifier: pkce.codeVerifier,
    );

    await _persistToken(token);
    return token.accessToken;
  }

  Future<String?> getValidAccessToken() async {
    final tokens = await _readStoredTokens();
    if (tokens == null) {
      return null;
    }

    if (!_needsRefresh(tokens)) {
      return tokens.accessToken;
    }

    if (tokens.refreshToken == null || tokens.refreshToken!.isEmpty) {
      developer.log(
        'Missing refresh token during refresh attempt',
        name: 'DropboxAuth',
      );
      return null;
    }

    final refreshed = await _refreshAccessToken(tokens.refreshToken!);
    await _persistToken(refreshed, fallbackRefreshToken: tokens.refreshToken);
    return refreshed.accessToken;
  }

  Future<void> signOut() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _expiresAtKey),
    ]);
  }

  Future<bool> isSignedIn() async {
    final refresh = await _storage.read(key: _refreshTokenKey);
    return refresh != null && refresh.isNotEmpty;
  }

  Future<_TokenResponse> _exchangeCodeForToken({
    required String code,
    required String codeVerifier,
  }) async {
    final response = await _client.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': dropboxRedirectUri,
        'code_verifier': codeVerifier,
        'client_id': dropboxAppKey,
      },
    );

    if (response.statusCode != 200) {
      throw DropboxAuthException(
        'Token exchange failed: ${response.body}',
        response.statusCode.toString(),
      );
    }

    return _parseTokenResponse(response.body);
  }

  Future<_TokenResponse> _refreshAccessToken(String refreshToken) async {
    final response = await _client.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': dropboxAppKey,
      },
    );

    if (response.statusCode == 200) {
      return _parseTokenResponse(
        response.body,
        fallbackRefreshToken: refreshToken,
      );
    }

    if (response.statusCode == 400 || response.statusCode == 401) {
      await signOut();
      throw DropboxAuthException(
        'Refresh token rejected: ${response.body}',
        response.statusCode.toString(),
      );
    }

    throw DropboxAuthException(
      'Token refresh failed: ${response.body}',
      response.statusCode.toString(),
    );
  }

  Future<void> _persistToken(
    _TokenResponse response, {
    String? fallbackRefreshToken,
  }) async {
    final expiresAt = DateTime.now().toUtc().add(
      Duration(seconds: response.expiresIn),
    );
    final refreshToken = response.refreshToken ?? fallbackRefreshToken;
    final tasks = <Future<void>>[
      _storage.write(key: _accessTokenKey, value: response.accessToken),
      _storage.write(key: _expiresAtKey, value: expiresAt.toIso8601String()),
    ];
    if (refreshToken != null && refreshToken.isNotEmpty) {
      tasks.add(_storage.write(key: _refreshTokenKey, value: refreshToken));
    }
    await Future.wait(tasks);
  }

  Future<_StoredToken?> _readStoredTokens() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    final expiresRaw = await _storage.read(key: _expiresAtKey);
    if (expiresRaw == null || expiresRaw.isEmpty) {
      return null;
    }

    DateTime expiresAt;
    try {
      expiresAt = DateTime.parse(expiresRaw).toUtc();
    } catch (_) {
      developer.log(
        'Failed to parse token expiration date',
        name: 'DropboxAuth',
      );
      return null;
    }

    final refreshToken = await _storage.read(key: _refreshTokenKey);
    return _StoredToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );
  }

  bool _needsRefresh(_StoredToken tokens) {
    final threshold = tokens.expiresAt.subtract(_expiryBuffer);
    return DateTime.now().toUtc().isAfter(threshold);
  }

  _PkcePair _generatePkcePair() {
    const verifierLength =
        128; // Spec allows 43-128 characters; using max length for entropy.
    final verifier = _randomString(verifierLength);
    final bytes = utf8.encode(verifier);
    final digest = crypto.sha256.convert(bytes);
    final challenge = _base64UrlNoPadding(Uint8List.fromList(digest.bytes));
    return _PkcePair(verifier, challenge);
  }

  String _randomString(int length, {bool includeSymbols = true}) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const symbols = '-._~';
    final chars = includeSymbols
        ? letters + numbers + symbols
        : letters + numbers;
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(chars[_pkceRandom.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  String _base64UrlNoPadding(Uint8List data) {
    return base64UrlEncode(data).replaceAll('=', '');
  }

  _TokenResponse _parseTokenResponse(
    String body, {
    String? fallbackRefreshToken,
  }) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      throw DropboxAuthException(
        'Invalid token response: $body',
        'invalid_json',
      );
    }

    final accessToken = decoded['access_token'] as String?;
    final expiresIn = (decoded['expires_in'] as num?)?.toInt();
    final refreshToken =
        (decoded['refresh_token'] as String?) ?? fallbackRefreshToken;

    if (accessToken == null || expiresIn == null) {
      throw DropboxAuthException(
        'Missing fields in token response: $body',
        'invalid_response',
      );
    }

    return _TokenResponse(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
    );
  }

  void _ensureConfig() {
    if (dropboxAppKey.isEmpty || dropboxRedirectUri.isEmpty) {
      throw DropboxAuthException(
        'Dropbox configuration missing. Ensure DROPBOX_APP_KEY and DROPBOX_REDIRECT_URI are set.',
        'missing_config',
      );
    }
  }
}

class _PkcePair {
  const _PkcePair(this.codeVerifier, this.codeChallenge);
  final String codeVerifier;
  final String codeChallenge;
}

class _TokenResponse {
  const _TokenResponse({
    required this.accessToken,
    this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String? refreshToken;
  final int expiresIn;
}

class _StoredToken {
  const _StoredToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
}
