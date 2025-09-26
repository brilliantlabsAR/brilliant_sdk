class TextUtils {
  static const _lineHeight = 60;

  static const Map<int, int> charWidthMapping = {
    0x000020: 13,
    0x000021: 5,
    0x000022: 13,
    0x000023: 19,
    0x000024: 17,
    0x000025: 34,
    0x000026: 20,
    0x000027: 5,
    0x000028: 10,
    0x000029: 11,
    0x00002A: 21,
    0x00002B: 19,
    0x00002C: 8,
    0x00002D: 17,
    0x00002E: 6,
    0x000030: 18,
    0x000031: 16,
    0x000032: 16,
    0x000033: 15,
    0x000034: 18,
    0x000035: 15,
    0x000036: 17,
    0x000037: 15,
    0x000038: 18,
    0x000039: 17,
    0x00003A: 6,
    0x00003B: 8,
    0x00003C: 19,
    0x00003D: 19,
    0x00003E: 19,
    0x00003F: 14,
    0x000040: 31,
    0x000041: 22,
    0x000042: 18,
    0x000043: 16,
    0x000044: 19,
    0x000045: 17,
    0x000046: 17,
    0x000047: 18,
    0x000048: 19,
    0x000049: 12,
    0x00004A: 14,
    0x00004B: 19,
    0x00004C: 16,
    0x00004D: 23,
    0x00004E: 19,
    0x00004F: 20,
    0x000050: 18,
    0x000051: 22,
    0x000052: 20,
    0x000053: 17,
    0x000054: 20,
    0x000055: 19,
    0x000056: 21,
    0x000057: 23,
    0x000058: 21,
    0x000059: 23,
    0x00005A: 17,
    0x00005B: 9,
    0x00005C: 15,
    0x00005D: 10,
    0x00005E: 20,
    0x00005F: 25,
    0x000060: 11,
    0x000061: 19,
    0x000062: 18,
    0x000063: 13,
    0x000064: 18,
    0x000065: 16,
    0x000066: 15,
    0x000067: 20,
    0x000068: 18,
    0x000069: 5,
    0x00006A: 11,
    0x00006B: 18,
    0x00006C: 8,
    0x00006D: 28,
    0x00006E: 18,
    0x00006F: 18,
    0x000070: 18,
    0x000071: 18,
    0x000072: 11,
    0x000073: 15,
    0x000074: 14,
    0x000075: 17,
    0x000076: 19,
    0x000077: 30,
    0x000078: 20,
    0x000079: 20,
    0x00007A: 16,
    0x00007B: 12,
    0x00007C: 5,
    0x00007D: 12,
    0x00007E: 17,
    0x0000A1: 6,
    0x0000A2: 14,
    0x0000A3: 18,
    0x0000A5: 22,
    0x0000A9: 28,
    0x0000AB: 17,
    0x0000AE: 29,
    0x0000B0: 15,
    0x0000B1: 20,
    0x0000B5: 17,
    0x0000B7: 6,
    0x0000BB: 17,
    0x0000BF: 14,
    0x0000C0: 22,
    0x0000C1: 23,
    0x0000C2: 23,
    0x0000C3: 23,
    0x0000C4: 23,
    0x0000C5: 23,
    0x0000C6: 32,
    0x0000C7: 16,
    0x0000C8: 17,
    0x0000C9: 16,
    0x0000CA: 17,
    0x0000CB: 17,
    0x0000CC: 12,
    0x0000CD: 11,
    0x0000CE: 16,
    0x0000CF: 15,
    0x0000D0: 22,
    0x0000D1: 19,
    0x0000D2: 20,
    0x0000D3: 20,
    0x0000D4: 20,
    0x0000D5: 20,
    0x0000D6: 20,
    0x0000D7: 18,
    0x0000D8: 20,
    0x0000D9: 19,
    0x0000DA: 19,
    0x0000DB: 19,
    0x0000DC: 19,
    0x0000DD: 22,
    0x0000DE: 18,
    0x0000DF: 19,
    0x0000E0: 19,
    0x0000E1: 19,
    0x0000E2: 19,
    0x0000E3: 19,
    0x0000E4: 19,
    0x0000E5: 19,
    0x0000E6: 29,
    0x0000E7: 14,
    0x0000E8: 17,
    0x0000E9: 16,
    0x0000EA: 17,
    0x0000EB: 17,
    0x0000EC: 11,
    0x0000ED: 11,
    0x0000EE: 16,
    0x0000EF: 15,
    0x0000F0: 18,
    0x0000F1: 16,
    0x0000F2: 18,
    0x0000F3: 18,
    0x0000F4: 18,
    0x0000F5: 17,
    0x0000F6: 18,
    0x0000F7: 19,
    0x0000F8: 18,
    0x0000F9: 17,
    0x0000FA: 17,
    0x0000FB: 16,
    0x0000FC: 17,
    0x0000FD: 20,
    0x0000FE: 18,
    0x0000FF: 20,
    0x000131: 5,
    0x000141: 19,
    0x000142: 10,
    0x000152: 30,
    0x000153: 30,
    0x000160: 17,
    0x000161: 15,
    0x000178: 22,
    0x00017D: 18,
    0x00017E: 17,
    0x000192: 16,
    0x0020AC: 18,
    0x0F0000: 70,
    0x0F0001: 70,
    0x0F0002: 70,
    0x0F0003: 70,
    0x0F0004: 91,
    0x0F0005: 70,
    0x0F0006: 70,
    0x0F0007: 70,
    0x0F0008: 70,
    0x0F0009: 70,
    0x0F000A: 70,
    0x0F000B: 70,
    0x0F000C: 70,
    0x0F000D: 70,
    0x0F000E: 77,
    0x0F000F: 76,
    0x0F0010: 70
  };

  static int getTextWidth(String text, int charSpacing) {
    int width = 0;
    for (int i = 0; i < text.length; i++) {
      int charCode = text.codeUnitAt(i);
      width += charWidthMapping[charCode] ?? 25;
      width += charSpacing;
    }
    // if there's more than one character we probably should trim the extra charSpacing at the end
    return width == 0 ? 0 : width - charSpacing;
  }

  static int getTextHeight(String text) {
    int numLines = '\n'.allMatches(text).length + 1;
    return numLines * _lineHeight;
  }

  static List<String> wrapText(String text, int maxWidth, int charSpacing) {
    List<String> lines = text.split("\n");
    List<String> output = List.empty(growable: true);

    for (String line in lines) {
      String trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        continue;
      }
      else if (getTextWidth(trimmedLine, charSpacing) <= maxWidth) {
        output.add(trimmedLine);
      }
      else {
        String thisLine = "";
        List<String> words = trimmedLine.split(" ");
        for (String word in words) {
          if (getTextWidth("$thisLine $word", charSpacing) > maxWidth) {
            // TODO handle case in which first word > maxWidth
            // TODO shouldn't really be measuring length with the leading space char
            output.add(thisLine);
            thisLine = word;
          } else if (thisLine.isEmpty) {
            thisLine = word;
          } else {
            thisLine += " $word";
          }
        }
        if (thisLine.isNotEmpty) {
          output.add(thisLine.trim());
        }
      }
    }
    return output;
  }
}
