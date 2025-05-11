import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quan_ly_giao_thong/models/user.dart';
import 'package:quan_ly_giao_thong/config/app_config.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // User state
  User? _currentUser;
  User? get currentUser => _currentUser;

  // Token state
  AuthTokens? _tokens;
  String? get accessToken => _tokens?.accessToken;
  String? get refreshToken => _tokens?.refreshToken;

  // Stream controller for auth state changes
  final _authStateController = StreamController<User?>.broadcast();
  Stream<User?> get authStateStream => _authStateController.stream;

  // Check if user is logged in
  bool get isLoggedIn => _currentUser != null && _tokens != null;

  // HTTP client
  final _client = http.Client();

  // Storage keys
  static const _userKey = 'auth_user';
  static const _tokensKey = 'auth_tokens';

  // Log HTTP request and response
  void _logRequest(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) {
    if (kDebugMode) {
      print('🌐 HTTP $method: $url');
      print('📤 Headers: $headers');
      if (body != null) {
        print('📤 Body: $body');
      }
    }
  }

  void _logResponse(http.Response response) {
    if (kDebugMode) {
      print('📥 Status: ${response.statusCode}');
      print('📥 Headers: ${response.headers}');
      print('📥 Body: ${response.body}');
    }
  }

  // Check if the API server is reachable
  Future<bool> checkApiConnection() async {
    try {
      // Instead of checking a health endpoint, check the base URL
      _logRequest('GET', Uri.parse(AppConfig.SERVER_URL), {}, null);

      final response = await _client
          .get(
            Uri.parse(AppConfig.SERVER_URL),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      _logResponse(response);

      // Consider any response as successful connection
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('API connection check failed: $e');
      }
      return false;
    }
  }

  // Initialize auth state from local storage
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      final tokensJson = prefs.getString(_tokensKey);

      if (userJson != null && tokensJson != null) {
        _currentUser = User.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
        _tokens = AuthTokens.fromJson(
          jsonDecode(tokensJson) as Map<String, dynamic>,
        );
        _authStateController.add(_currentUser);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing auth state: $e');
      }
      await logout();
    }
  }

  // Register a new user
  Future<User> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      // Check API connectivity first
      final isConnected = await checkApiConnection();
      if (!isConnected) {
        throw Exception(
          'Cannot connect to the API server. Please check your internet connection and try again.',
        );
      }

      final url = Uri.parse('${AppConfig.SERVER_URL}/api/auth/register');
      final body = jsonEncode({
        'email': email,
        'password': password,
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'address': address,
      });

      _logRequest('POST', url, {'Content-Type': 'application/json'}, body);

      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      _logResponse(response);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final data = responseData['data'];

        // Check if the response structure is as expected
        if (data == null) {
          throw Exception('Server returned null response data');
        }

        if (data['user'] == null) {
          throw Exception('Response missing user data');
        }

        if (data['tokens'] == null) {
          throw Exception('Response missing tokens data');
        }

        // Save user and tokens with safe casting
        final userData = data['user'];
        final tokensData = data['tokens'];

        if (userData is! Map<String, dynamic>) {
          throw Exception('User data is not in the expected format');
        }

        if (tokensData is! Map<String, dynamic>) {
          throw Exception('Tokens data is not in the expected format');
        }

        _currentUser = User.fromJson(userData);
        _tokens = AuthTokens.fromJson(tokensData);

        // Save to local storage
        await _saveToStorage();

        // Notify listeners
        _authStateController.add(_currentUser);

        return _currentUser!;
      } else {
        String errorMessage = 'Registration failed';
        try {
          final error = jsonDecode(response.body);
          errorMessage = error['message'] ?? errorMessage;
        } catch (e) {
          // If error response is not valid JSON
          errorMessage = 'Registration failed: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Registration error: $e');
      }
      rethrow;
    }
  }

  // Login with email and password
  Future<User> login(String email, String password) async {
    try {
      // Check API connectivity first
      final isConnected = await checkApiConnection();
      if (!isConnected) {
        throw Exception(
          'Cannot connect to the API server. Please check your internet connection and try again.',
        );
      }

      final url = Uri.parse('${AppConfig.SERVER_URL}/api/auth/login');
      final body = jsonEncode({'email': email, 'password': password});

      _logRequest('POST', url, {'Content-Type': 'application/json'}, body);

      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      _logResponse(response);

      if (response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          final data = responseData['data'];

          // Check if the response structure is as expected
          if (data == null) {
            throw Exception('Server returned null response data');
          }

          if (data['user'] == null) {
            throw Exception('Response missing user data');
          }

          if (data['tokens'] == null) {
            throw Exception('Response missing tokens data');
          }

          // Save user and tokens with safe casting
          final userData = data['user'];
          final tokensData = data['tokens'];

          if (userData is! Map<String, dynamic>) {
            throw Exception('User data is not in the expected format');
          }

          if (tokensData is! Map<String, dynamic>) {
            throw Exception('Tokens data is not in the expected format');
          }

          // Create user object with proper null checks for all fields
          _currentUser = User.fromJson(userData);
          _tokens = AuthTokens.fromJson(tokensData);

          // Save to local storage
          await _saveToStorage();

          // Notify listeners
          _authStateController.add(_currentUser);

          return _currentUser!;
        } catch (e) {
          if (kDebugMode) {
            print('Login error: $e');
            // Print more detailed data about the response structure
            try {
              final responseData = jsonDecode(response.body);
              print('Response structure: $responseData');
              if (responseData.containsKey('data')) {
                final data = responseData['data'];
                print('Data structure: $data');
                if (data.containsKey('user')) {
                  print('User data: ${data['user']}');
                }
              }
            } catch (jsonError) {
              print('Could not parse response JSON: $jsonError');
            }
          }
          rethrow;
        }
      } else {
        String errorMessage = 'Login failed';
        try {
          final error = jsonDecode(response.body);
          errorMessage = error['message'] ?? errorMessage;
        } catch (e) {
          // If error response is not valid JSON
          errorMessage = 'Login failed: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Login error: $e');
      }
      rethrow;
    }
  }

  // Refresh access token
  Future<bool> refreshTokens() async {
    if (_currentUser == null || _tokens == null) {
      return false;
    }

    try {
      final response = await _client.post(
        Uri.parse('${AppConfig.SERVER_URL}/api/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _currentUser!.id,
          'refreshToken': _tokens!.refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Update tokens
        _tokens = AuthTokens.fromJson(data as Map<String, dynamic>);

        // Save to local storage
        await _saveToStorage();

        return true;
      } else {
        // If refresh token fails, log the user out
        await logout();
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Token refresh error: $e');
      }
      await logout();
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    if (_currentUser != null && _tokens != null) {
      try {
        // Call server logout endpoint
        await _client.post(
          Uri.parse('${AppConfig.SERVER_URL}/api/auth/logout'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_tokens!.accessToken}',
          },
          body: jsonEncode({'userId': _currentUser!.id}),
        );
      } catch (e) {
        if (kDebugMode) {
          print('Logout error: $e');
        }
      }
    }

    // Clear local state regardless of server response
    _currentUser = null;
    _tokens = null;

    // Clear from local storage
    await _clearStorage();

    // Notify listeners
    _authStateController.add(null);
  }

  // Helper to save auth state to local storage
  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser != null) {
      await prefs.setString(_userKey, jsonEncode(_currentUser!.toJson()));
    }

    if (_tokens != null) {
      await prefs.setString(_tokensKey, jsonEncode(_tokens!.toJson()));
    }
  }

  // Helper to clear auth state from local storage
  Future<void> _clearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokensKey);
  }

  // Get authorized HTTP headers
  Map<String, String> get authHeaders {
    return {
      'Content-Type': 'application/json',
      if (_tokens != null) 'Authorization': 'Bearer ${_tokens!.accessToken}',
    };
  }

  // Make authenticated request with token refresh
  Future<http.Response> authenticatedRequest(
    Future<http.Response> Function() requestFunction,
  ) async {
    try {
      // Make the initial request
      final response = await requestFunction();

      // If unauthorized, try to refresh token and retry
      if (response.statusCode == 401) {
        final refreshed = await refreshTokens();
        if (refreshed) {
          // Retry the request with new token
          return await requestFunction();
        } else {
          throw Exception('Authentication failed');
        }
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Dispose resources
  void dispose() {
    _authStateController.close();
    _client.close();
  }
}
