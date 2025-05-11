import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user_model.dart';

class AuthService {
  // Register a new user
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String? address,
  }) async {
    final url = Uri.parse(ApiConfig.register);

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'address': address,
      }),
    );

    if (response.statusCode == 201) {
      final jsonResponse = jsonDecode(response.body);
      final authResponse = AuthResponse.fromJson(jsonResponse['data']);

      // Save tokens to secure storage
      await _saveTokens(authResponse.tokens);

      return authResponse;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to register');
    }
  }

  // Login user
  Future<AuthResponse> login(String email, String password) async {
    final url = Uri.parse(ApiConfig.login);

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final authResponse = AuthResponse.fromJson(jsonResponse['data']);

      // Save tokens to secure storage
      await _saveTokens(authResponse.tokens);

      return authResponse;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to login');
    }
  }

  // Save authentication tokens
  Future<void> _saveTokens(AuthTokens tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accessToken', tokens.accessToken);
    await prefs.setString('refreshToken', tokens.refreshToken);
  }

  // Get current access token
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('accessToken');
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null;
  }

  // Logout user
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
  }
}
