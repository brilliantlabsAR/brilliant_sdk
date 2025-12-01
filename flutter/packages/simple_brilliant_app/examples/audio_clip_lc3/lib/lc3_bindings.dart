import 'dart:ffi';
import 'dart:io' show Platform;

// --- FFI Function Type Definitions ---
// These must match the C header file (lc3.h)
// int lc3_encoder_size(int dt_us, int sr_hz);
// C 'unsigned' return type is mapped to Dart 'int' / FFI 'Int32'.
// This is safe as the size will be positive.
typedef _Lc3EncoderSizeNative = Int32 Function(Int32 dt_us, Int32 sr_hz);
typedef _Lc3EncoderSizeDart = int Function(int dt_us, int sr_hz);

// lc3_encoder_t lc3_setup_encoder(int dt_us, int sr_hz, int sr_pcm_hz, void *mem);
// lc3_encoder_t is a typedef for void*
typedef _Lc3SetupEncoderNative = Pointer<Void> Function(
    Int32 dt_us, Int32 sr_hz, Int32 sr_pcm_hz, Pointer<Void> mem);
typedef _Lc3SetupEncoderDart = Pointer<Void> Function(
    int dt_us, int sr_hz, int sr_pcm_hz, Pointer<Void> mem);

// int lc3_encode(lc3_encoder_t enc, enum lc3_pcm_format pcm_fmt,
//                const void *pcm, int stride, int nbytes, void *out);
typedef _Lc3EncodeNative = Int32 Function(Pointer<Void> enc, Int32 pcm_fmt,
    Pointer<Void> pcm, Int32 stride, Int32 nbytes_out, Pointer<Void> out);
typedef _Lc3EncodeDart = int Function(Pointer<Void> enc, int pcm_fmt,
    Pointer<Void> pcm, int stride, int nbytes_out, Pointer<Void> out);

// --- Constants ---

// enum lc3_pcm_format
const int LC3_PCM_FORMAT_S16 = 0;

///
/// Helper class to load and bind to the native liblc3 library.
///
/// Assumes the dynamic library is named 'liblc3.so' on Android/Linux,
/// 'liblc3.dylib' on macOS, and 'liblc3.dll' on Windows.
/// You must ensure this compiled library is bundled with your app.
///
class Lc3Bindings {
  late final DynamicLibrary _dylib;

  late final _Lc3EncoderSizeDart lc3_encoder_size;
  late final _Lc3SetupEncoderDart lc3_setup_encoder;
  late final _Lc3EncodeDart lc3_encode;

  Lc3Bindings() {
    _dylib = _loadDynamicLibrary();
    
    // Look up the functions
    lc3_encoder_size = _dylib
        .lookup<NativeFunction<_Lc3EncoderSizeNative>>('lc3_encoder_size')
        .asFunction<_Lc3EncoderSizeDart>();

    lc3_setup_encoder = _dylib
        .lookup<NativeFunction<_Lc3SetupEncoderNative>>('lc3_setup_encoder')
        .asFunction<_Lc3SetupEncoderDart>();

    lc3_encode = _dylib
        .lookup<NativeFunction<_Lc3EncodeNative>>('lc3_encode')
        .asFunction<_Lc3EncodeDart>();
  }

  DynamicLibrary _loadDynamicLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('liblc3.so');
    }
    if (Platform.isIOS) {
      // For iOS, liblc3 must be bundled as a framework
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform');
  }
}