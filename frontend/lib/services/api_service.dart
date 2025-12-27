import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  final String _baseUrl = "http://localhost:5000";

  // Calls the Gemini backend to understand speech
  Future<Map<String, dynamic>> understandSpeech(String rawText) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/understand-speech'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: json.encode({
          'raw_text': rawText,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'ok') {
          // The server returns JSON *as a string*,
          // so we need to parse it again. This is a "double parse".
          final extractedJson = data['extracted_json'];
          return json.decode(extractedJson) as Map<String, dynamic>;
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('Failed to process speech.');
      }
    } catch (e) {
      print('API ERROR on understandSpeech: $e');
      rethrow;
    }
  }

  // startDelivery is unchanged
  Future<void> startDelivery(String company, String info) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/start-delivery'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: json.encode({
          'company': company,
          'info': info,
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to start delivery process.');
      }
      print('API: Delivery process started successfully.');
    } catch (e) {
      print('API ERROR on startDelivery: $e');
      rethrow;
    }
  }

  // Unchanged Functions
  Future<String> checkStatus() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/check-status'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'];
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
        return data['spoken_otp'];
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