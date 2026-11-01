import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapa_vivo/local_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('places keep the map coordinates and review/chat data', () {
    final place = Place(
      name: 'Café de teste',
      category: 'Comida',
      latitude: -23.5505,
      longitude: -46.6333,
      rating: 4.5,
      reviews: [Review('Pessoa', 'Muito bom', 5)],
      messages: [ChatMessage('Pessoa', 'Está aberto?', '12:00')],
      color: Colors.orange,
      ownerId: 'owner',
    );

    expect(place.latitude, -23.5505);
    expect(place.longitude, -46.6333);
    expect(place.reviews.single.stars, 5);
    expect(place.messages.single.text, 'Está aberto?');
  });

  test('local data round-trips account ownership, reviews, and chat', () {
    final data = LocalAppData(
      accounts: [
        const LocalAccount(
          id: 'account-1',
          name: 'Pessoa',
          email: 'pessoa@example.com',
          salt: '0123456789abcdef',
          passwordHash: 'hashed-password',
        ),
      ],
      places: [
        Place(
          name: 'Praça',
          category: 'Natureza',
          latitude: -23.5,
          longitude: -46.6,
          rating: 5,
          reviews: [Review('Pessoa', 'Excelente', 5, authorId: 'account-1')],
          messages: [
            ChatMessage('Pessoa', 'Olá', '12:00', authorId: 'account-1'),
          ],
          color: Colors.green,
          ownerId: 'account-1',
        ),
      ],
      activeUserId: 'account-1',
    );

    final restored = LocalAppData.fromJson(data.toJson());
    expect(restored.activeAccount?.email, 'pessoa@example.com');
    expect(restored.places.single.ownerId, 'account-1');
    expect(canDeletePlace(restored.places.single, restored.accounts.single),
        isTrue);
    expect(
      canDeletePlace(
        restored.places.single,
        const LocalAccount(
          id: 'account-2',
          name: 'Outro perfil',
          email: 'outro@example.com',
          salt: '0123456789abcdef',
          passwordHash: 'another-hash',
        ),
      ),
      isFalse,
    );
    expect(restored.places.single.reviews.single.authorId, 'account-1');
    expect(restored.places.single.messages.single.text, 'Olá');
    expect(restored.places.single.color.toARGB32(), Colors.green.toARGB32());
  });

  test('local store persists account and place data', () async {
    SharedPreferences.setMockInitialValues({});
    final data = LocalAppData(
      accounts: [
        const LocalAccount(
          id: 'account-2',
          name: 'Outro perfil',
          email: 'outro@example.com',
          salt: '0123456789abcdef',
          passwordHash: 'salted-hash',
        ),
      ],
      places: [
        Place(
          name: 'Local',
          category: 'Lazer',
          latitude: 0,
          longitude: 0,
          rating: 0,
          reviews: [],
          messages: [],
          color: Colors.amber,
          ownerId: 'account-2',
        ),
      ],
      activeUserId: 'account-2',
    );

    await LocalDataStore().save(data);
    final loaded = await LocalDataStore().load();

    expect(loaded.activeAccount?.id, 'account-2');
    expect(loaded.places.single.ownerId, 'account-2');
  });

  test('corrupt local data is reported without replacing stored contents',
      () async {
    SharedPreferences.setMockInitialValues({
      'perto.local-data.v1': '{invalid',
    });
    final store = LocalDataStore();

    await expectLater(store.load(), throwsA(isA<LocalDataException>()));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('perto.local-data.v1'), '{invalid');
  });

  test('password hashes are salted and verify without storing plaintext',
      () async {
    const password = 'senha-de-teste-segura';
    final salt = LocalPassword.createSalt();
    final hash = await LocalPassword.hash(password, salt);

    expect(hash, hasLength(64));
    expect(hash, isNot(password));
    expect(await LocalPassword.verify(password, salt, hash), isTrue);
    expect(await LocalPassword.verify('senha-incorreta', salt, hash), isFalse);
    expect(LocalPassword.createSalt(), isNot(salt));
  });
}
