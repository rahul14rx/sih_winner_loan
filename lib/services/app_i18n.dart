import 'package:flutter/foundation.dart';

class AppI18n {
  /// 'en' or 'hi'
  static final ValueNotifier<String> lang = ValueNotifier<String>('en');

  static void setLang(String code) {
    final next = (code == 'hi') ? 'hi' : 'en';
    if (lang.value != next) lang.value = next;
  }

  static bool get isHi => lang.value == 'hi';

  static String languageLabel(String code) {
    if (code == 'hi') return 'हिंदी';
    return 'English';
  }

  static String currentLanguageLabel() => languageLabel(lang.value);

  static String t(String key, {Map<String, String> params = const {}}) {
    final dict = _strings[lang.value] ?? _strings['en']!;
    var s = dict[key] ?? _strings['en']![key] ?? key;
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      // Common
      'language': 'Language',
      'english': 'English',
      'hindi': 'Hindi',
      'done': 'Done',
      'required': 'Required',
      'invalid_number': 'Invalid Number',

      // Nav
      'nav_home': 'Home',
      'nav_new_beneficiary': 'New Beneficiary',
      'nav_history': 'History',
      'nav_reports': 'Reports',
      'nav_profile': 'Profile',
      'nav_help': 'Help',

      // Login
      'app_title': 'NYAY SAHAYAK',
      'ministry': 'Ministry of Social Justice & Empowerment',
      'official_login': 'Official Login',
      'official_subtitle': 'Bank & Govt Officers',
      'beneficiary_login': 'Beneficiary Login',
      'beneficiary_subtitle': 'Citizens & Applicants',
      'secure_footer': 'Secure GovTech Platform',
      'officer_id': 'Officer ID',
      'password': 'Password',
      'secure_login_btn': 'Secure Login',
      'official_login_title': 'Official Login',
      'official_login_desc': 'Secure access for bank & government officers.',
      'mobile_number': 'Mobile Number',
      'send_otp': 'Send OTP',
      'verify_otp': 'Verify & Login',
      'enter_otp': 'Enter Verification Code',
      'otp_sent': 'We sent a code to',

      // Dashboard
      'search_reviews': 'Search reviews',
      'your_reviews': 'Your Reviews',
      'good_afternoon': 'Good afternoon, ',
      'recent_services': 'Recently Used Services',
      'pending_reviews': 'Pending Reviews',
      'pending': 'Pending',
      'verified': 'Verified',
      'rejected': 'Rejected',
      'all_caught_up': 'All caught up!',
      'no_pending_loans': 'No pending loans to review.',
      'couldnt_open_link': "Couldn't open link",
    },

    'hi': {
      // Common
      'language': 'भाषा',
      'english': 'English',
      'hindi': 'हिंदी',
      'done': 'ठीक है',
      'required': 'आवश्यक',
      'invalid_number': 'अमान्य नंबर',

      // Nav
      'nav_home': 'होम',
      'nav_new_beneficiary': 'नया लाभार्थी',
      'nav_history': 'इतिहास',
      'nav_reports': 'रिपोर्ट्स',
      'nav_profile': 'प्रोफ़ाइल',
      'nav_help': 'सहायता',

      // Login
      'app_title': 'न्याय सहायक',
      'ministry': 'सामाजिक न्याय और अधिकारिता मंत्रालय',
      'official_login': 'अधिकारी लॉगिन',
      'official_subtitle': 'बैंक व सरकारी अधिकारी',
      'beneficiary_login': 'लाभार्थी लॉगिन',
      'beneficiary_subtitle': 'नागरिक व आवेदक',
      'secure_footer': 'सुरक्षित GovTech प्लेटफॉर्म',
      'officer_id': 'अधिकारी आईडी',
      'password': 'पासवर्ड',
      'secure_login_btn': 'सुरक्षित लॉगिन',
      'official_login_title': 'अधिकारी लॉगिन',
      'official_login_desc': 'बैंक और सरकारी अधिकारियों के लिए सुरक्षित प्रवेश।',
      'mobile_number': 'मोबाइल नंबर',
      'send_otp': 'ओटीपी भेजें',
      'verify_otp': 'सत्यापित करें',
      'enter_otp': 'सत्यापन कोड दर्ज करें',
      'otp_sent': 'हमने कोड भेजा है',

      // Dashboard
      'search_reviews': 'समीक्षाएँ खोजें',
      'your_reviews': 'आपकी समीक्षाएँ',
      'good_afternoon': 'नमस्कार, ',
      'recent_services': 'हाल ही में उपयोग की गई सेवाएँ',
      'pending_reviews': 'लंबित समीक्षाएँ',
      'pending': 'लंबित',
      'verified': 'सत्यापित',
      'rejected': 'अस्वीकृत',
      'all_caught_up': 'सभी कार्य पूर्ण!',
      'no_pending_loans': 'समीक्षा के लिए कोई लंबित ऋण नहीं है।',
      'couldnt_open_link': 'लिंक नहीं खुल सका',
    },
  };
}
