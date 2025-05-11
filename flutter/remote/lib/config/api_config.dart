class ApiConfig {
  // Base URL for API endpoints
  static const String baseUrl = 'http://localhost:3000/api/v1'; // Change this to your actual API URL
  
  // Auth endpoints
  static const String register = '$baseUrl/auth/register';
  static const String login = '$baseUrl/auth/login';
  static const String refreshToken = '$baseUrl/auth/refresh-token';
  static const String logout = '$baseUrl/auth/logout';
} 