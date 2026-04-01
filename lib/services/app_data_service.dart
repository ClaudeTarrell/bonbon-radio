import 'dart:convert';
import 'package:http/http.dart' as http;

class AppDataService {
  static Future<Map<String, dynamic>> fetchAppData() async {
    final url = Uri.parse('https://bonbonradio.net/app-data.json');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('App-Daten konnten nicht geladen werden');
    }
  }
}