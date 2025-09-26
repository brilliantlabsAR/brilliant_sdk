import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import '../tx_msg.dart';

final _log = Logger("TxSprite");

class TxSprite extends TxMsg {
  late final int _width;
  int get width => _width;
  late final int _height;
  int get height => _height;
  late final int _numColors;
  int get numColors => _numColors;
  late final Uint8List _paletteData;
  Uint8List get paletteData => _paletteData;
  late final Uint8List _pixelData;
  Uint8List get pixelData => _pixelData;

  /// Create a sprite with the specified size, palette data and pixel data, identified by the specified message code (the identifier used on the Lua side to label this sprite)
  /// width(Uint16), height(Uint16), bpp(Uint8), numColors(Uint8), palette (Uint8 r, Uint8 g, Uint8 b)*numColors, data (length: width x height bytes content: palette index)
  TxSprite({
    required int width,
    required int height,
    required int numColors,
    required Uint8List paletteData,
    required Uint8List pixelData})
    : _width = width,
      _height = height,
      _numColors = numColors,
      _paletteData = paletteData,
      _pixelData = pixelData;

  /// Create a TxSprite from any image bytes that can be decoded by img.decode()
  /// If it's an indexed image, quantize down to 14 colors if larger
  /// (plus black, white as palette entries 0 and 1.)
  /// If it's an RGB image, also quantize to 14 colors (then prepend black and white)
  /// Scale to 640x400 preserving aspect ratio for 1- or 2-bit images
  /// Scale to ~128k pixels preserving aspect ratio for 4-bit images
  /// TODO improve quantization - quality, speed
  /// If quantizing, since neuralNet seems to give the black in entry 0 and white in the last entry
  /// We just leave 0 (black) and swap palette entries 1 and 15 (and remap those pixels)
  TxSprite.fromImageBytes({required Uint8List imageBytes}) {
    var image = img.decodeImage(imageBytes);

    if (image == null) throw Exception('Unable to decode image file');

    // the number of colors in the image (after optional quantization), must be 16 or fewer
    final int numColors;
    bool quantized = false;

    if ((image.hasPalette && image.palette!.numColors > 16) || !image.hasPalette) {
      _log.fine('quantizing image');
      // note, even though we ask for only numberOfColors here, neuralNet gives us back a palette of 256
      // with only the first numberOfColors populated, ordered by increasing luminance (TODO and always containing black, then colors, then white last)
      // we'll trim that palette array down to 16*3 later
      image = img.quantize(image, numberOfColors: 16, method: img.QuantizeMethod.neuralNet, dither: img.DitherKernel.none);
      numColors = 16;
      quantized = true;
    }
    else {
      _log.fine('16 or fewer colors in an indexed image, no quantizing required');
      numColors = image.palette!.numColors;
    }

    if (image.width > 640 || image.height > 400) {
      _log.fine('scaling down oversized image');

      if (image.palette!.numColors <= 4) {
        _log.fine('Low bit depth image, scale to 640x400');
        // 1- or 2-bit images can take as much of 640x400 as needed, preserving aspect ratio
        // use nearest interpolation, we can't use any interpolation that averages colors
        image = img.copyResize(image,
            width: 640,
            height: 400,
            maintainAspect: true,
            interpolation: img.Interpolation.nearest);
      }
      else {
        _log.fine('4-bit image, scale to max 128k pixels');
        // 4-bit images need to be smaller or else we run out of memory. Limit to 64kb, or 128k pixels
        int numSrcPixels = image.height * image.width;

        if (numSrcPixels > 128000) {
          double scaleFactor = sqrt(128000 / numSrcPixels);
          _log.fine(() => 'scaling down by $scaleFactor');

          image = img.copyResize(image,
              width: (image.width * scaleFactor).toInt().clamp(1, 640),
              height: (image.height * scaleFactor).toInt().clamp(1, 400),
              maintainAspect: true,
              interpolation: img.Interpolation.nearest);
        }
        else {
          _log.fine('small 4-bit image, no need to scale down pixels, just max extent in height or width');
          // TODO does this scale up if the image is smaller? It doesn't need to do this.
          image = img.copyResize(image,
              width: 640,
              height: 400,
              maintainAspect: true,
              interpolation: img.Interpolation.nearest);
        }
      }
    }

    _width = image.width;
    _height = image.height;
    _pixelData = image.data!.toUint8List();
    // use a temporary palette in case we need to expand it to add VOID at the start
    Uint8List? initialPalette;

    // we can process RGB or RGBA format palettes, but any others we just exclude here
    if (image.palette!.numChannels == 3) {
      _log.fine('3-channel palette');
      // take the sublist because neuralNet quantized images have the number of colors we want
      // but packaged in a length 256 palette (a bug)
      initialPalette = image.palette!.toUint8List().sublist(0, 3 * numColors);
    }
    else if (image.palette!.numChannels == 4) {
      _log.fine('4-channel palette');
      // strip out the alpha channel from the palette
      // take the sublist because neuralNet quantized images have the number of colors we want
      // but packaged in a length 256 palette (a bug)
      initialPalette = _extractRGB(image.palette!.toUint8List().sublist(0, 4 * numColors));
    }
    else {
      throw Exception('Image colors must have 3 or 4 channels to be converted to a sprite');
    }

    // Frame uses palette entry 0 for VOID.
    // If we can fit another color, we can add VOID at the start and shift every pixel up by one.
    // If we can't fit any more colors, for now just set 0 to black (otherwise the rest of the display
    // will be lit)
    // We move the white palette index to 1 so that regular white text displays OK
    // TODO in future we could:
    // - find an alpha color from the palette (if it exists), and swap it with the color in 0
    // - find black from the palette (if it exists), and swap it with the color in 0
    // - find the darkest luminance color and swap it with the color in 0
    // - neuralNet quantizer seems to set 0 to black and max color to white.
    if (image.palette!.numColors < 16) {
      _log.fine('fewer than 16 colors');

      // if the first RGB color of the palette is not black/void, we need to
      // insert another color (which may promote the image to 2-bit or 4-bit)
      // but no need to if the palette already has black at the start
      if (initialPalette[0] != 0 || initialPalette[1] != 0 || initialPalette[2] != 0) {
        // TODO consider checking for whether we can move/add white to the #1 slot without
        // increasing the palette size to the next bitness
        _log.fine('insert black at the front of the palette');
        _numColors = image.palette!.numColors + 1;

        _paletteData = Uint8List(initialPalette.length + 3);
        _paletteData.setAll(3, initialPalette);
        _log.fine(initialPalette);
        _log.fine(_paletteData);

        // update all the pixels to refer to the new palette index
        for (int i=0; i<_pixelData.length; i++) {
          _pixelData[i] += 1;
        }
      }
      else {
        // palette already has black at the start, just copy it over
        _log.fine('black already at the start of the palette');
        _numColors = image.palette!.numColors;
        _paletteData = initialPalette;
      }
    }
    else {
      _log.fine('exactly 16 colors');

      if (!quantized) {
        // 16 colors in palette set by user's file, might not have black in slot 0
        _log.fine('16 colors exactly, make sure 0 is set to black');
        _numColors = image.palette!.numColors;
        // can't fit any more colors, set entry 0 to black
        _paletteData = initialPalette;
        _paletteData[0] = 0;
        _paletteData[1] = 0;
        _paletteData[2] = 0;
        _log.fine(initialPalette);
        _log.fine(_paletteData);
      }
      else {
        _log.fine('16 colors coming from quantizer');

        _numColors = 16;
        _paletteData = initialPalette;
        _log.fine(initialPalette);
        // black is already in #0 [0, 1, 2]

        // swap color in #1 [3, 4, 5] with white, which is in #15 [45, 46, 47]
        var swapR = _paletteData[3];
        var swapG = _paletteData[4];
        var swapB = _paletteData[5];
        _paletteData[3] = 255;
        _paletteData[4] = 255;
        _paletteData[5] = 255;
        _paletteData[45] = swapR;
        _paletteData[46] = swapG;
        _paletteData[47] = swapB;

        _log.fine(_paletteData);

        // update all the pixels to swap the palette index for white and the color that was in #1
        for (int i=0; i<_pixelData.length; i++) {
          if (_pixelData[i] == 1) {
            _pixelData[i] = 15;
          }
          else if (_pixelData[i] == 15) {
            _pixelData[i] = 1;
          }
        }
      }

      _log.fine(() => 'Sprite: $_width x $_height, $_numColors cols, ${pack().length} bytes');
    }
  }

  /// Create a TxSprite from an indexed PNG
  /// Sprites should be PNGs with palettes of up to 2, 4, or 16 colors (1-, 2-, or 4-bit indexed palettes)
  /// Alpha channel (4th-RGBA), if present, is dropped before sending to Frame (RGB only, but color 0 is VOID)
  /// Scale to 640x400 if larger, preserving aspect ratio
  TxSprite.fromPngBytes({required Uint8List pngBytes}) {
    var imgPng = img.PngDecoder().decode(pngBytes);

    if (imgPng != null &&
        imgPng.hasPalette &&
        imgPng.palette!.numColors <= 16) {
      // resize the image if it's too big - we really shouldn't have to do this for project sprites, just user-picked images
      if (imgPng.width > 640 || imgPng.height > 400) {
        // use nearest interpolation, we can't use any interpolation that averages colors
        imgPng = img.copyResize(imgPng,
            width: 640,
            height: 400,
            maintainAspect: true,
            interpolation: img.Interpolation.nearest);
      }

      _width = imgPng.width;
      _height = imgPng.height;
      _numColors = imgPng.palette!.numColors;
      _pixelData = imgPng.data!.toUint8List();

      // we can process RGB or RGBA format palettes, but any others we just exclude here
      if (imgPng.palette!.numChannels == 3 ||
          imgPng.palette!.numChannels == 4) {
        if (imgPng.palette!.numChannels == 3) {
          _paletteData = imgPng.palette!.toUint8List();
        }
        else if (imgPng.palette!.numChannels == 4) {
          // strip out the alpha channel from the palette
          _paletteData = _extractRGB(imgPng.palette!.toUint8List());
        }

        //_log.fine('Sprite: ${imgPng.width} x ${imgPng.height}, ${imgPng.palette!.numColors} cols, ${sprite.pack().length} bytes');
      } else {
        throw Exception(
            'PNG colors must have 3 or 4 channels to be converted to a sprite');
      }
    } else {
      throw Exception(
          'PNG must be a valid PNG image with a palette (indexed color) and 16 colors or fewer to be converted to a sprite');
    }
  }

  /// Strips the Alpha byte out of a list of RGBA colors
  /// Takes a Uint8List of length 4n made of RGBA bytes, and takes the first 3 bytes out of each 4 (RGB)
  Uint8List _extractRGB(Uint8List rgba) {
    _log.fine('extracting RGB from RGBA');
    // The output list will have 3/4 the length of the input list
    Uint8List rgb = Uint8List((rgba.length * 3) ~/ 4);

    int rgbIndex = 0;
    for (int i = 0; i < rgba.length; i += 4) {
      rgb[rgbIndex++] = rgba[i]; // R
      rgb[rgbIndex++] = rgba[i + 1]; // G
      rgb[rgbIndex++] = rgba[i + 2]; // B
    }

    return rgb;
  }

  /// Corresponding parser should be called from frame_app.lua data_handler()
  @override
  Uint8List pack() {
    int widthMsb = _width >> 8;
    int widthLsb = _width & 0xFF;
    int heightMsb = _height >> 8;
    int heightLsb = _height & 0xFF;
    int compressed = 0; // no compression supported yet
    int bpp = 0;
    Uint8List packed;
    switch (_numColors) {
      case <= 2:
        bpp = 1;
        packed = pack1Bit(_pixelData);
        break;
      case <= 4:
        bpp = 2;
        packed = pack2Bit(_pixelData);
        break;
      case <= 16:
        bpp = 4;
        packed = pack4Bit(_pixelData);
        break;
      default:
        throw Exception(
            'Image must have 16 or fewer colors. Actual: $_numColors');
    }

    // preallocate the list of bytes to send - sprite header, palette, pixel data
    // (packed.length already adds the extra byte if WxH is not divisible by 8)
    Uint8List payload =
        Uint8List.fromList(List.filled(7 + _numColors * 3 + packed.length, 0));

    // NB: palette data could be numColors=12 x 3 (RGB) bytes even if bpp is 4 (max 16 colors)
    // hence we provide both numColors and bpp here.
    // sendMessage will prepend the data byte, msgCode to each packet
    // and the Uint16 payload length to the first packet
    payload
        .setAll(0, [widthMsb, widthLsb, heightMsb, heightLsb, compressed, bpp, _numColors]);
    payload.setAll(7, _paletteData);
    payload.setAll(7 + _numColors * 3, packed);

    return payload;
  }

  static Uint8List pack1Bit(Uint8List bpp1) {
    int byteLength =
        (bpp1.length + 7) ~/ 8; // Calculate the required number of bytes
    Uint8List packed =
        Uint8List(byteLength); // Create the Uint8List to hold packed bytes

    for (int i = 0; i < bpp1.length; i++) {
      int byteIndex = i ~/ 8;
      int bitIndex = i % 8;
      packed[byteIndex] |= (bpp1[i] & 0x01) << (7 - bitIndex);
    }

    return packed;
  }

  static Uint8List pack2Bit(Uint8List bpp2) {
    int byteLength =
        (bpp2.length + 3) ~/ 4; // Calculate the required number of bytes
    Uint8List packed =
        Uint8List(byteLength); // Create the Uint8List to hold packed bytes

    for (int i = 0; i < bpp2.length; i++) {
      int byteIndex = i ~/ 4;
      int bitOffset = (3 - (i % 4)) * 2;
      packed[byteIndex] |= (bpp2[i] & 0x03) << bitOffset;
    }

    return packed;
  }

  static Uint8List pack4Bit(Uint8List bpp4) {
    int byteLength =
        (bpp4.length + 1) ~/ 2; // Calculate the required number of bytes
    Uint8List packed =
        Uint8List(byteLength); // Create the Uint8List to hold packed bytes

    for (int i = 0; i < bpp4.length; i++) {
      int byteIndex = i ~/ 2;
      int bitOffset = (1 - (i % 2)) * 4;
      packed[byteIndex] |= (bpp4[i] & 0x0F) << bitOffset;
    }

    return packed;
  }

  /// Convert TxSprite back to an image for testing/verification
  img.Image toImage() {
    // set up the indexed palette
    img.PaletteUint8 pal = img.PaletteUint8(_numColors, 3);
    pal.buffer.asUint8List().setAll(0, _paletteData);

    // TODO Image.palette() doesn't seem to correctly create indexed image.
    // instead, expand out the image to RGB pixels since this is just for phoneside display
    var data = img.ImageDataUint8(_width, _height, 3);
    int pixNum = 0;

    for (var palEntry in _pixelData) {
      data.setPixelRgb(
          pixNum % _width,
          pixNum ~/ _width,
          _paletteData[palEntry * 3],
          _paletteData[palEntry * 3 + 1],
          _paletteData[palEntry * 3 + 2]);

      pixNum++;
    }

    return img.Image.fromBytes(
        width: _width, height: _height, bytes: data.buffer, numChannels: 3);
  }
}
