import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  // Since you are running on Chrome, we use 'localhost' to connect to the server
  // running on the same machine.
  final String _baseUrl = "http://localhost:5000";

  Future<void> startDelivery() async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/start-delivery'));
      if (response.statusCode != 200) {
        throw Exception('Failed to start delivery process.');
      }
      print('API: Delivery process started successfully.');
    } catch (e) {
      print('API ERROR on startDelivery: $e');
      rethrow;
    }
  }

  Future<String> checkStatus() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/check-status'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status']; // e.g., 'waiting_for_otp' or 'otp_ready'
      } else {
        throw Exception('Failed to check status.');
      }
    } catch (e) {
      print('API ERROR on checkStatus: $e');
      rethrow;
    }
  }

  Future<String> getSpokenOtp() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/speak-otp'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['spoken_otp']; // e.g., "1... 2... 3... 4..."
      } else {
        throw Exception('Failed to get OTP.');
      }
    } catch (e) {
      print('API ERROR on getSpokenOtp: $e');
      rethrow;
    }
  }
  
  Future<void> cancelDelivery() async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/cancel-delivery'));
      if (response.statusCode != 200) {
        throw Exception('Failed to cancel delivery.');
      }
      print('API: Delivery cancelled successfully.');
    } catch (e) {
      print('API ERROR on cancelDelivery: $e');
      rethrow;
    }
  }
}