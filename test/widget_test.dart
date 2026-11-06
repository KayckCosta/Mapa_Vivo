import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapa_vivo/local_data.dart';
import 'package:mapa_vivo/main.dart' hide main;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('places keep the map coordinates and review/chat data', () {
    final place = Place(
      name: 'Café de teste',
      category: 'Comida',
      description: 'Café com mesas ao ar livre',
      imageBase64: 'aW1hZ2U=',
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
    expect(place.description, 'Café com mesas ao ar livre');
    expect(place.imageBase64, 'aW1hZ2U=');
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
          description: 'Área verde para passear',
          imageBase64: 'cGhvdG8=',
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
    expect(restored.places.single.description, 'Área verde para passear');
    expect(restored.places.single.imageBase64, 'cGhvdG8=');
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

  test('older saved places load without descriptions or images', () {
    final place = Place.fromJson({
      'name': 'Praça',
      'category': 'Natureza',
      'latitude': -23.5,
      'longitude': -46.6,
      'rating': 0,
      'reviews': <Object>[],
      'messages': <Object>[],
      'color': Colors.green.toARGB32(),
      'ownerId': 'account-1',
    });

    expect(place.description, isEmpty);
    expect(place.imageBase64, isNull);
  });

  testWidgets('place details show their reviews and owner edit controls',
      (tester) async {
    final place = Place(
      name: 'Parque Central',
      category: 'Natureza',
      description: 'Um lugar para caminhar',
      latitude: -23.5,
      longitude: -46.6,
      rating: 5,
      reviews: [Review('Ana', 'Muito bonito', 5)],
      messages: [],
      color: Colors.green,
      ownerId: 'owner',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailsPage(
          place: place,
          ownerName: 'Pessoa',
          canEdit: true,
          onEdit: () async {},
          onDelete: () async => false,
          onReview: () async {},
          onChat: () {},
        ),
      ),
    );

    expect(find.text('Parque Central'), findsWidgets);
    expect(find.text('Um lugar para caminhar'), findsOneWidget);
    expect(find.text('Avaliações'), findsOneWidget);
    expect(find.text('Muito bonito'), findsOneWidget);
    expect(find.byTooltip('Editar lugar'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('review and edit dialogs finish without lifecycle errors',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const account = LocalAccount(
      id: 'account-1',
      name: 'Pessoa',
      email: 'pessoa@example.com',
      salt: '0123456789abcdef',
      passwordHash: 'hashed-password',
    );
    final place = Place(
      name: 'Praça',
      category: 'Natureza',
      latitude: -23.5,
      longitude: -46.6,
      rating: 0,
      reviews: [],
      messages: [],
      color: Colors.green,
      ownerId: account.id,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapHomePage(
          account: account,
          places: [place],
          onDataChanged: () async {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver lugar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avaliar').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Muito bom');
    await tester.tap(find.text('Publicar'));
    await tester.pumpAndSettle();

    expect(place.reviews.single.comment, 'Muito bom');
    expect(find.text('Muito bom'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar lugar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Praça arborizada');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(place.description, 'Praça arborizada');
    expect(place.name, 'Praça');
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
