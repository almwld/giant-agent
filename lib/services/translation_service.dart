import 'package:translator/translator.dart';

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();
  
  final GoogleTranslator _translator = GoogleTranslator();
  
  Future<String> translate(String text, {String from = 'auto', String to = 'en'}) async {
    try {
      final translation = await _translator.translate(text, from: from, to: to);
      return translation.text;
    } catch (e) {
      return text;
    }
  }
  
  Future<String> translateToArabic(String text) async {
    return await translate(text, to: 'ar');
  }
  
  Future<String> translateToEnglish(String text) async {
    return await translate(text, to: 'en');
  }
}
