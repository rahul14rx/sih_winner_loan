import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class EncryptionService {
  static final _storage = const FlutterSecureStorage();
  static const _keyName = 'aes_gcm_key';
  static enc.Key? _key;

  /// Initialize the encryption key.
  static Future<void> init() async {
    if (_key != null) return;

    try {
      String? keyBase64 = await _storage.read(key: _keyName);

      if (keyBase64 == null) {
        print("🔐 Generating new secure encryption key...");
        final newKey = enc.Key.fromSecureRandom(32);
        keyBase64 = newKey.base64;
        await _storage.write(key: _keyName, value: keyBase64);
        _key = newKey;
      } else {
        _key = enc.Key.fromBase64(keyBase64);
      }
    } catch (e) {
      print("❌ Error initializing encryption key: $e");
      rethrow;
    }
  }

  /// Encrypts a file and returns the encrypted File object.
  /// Appends '_enc' to the filename.
  static Future<File> encryptFile(File sourceFile) async {
    if (_key == null) await init();

    final fileBytes = await sourceFile.readAsBytes();
    
    // Generate a random IV (Initialization Vector) - 12 bytes for GCM
    final iv = enc.IV.fromSecureRandom(12);
    
    final encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.gcm));

    // Encrypt
    final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);

    // Combine IV + Encrypted Data (Prepending IV)
    final combined = Uint8List.fromList(iv.bytes + encrypted.bytes);

    final dir = sourceFile.parent;
    final name = p.basenameWithoutExtension(sourceFile.path);
    final ext = p.extension(sourceFile.path);
    final destPath = p.join(dir.path, '${name}_enc$ext');

    final encryptedFile = File(destPath);
    await encryptedFile.writeAsBytes(combined);

    print("🔒 Encrypted file saved: $destPath");
    return encryptedFile;
  }

  /// Decrypts a file and returns the raw bytes.
  static Future<Uint8List> decryptFileToBytes(File encryptedFile) async {
    if (_key == null) await init();

    final fileBytes = await encryptedFile.readAsBytes();
    
    // Extract IV (first 12 bytes)
    final iv = enc.IV(fileBytes.sublist(0, 12));
    // Extract Data (remaining bytes)
    final cipherText = fileBytes.sublist(12);

    final encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.gcm));
    
    // Decrypt
    final decrypted = encrypter.decryptBytes(enc.Encrypted(cipherText), iv: iv);

    return Uint8List.fromList(decrypted);
  }
  
  /// Decrypts a file and saves it to a temporary file (useful for video players or uploaders requiring path).
  static Future<File> decryptFileToTemp(File encryptedFile) async {
    final bytes = await decryptFileToBytes(encryptedFile);
    
    final tempDir = await getTemporaryDirectory();
    final name = p.basenameWithoutExtension(encryptedFile.path).replaceAll('_enc', '');
    final ext = p.extension(encryptedFile.path);
    final tempPath = p.join(tempDir.path, 'temp_dec_$name$ext');
    
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes);
    
    return tempFile;
  }
}
