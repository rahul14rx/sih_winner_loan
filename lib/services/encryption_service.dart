import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EncryptionService {
  static const _keyFileName = 'local_enc_key.txt';
  static enc.Key? _key;

  /// Initialize the encryption key by storing/reading it from a local file.
  /// (Not using OS KeyRing as requested)
  static Future<void> init() async {
    if (_key != null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final keyFile = File(p.join(directory.path, _keyFileName));

      if (await keyFile.exists()) {
        // Read existing key
        final keyBase64 = await keyFile.readAsString();
        _key = enc.Key.fromBase64(keyBase64);
        print("🔐 Loaded local encryption key.");
      } else {
        // Generate new key
        print("🔐 Generating new local encryption key...");
        final newKey = enc.Key.fromSecureRandom(32);
        await keyFile.writeAsString(newKey.base64);
        _key = newKey;
        print("🔐 Saved local encryption key to file.");
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
