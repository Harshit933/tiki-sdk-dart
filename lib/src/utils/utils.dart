/*
 * Copyright (c) TIKI Inc.
 * MIT license. See LICENSE file in root directory.
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/random/fortuna_random.dart';

FortunaRandom secureRandom() {
  var secureRandom = FortunaRandom();
  var random = Random.secure();
  final seeds = <int>[];
  for (int i = 0; i < 32; i++) {
    seeds.add(random.nextInt(255));
  }
  secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
  return secureRandom;
}

/// Encode a BigInt into bytes using big-endian encoding.
/// It encodes the integer to a minimal twos-compliment integer as defined by
/// ASN.1
/// From pointycastle/src/utils
Uint8List encodeBigInt(BigInt? number) {
  if (number == BigInt.zero) {
    return Uint8List.fromList([0]);
  }

  int needsPaddingByte;
  int rawSize;

  if (number! > BigInt.zero) {
    rawSize = (number.bitLength + 7) >> 3;
    needsPaddingByte =
        ((number >> (rawSize - 1) * 8) & BigInt.from(0x80)) == BigInt.from(0x80)
            ? 1
            : 0;
  } else {
    needsPaddingByte = 0;
    rawSize = (number.bitLength + 8) >> 3;
  }

  final size = rawSize + needsPaddingByte;
  var result = Uint8List(size);
  for (var i = 0; i < rawSize; i++) {
    result[size - i - 1] = (number! & BigInt.from(0xff)).toInt();
    number = number >> 8;
  }
  return result;
}

/// Decode a BigInt from bytes in big-endian encoding.
/// Twos compliment.
/// From pointycastle/src/utils
BigInt decodeBigInt(List<int> bytes) {
  var negative = bytes.isNotEmpty && bytes[0] & 0x80 == 0x80;

  BigInt result;

  if (bytes.length == 1) {
    result = BigInt.from(bytes[0]);
  } else {
    result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      var item = bytes[bytes.length - i - 1];
      result |= (BigInt.from(item) << (8 * i));
    }
  }
  return result != BigInt.zero
      ? negative
          ? result.toSigned(result.bitLength)
          : result
      : BigInt.zero;
}

Uint8List processInBlocks(AsymmetricBlockCipher engine, Uint8List input) {
  final numBlocks = input.length ~/ engine.inputBlockSize +
      ((input.length % engine.inputBlockSize != 0) ? 1 : 0);

  final output = Uint8List(numBlocks * engine.outputBlockSize);

  var inputOffset = 0;
  var outputOffset = 0;
  while (inputOffset < input.length) {
    final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
        ? engine.inputBlockSize
        : input.length - inputOffset;

    outputOffset += engine.processBlock(
        input, inputOffset, chunkSize, output, outputOffset);

    inputOffset += chunkSize;
  }

  return (output.length == outputOffset)
      ? output
      : output.sublist(0, outputOffset);
}

Uint8List addPadding(Uint8List message, int blockSize, {int pad = 0}) {
  if (pad < 0 || pad > 255) {
    throw ArgumentError("pad value must be between 0 - 255");
  }

  int numPadding = (~message.length + 1) & (blockSize - 1);
  BytesBuilder padded = BytesBuilder();
  padded.add(message);
  for (int i = 0; i < numPadding; i++) {
    padded.add([pad]);
  }

  return padded.toBytes();
}

Uint8List removePadding(Uint8List message, {int pad = 0}) {
  if (pad < 0 || pad > 255) {
    throw ArgumentError("pad value must be between 0 - 255");
  }

  int paddingStart;
  for (paddingStart = message.length - 1;
      paddingStart > 0 && message.elementAt(paddingStart) == pad;
      paddingStart--) {}
  return message.sublist(0, paddingStart + 1);
}

Uint8List sha256(Uint8List message, {bool sha3 = true}) {
  Digest digest = sha3 ? Digest("SHA3-256") : Digest("SHA-256");
  return digest.process(message);
}

String hexEncode(Uint8List message) {
  String s = "";
  for (int e in message) {
    s += e.toRadixString(16).padLeft(2, "0");
  }
  return s;
}

Uint8List hexDecode(String message) {
  if (message.length % 2 > 0) message = "0$message";

  int len = (message.length / 2).floor();
  Uint8List output = Uint8List(len);

  for (int i = 0; i < len; i++) {
    String s = message.substring(i * 2, (i + 1) * 2);
    output[i] = int.parse(s, radix: 16);
  }

  return output;
}

Uint8List serializeInt(int value) {
  Uint8List uint8List = encodeBigInt(BigInt.from(value));
  return Uint8List.fromList([uint8List.length, ...uint8List]);
}

String? uint8ListToBase64Url(Uint8List? uint8list,
    {bool nullable = false, bool addQuotes = false}) {
  if (uint8list == null) {
    if (nullable) return null;
    return '${addQuotes ? "'" : ''}${base64Url.encode(Uint8List(1))}${addQuotes ? "'" : ''}';
  }
  return '${addQuotes ? "'" : ''}${base64Url.encode(uint8list)}${addQuotes ? "'" : ''}';
}

Uint8List? base64UrlToUint8List(String? base64String,
    {bool nullable = false, bool addQuotes = false}) {
  if (base64String == null) {
    if (nullable) return null;
    return base64Url.decode('AA==');
  }
  return base64Url.decode(base64String);
}

Uint8List calculateMerkelRoot(List<Uint8List> hashes) {
  if (hashes.isEmpty) return Uint8List(1);
  List<Uint8List> currentList = hashes;
  List<Uint8List> nextList = [];
  Uint8List? left;
  Uint8List? right;
  while (currentList.length > 1) {
    for (int i = 0; i < currentList.length; i++) {
      if (left == null) {
        left = currentList[i];
        continue;
      }
      right = currentList[1];
      Uint8List hash = sha256(Uint8List.fromList([...left, ...right]));
      nextList.add(hash);
      left = null;
    }
    if (left != null) {
      nextList.add(left);
    }
    currentList = nextList;
    nextList = [];
  }
  return currentList.single;
}
