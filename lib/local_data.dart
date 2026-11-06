import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAccount {
  const LocalAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.salt,
    required this.passwordHash,
  });

  final String id;
  final String name;
  final String email;
  final String salt;
  final String passwordHash;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'salt': salt,
        'passwordHash': passwordHash,
      };

  factory LocalAccount.fromJson(Map<String, dynamic> json) => LocalAccount(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        salt: json['salt'] as String,
        passwordHash: json['passwordHash'] as String,
      );
}

class Review {
  Review(this.author, this.comment, this.stars, {this.authorId});

  final String author;
  final String comment;
  final int stars;
  final String? authorId;

  Map<String, Object?> toJson() => {
        'author': author,
        'comment': comment,
        'stars': stars,
        'authorId': authorId,
      };

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        json['author'] as String,
        json['comment'] as String,
        json['stars'] as int,
        authorId: json['authorId'] as String?,
      );
}

class ChatMessage {
  ChatMessage(this.author, this.text, this.time,
      {this.mine = false, this.authorId});

  final String author;
  final String text;
  final String time;
  final bool mine;
  final String? authorId;

  Map<String, Object?> toJson() => {
        'author': author,
        'text': text,
        'time': time,
        'authorId': authorId,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        json['author'] as String,
        json['text'] as String,
        json['time'] as String,
        authorId: json['authorId'] as String?,
      );
}

class Place {
  Place({
    required this.name,
    required this.category,
    this.description = '',
    this.imageBase64,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.reviews,
    required this.messages,
    required this.color,
    required this.ownerId,
  });

  String name;
  String category;
  String description;
  String? imageBase64;
  final double latitude;
  final double longitude;
  double rating;
  final List<Review> reviews;
  final List<ChatMessage> messages;
  Color color;
  final String ownerId;

  String get emoji {
    switch (category) {
      case 'Comida':
        return '☕';
      case 'Natureza':
        return '🌿';
      case 'Cultura':
        return '🎨';
      case 'Lazer':
        return '✨';
      default:
        return '📍';
    }
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'category': category,
        'description': description,
        'imageBase64': imageBase64,
        'latitude': latitude,
        'longitude': longitude,
        'rating': rating,
        'reviews': reviews.map((item) => item.toJson()).toList(),
        'messages': messages.map((item) => item.toJson()).toList(),
        'color': color.toARGB32(),
        'ownerId': ownerId,
      };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        name: json['name'] as String,
        category: json['category'] as String,
        description: json['description'] as String? ?? '',
        imageBase64: json['imageBase64'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        rating: (json['rating'] as num).toDouble(),
        reviews: (json['reviews'] as List<dynamic>? ?? [])
            .map((item) => Review.fromJson(item as Map<String, dynamic>))
            .toList(),
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .toList(),
        color: Color(json['color'] as int),
        ownerId: json['ownerId'] as String,
      );
}

bool canDeletePlace(Place place, LocalAccount account) =>
    place.ownerId == account.id;

class LocalAppData {
  LocalAppData({
    List<LocalAccount>? accounts,
    List<Place>? places,
    this.activeUserId,
  })  : accounts = accounts ?? [],
        places = places ?? [];

  final List<LocalAccount> accounts;
  final List<Place> places;
  String? activeUserId;

  LocalAccount? get activeAccount {
    for (final account in accounts) {
      if (account.id == activeUserId) return account;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'accounts': accounts.map((item) => item.toJson()).toList(),
        'places': places.map((item) => item.toJson()).toList(),
        'activeUserId': activeUserId,
      };

  factory LocalAppData.fromJson(Map<String, dynamic> json) => LocalAppData(
        accounts: (json['accounts'] as List<dynamic>? ?? [])
            .map((item) => LocalAccount.fromJson(item as Map<String, dynamic>))
            .toList(),
        places: (json['places'] as List<dynamic>? ?? [])
            .map((item) => Place.fromJson(item as Map<String, dynamic>))
            .toList(),
        activeUserId: json['activeUserId'] as String?,
      );
}

class LocalDataStore {
  static const _storageKey = 'perto.local-data.v1';

  Future<LocalAppData> load() async {
    final preferences = await SharedPreferences.getInstance();
    final contents = preferences.getString(_storageKey);
    if (contents == null) return LocalAppData();
    try {
      return LocalAppData.fromJson(
          jsonDecode(contents) as Map<String, dynamic>);
    } on FormatException catch (error) {
      throw LocalDataException(
        'Os dados locais estão inválidos. Eles não foram apagados.',
        error,
      );
    } on TypeError catch (error) {
      throw LocalDataException(
        'O formato dos dados locais não é compatível. Eles não foram apagados.',
        error,
      );
    }
  }

  Future<void> save(LocalAppData data) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(data.toJson()));
  }
}

class LocalDataException implements Exception {
  const LocalDataException(this.message, this.cause);

  final String message;
  final Object cause;

  @override
  String toString() => '$message ($cause)';
}

class LocalPassword {
  static const iterations = 120000;
  static const _keyLength = 32;

  static String createSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String createId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static Future<String> hash(String password, String salt) async {
    final saltBytes = _decodeHex(salt);
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = <int>[...saltBytes, 0, 0, 0, 1];
    var u = hmac.convert(block).bytes;
    final result = Uint8List.fromList(u);
    for (var iteration = 1; iteration < iterations; iteration++) {
      u = hmac.convert(u).bytes;
      for (var index = 0; index < _keyLength; index++) {
        result[index] ^= u[index];
      }
      if (iteration % 2048 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return result.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<bool> verify(
      String password, String salt, String expectedHash) async {
    final actualHash = await hash(password, salt);
    if (actualHash.length != expectedHash.length) return false;
    var difference = 0;
    for (var index = 0; index < actualHash.length; index++) {
      difference |=
          actualHash.codeUnitAt(index) ^ expectedHash.codeUnitAt(index);
    }
    return difference == 0;
  }

  static List<int> _decodeHex(String value) => [
        for (var index = 0; index < value.length; index += 2)
          int.parse(value.substring(index, index + 2), radix: 16),
      ];
}
