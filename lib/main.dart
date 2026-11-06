import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'local_data.dart';

void main() {
  runApp(const MapaVivoApp());
}

const _ink = Color(0xFF18332D);
const _muted = Color(0xFF71817A);
const _green = Color(0xFF176B55);
const _canvas = Color(0xFFF1F3EC);

Color _categoryColor(String category) {
  switch (category) {
    case 'Comida':
      return const Color(0xFFDF7854);
    case 'Natureza':
      return const Color(0xFF489A72);
    case 'Cultura':
      return const Color(0xFF8A73C1);
    case 'Lazer':
      return const Color(0xFFE1A93D);
    default:
      return _green;
  }
}

class MapaVivoApp extends StatelessWidget {
  const MapaVivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mapa Vivo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          primary: _green,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
      ),
      home: const _SessionGate(),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  final _store = LocalDataStore();
  LocalAppData? _data;
  Exception? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _store.load();
      if (!data.accounts.any((account) => account.id == data.activeUserId)) {
        data.activeUserId = null;
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadError = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<String?> _register(String name, String email, String password) async {
    final data = _data!;
    final normalizedEmail = email.trim().toLowerCase();
    if (data.accounts.any((account) => account.email == normalizedEmail)) {
      return 'Já existe uma conta local com este e-mail.';
    }
    final salt = LocalPassword.createSalt();
    final account = LocalAccount(
      id: LocalPassword.createId(),
      name: name.trim(),
      email: normalizedEmail,
      salt: salt,
      passwordHash: await LocalPassword.hash(password, salt),
    );
    data.accounts.add(account);
    final previousUserId = data.activeUserId;
    data.activeUserId = account.id;
    try {
      await _store.save(data);
    } on Exception {
      data.accounts.remove(account);
      data.activeUserId = previousUserId;
      rethrow;
    }
    if (mounted) setState(() {});
    return null;
  }

  Future<String?> _login(String email, String password) async {
    final data = _data!;
    final normalizedEmail = email.trim().toLowerCase();
    LocalAccount? account;
    for (final item in data.accounts) {
      if (item.email == normalizedEmail) {
        account = item;
        break;
      }
    }
    if (account == null ||
        !await LocalPassword.verify(
            password, account.salt, account.passwordHash)) {
      return 'E-mail ou senha incorretos.';
    }
    final previousUserId = data.activeUserId;
    data.activeUserId = account.id;
    try {
      await _store.save(data);
    } on Exception {
      data.activeUserId = previousUserId;
      rethrow;
    }
    if (mounted) setState(() {});
    return null;
  }

  Future<void> _logout() async {
    final previousUserId = _data!.activeUserId;
    _data!.activeUserId = null;
    try {
      await _store.save(_data!);
    } on Exception {
      _data!.activeUserId = previousUserId;
      rethrow;
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveData() => _store.save(_data!);

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final loadError = _loadError;
    if (loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 44),
                  const SizedBox(height: 12),
                  const Text(
                    'Não foi possível carregar os dados locais.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _ink, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loadError is LocalDataException
                        ? loadError.message
                        : 'Falha ao acessar o armazenamento: $loadError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (data == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _green)),
      );
    }
    final account = data.activeAccount;
    if (account == null) {
      return _AuthPage(
        hasAccounts: data.accounts.isNotEmpty,
        onLogin: _login,
        onRegister: _register,
      );
    }
    return MapHomePage(
      key: ValueKey(account.id),
      account: account,
      places: data.places,
      onDataChanged: _saveData,
      onLogout: _logout,
    );
  }
}

class _AuthPage extends StatefulWidget {
  const _AuthPage({
    required this.hasAccounts,
    required this.onLogin,
    required this.onRegister,
  });

  final bool hasAccounts;
  final Future<String?> Function(String email, String password) onLogin;
  final Future<String?> Function(String name, String email, String password)
      onRegister;

  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isRegistering = !widget.hasAccounts;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (_isRegistering && name.isEmpty) {
      setState(() => _error = 'Informe seu nome.');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Informe um e-mail válido.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'A senha deve ter pelo menos 8 caracteres.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final error = _isRegistering
          ? await widget.onRegister(name, email, password)
          : await widget.onLogin(email, password);
      if (mounted) setState(() => _error = error);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Não foi possível salvar os dados locais.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26)),
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.explore_rounded, color: _green, size: 46),
                    const SizedBox(height: 8),
                    const Text('Mapa Vivo',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _ink,
                            fontSize: 29,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 22),
                    if (_isRegistering) ...[
                      TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'Nome', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          labelText: 'E-mail', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                          labelText: 'Senha', border: OutlineInputBorder()),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(_isRegistering ? 'Criar conta' : 'Entrar'),
                      ),
                    ),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => setState(() {
                                _isRegistering = !_isRegistering;
                                _error = null;
                              }),
                      child: Text(
                        _isRegistering ? 'Já tenho uma conta' : 'Criar conta',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MapHomePage extends StatefulWidget {
  const MapHomePage({
    super.key,
    required this.account,
    required this.places,
    required this.onDataChanged,
    required this.onLogout,
  });

  final LocalAccount account;
  final List<Place> places;
  final Future<void> Function() onDataChanged;
  final Future<void> Function() onLogout;

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage> {
  final _searchController = TextEditingController();
  final _mapController = MapController();
  final _imagePicker = ImagePicker();
  Position? _currentPosition;
  bool _mapReady = false;
  bool _isLocating = false;
  String? _locationMessage;
  Place? _selectedPlace;
  _PendingPlace? _pendingPlace;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locateUser(requestPermission: true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _centerOnCurrentLocation() {
    final position = _currentPosition;
    if (!_mapReady || position == null) return;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      16,
    );
  }

  Future<void> _locateUser({required bool requestPermission}) async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _locationMessage = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationException(
          'Ative a localização do dispositivo para mostrar onde você está.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationException(
          'A permissão de localização foi negada. Permita o acesso para ver sua posição.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationException(
          'A localização está bloqueada nas configurações do dispositivo.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
      });
      _centerOnCurrentLocation();
    } on _LocationException catch (error) {
      if (mounted) setState(() => _locationMessage = error.message);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _locationMessage =
            'Não foi possível obter sua localização: $error');
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  List<Place> get _visiblePlaces {
    if (_query.trim().isEmpty) return widget.places;
    final query = _query.toLowerCase();
    return widget.places
        .where((place) =>
            place.name.toLowerCase().contains(query) ||
            place.category.toLowerCase().contains(query))
        .toList();
  }

  Future<bool> _persistChanges() async {
    try {
      await widget.onDataChanged();
      return true;
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível salvar as alterações: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _startAddingPlace() async {
    final pending = await showDialog<_PendingPlace>(
      context: context,
      builder: (_) => const _NewPlaceDialog(),
    );
    if (!mounted || pending == null) return;
    setState(() {
      _pendingPlace = pending;
      _selectedPlace = null;
    });
  }

  Future<void> _placeAt(LatLng position) async {
    final pending = _pendingPlace;
    if (pending == null) return;
    final place = Place(
      name: pending.name,
      category: pending.category,
      latitude: position.latitude,
      longitude: position.longitude,
      rating: 0,
      color: _categoryColor(pending.category),
      reviews: [],
      messages: [],
      ownerId: widget.account.id,
    );
    setState(() {
      widget.places.add(place);
      _selectedPlace = place;
      _pendingPlace = null;
      _query = '';
      _searchController.clear();
    });
    if (!await _persistChanges()) {
      if (mounted) {
        setState(() {
          widget.places.remove(place);
          if (_selectedPlace == place) _selectedPlace = null;
        });
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${place.name} foi adicionado ao mapa!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _openPlaceDetails(place);
  }

  Future<void> _showReviews(Place place) async {
    final review = await showDialog<Review>(
      context: context,
      builder: (_) => _ReviewDialog(
        placeName: place.name,
        account: widget.account,
      ),
    );
    if (!mounted || review == null) return;
    final previousRating = place.rating;
    setState(() {
      place.reviews.add(review);
      place.rating =
          place.reviews.map((item) => item.stars).reduce((a, b) => a + b) /
              place.reviews.length;
    });
    if (!await _persistChanges()) {
      if (mounted) {
        setState(() {
          place.reviews.remove(review);
          place.rating = previousRating;
        });
      }
    }
  }

  Future<void> _editPlace(Place place) async {
    if (!canDeletePlace(place, widget.account)) return;

    final edited = await showDialog<_PlaceEdit>(
      context: context,
      builder: (_) => _EditPlaceDialog(
        place: place,
        imagePicker: _imagePicker,
      ),
    );
    if (!mounted || edited == null) return;

    final previousName = place.name;
    final previousCategory = place.category;
    final previousColor = place.color;
    final previousDescription = place.description;
    final previousImage = place.imageBase64;
    setState(() {
      place.name = edited.name;
      place.category = edited.category;
      place.color = _categoryColor(edited.category);
      place.description = edited.description;
      place.imageBase64 = edited.imageBase64;
    });
    if (!await _persistChanges() && mounted) {
      setState(() {
        place.name = previousName;
        place.category = previousCategory;
        place.color = previousColor;
        place.description = previousDescription;
        place.imageBase64 = previousImage;
      });
    }
  }

  Future<bool> _deletePlace(Place place) async {
    if (!canDeletePlace(place, widget.account)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você só pode excluir os seus lugares.')),
      );
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir lugar?'),
        content: Text('“${place.name}” e seus dados locais serão removidos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return false;
    if (!canDeletePlace(place, widget.account)) return false;
    final originalIndex = widget.places.indexOf(place);
    setState(() {
      widget.places.remove(place);
      if (_selectedPlace == place) _selectedPlace = null;
    });
    if (!await _persistChanges() && mounted && originalIndex >= 0) {
      setState(() {
        widget.places.insert(originalIndex, place);
        _selectedPlace = place;
      });
      return false;
    }
    return true;
  }

  void _openPlaceDetails(Place place) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaceDetailsPage(
          place: place,
          ownerName: _ownerName(place.ownerId),
          canEdit: canDeletePlace(place, widget.account),
          onEdit: () => _editPlace(place),
          onDelete: () => _deletePlace(place),
          onReview: () => _showReviews(place),
          onChat: () => _openChat(place),
        ),
      ),
    );
  }

  void _openChat(Place place) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          place: place,
          account: widget.account,
          onDataChanged: widget.onDataChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPlace;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(0, 0),
              initialZoom: 2,
              minZoom: 3,
              maxZoom: 19,
              onMapReady: () {
                _mapReady = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _centerOnCurrentLocation();
                });
              },
              onTap: (_, point) => _placeAt(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'br.com.perto.mapa_vivo',
                maxNativeZoom: 19,
              ),
              MarkerLayer(
                markers: [
                  for (final place in _visiblePlaces)
                    Marker(
                      point: LatLng(place.latitude, place.longitude),
                      width: 52,
                      height: 60,
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPlace = place),
                        child: _MapMarker(
                          place: place,
                          selected: place == selected,
                        ),
                      ),
                    ),
                  if (_currentPosition case final position?)
                    Marker(
                      point: LatLng(position.latitude, position.longitude),
                      width: 30,
                      height: 30,
                      child: const _CurrentLocationMarker(),
                    ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _softShadow,
                        ),
                        child: const Icon(Icons.explore_rounded, color: _green),
                      ),
                      const SizedBox(width: 11),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mapa Vivo',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _RoundAction(
                        icon: _isLocating
                            ? Icons.location_searching_rounded
                            : Icons.my_location_rounded,
                        onTap: () {
                          setState(() => _selectedPlace = null);
                          _locateUser(requestPermission: true);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: _softShadow,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 21,
                          backgroundColor: const Color(0xFFE2F0E9),
                          child: Text(
                            _accountInitial,
                            style: const TextStyle(
                              color: _green,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.account.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() {
                              _selectedPlace = null;
                              _pendingPlace = null;
                            });
                            try {
                              await widget.onLogout();
                            } on Exception catch (error) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Não foi possível sair da conta local: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.logout_rounded, size: 17),
                          label: const Text('Sair'),
                          style: TextButton.styleFrom(
                            foregroundColor: _green,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: _softShadow,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            color: _green, size: 23),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Buscar lugares por perto',
                              hintStyle: TextStyle(color: _muted, fontSize: 14),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close, size: 19),
                          )
                        else
                          const Icon(Icons.tune_rounded,
                              color: _muted, size: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CategoryChips(
                    onSelected: (category) {
                      setState(() {
                        _query = category == 'Todos' ? '' : category;
                        _searchController.text = _query;
                      });
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(top: 2, right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (_locationMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: _softShadow,
                      ),
                      child: Text(
                        _locationMessage!,
                        style: const TextStyle(color: _ink, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_pendingPlace != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 170,
              left: 24,
              right: 24,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _ink,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'Toque no mapa para posicionar “${_pendingPlace!.name}”',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 20,
            bottom: selected == null ? 230 : 278,
            child: _RoundAction(
              icon: Icons.add_rounded,
              filled: true,
              onTap: _startAddingPlace,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: selected == null
                ? _DiscoveryCard(
                    places: _visiblePlaces,
                    onPlaceTap: _openPlaceDetails,
                    onBrowse: () => setState(() {
                      _selectedPlace =
                          _visiblePlaces.isEmpty ? null : _visiblePlaces.first;
                    }),
                  )
                : _PlaceCard(
                    place: selected,
                    ownerName: _ownerName(selected.ownerId),
                    canDelete: canDeletePlace(selected, widget.account),
                    onClose: () => setState(() => _selectedPlace = null),
                    onDelete: () {
                      _deletePlace(selected);
                    },
                    onDetails: () => _openPlaceDetails(selected),
                    onChat: () => _openChat(selected),
                  ),
          ),
        ],
      ),
    );
  }

  String _ownerName(String ownerId) {
    if (ownerId == widget.account.id) return widget.account.name;
    return 'Outro perfil local';
  }

  String get _accountInitial {
    final name = widget.account.name.trim();
    return name.isEmpty
        ? 'U'
        : String.fromCharCode(name.runes.first).toUpperCase();
  }
}

class _PlaceReviewsCard extends StatelessWidget {
  const _PlaceReviewsCard({
    required this.place,
    required this.onReview,
    required this.onOpenPlace,
  });

  final Place place;
  final VoidCallback onReview;
  final VoidCallback onOpenPlace;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: place.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child:
                      Text(place.emoji, style: const TextStyle(fontSize: 21)),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      place.category,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.star_rounded,
                  color: Color(0xFFF2B544), size: 19),
              const SizedBox(width: 3),
              Text(
                place.reviews.isEmpty ? '—' : place.rating.toStringAsFixed(1),
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (place.reviews.isEmpty)
            const Text(
              'Ainda não há avaliações.',
              style: TextStyle(color: _muted, fontSize: 13),
            )
          else
            ...place.reviews.map(
              (review) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (place.reviews.length > 1) const Divider(height: 1),
                    if (place.reviews.length > 1) const SizedBox(height: 10),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: const Color(0xFFE2F0E9),
                          child: Text(
                            review.author.trim().isEmpty
                                ? '?'
                                : String.fromCharCode(
                                    review.author.trim().runes.first,
                                  ).toUpperCase(),
                            style: const TextStyle(
                              color: _green,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            review.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            5,
                            (starIndex) => Icon(
                              starIndex < review.stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: const Color(0xFFF2B544),
                              size: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 38, top: 5),
                      child: Text(
                        review.comment,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onOpenPlace,
                icon: const Icon(Icons.arrow_back_rounded, size: 17),
                label: const Text('Voltar ao mapa'),
              ),
              TextButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.rate_review_outlined, size: 17),
                label: const Text('Avaliar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PlaceDetailsPage extends StatefulWidget {
  const PlaceDetailsPage({
    required this.place,
    required this.ownerName,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
    required this.onReview,
    required this.onChat,
    super.key,
  });

  final Place place;
  final String ownerName;
  final bool canEdit;
  final Future<void> Function() onEdit;
  final Future<bool> Function() onDelete;
  final Future<void> Function() onReview;
  final VoidCallback onChat;

  @override
  State<PlaceDetailsPage> createState() => _PlaceDetailsPageState();
}

class _PlaceDetailsPageState extends State<PlaceDetailsPage> {
  Future<void> _edit() async {
    await widget.onEdit();
    if (mounted) setState(() {});
  }

  Future<void> _review() async {
    await widget.onReview();
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    if (await widget.onDelete() && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final imageBase64 = place.imageBase64;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        title: Text(
          place.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.canEdit) ...[
            IconButton(
              tooltip: 'Editar lugar',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Excluir lugar',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: imageBase64 == null
                ? Container(
                    height: 210,
                    color: place.color.withValues(alpha: .16),
                    alignment: Alignment.center,
                    child: Text(
                      place.emoji,
                      style: const TextStyle(fontSize: 64),
                    ),
                  )
                : Image.memory(
                    base64Decode(imageBase64),
                    height: 230,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 210,
                      color: place.color.withValues(alpha: .16),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: _muted,
                        size: 42,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: _softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${place.category} • por ${widget.ownerName}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                if (place.description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    place.description,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFF2B544), size: 22),
                    const SizedBox(width: 4),
                    Text(
                      place.reviews.isEmpty
                          ? 'Sem avaliações'
                          : '${place.rating.toStringAsFixed(1)} (${place.reviews.length})',
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _CardAction(
                        icon: Icons.star_outline_rounded,
                        label: 'Avaliar',
                        onTap: _review,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CardAction(
                        icon: Icons.forum_outlined,
                        label: 'Conversar',
                        primary: true,
                        onTap: widget.onChat,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'Avaliações',
              style: TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _PlaceReviewsCard(
            place: place,
            onReview: _review,
            onOpenPlace: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _PlaceEdit {
  const _PlaceEdit({
    required this.name,
    required this.category,
    required this.description,
    required this.imageBase64,
  });

  final String name;
  final String category;
  final String description;
  final String? imageBase64;
}

class _NewPlaceDialog extends StatefulWidget {
  const _NewPlaceDialog();

  @override
  State<_NewPlaceDialog> createState() => _NewPlaceDialogState();
}

class _NewPlaceDialogState extends State<_NewPlaceDialog> {
  final _nameController = TextEditingController();
  String _category = 'Comida';
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const categories = ['Comida', 'Natureza', 'Cultura', 'Lazer'];
    return AlertDialog(
      title: const Text('Novo lugar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nome do lugar',
              hintText: 'Ex.: Padaria da esquina',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: categories
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(value),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Informe o nome do lugar.');
              return;
            }
            Navigator.pop(context, _PendingPlace(name, _category));
          },
          child: const Text('Escolher no mapa'),
        ),
      ],
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.placeName,
    required this.account,
  });

  final String placeName;
  final LocalAccount account;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _commentController = TextEditingController();
  int _stars = 5;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Avaliar lugar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.placeName, style: const TextStyle(color: _muted)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (index) => IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _stars = index + 1),
                icon: Icon(
                  index < _stars
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: const Color(0xFFF2B544),
                  size: 32,
                ),
              ),
            ),
          ),
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Conte como foi sua experiência',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final comment = _commentController.text.trim();
            if (comment.isEmpty) {
              setState(() => _error = 'Escreva um comentário.');
              return;
            }
            Navigator.pop(
              context,
              Review(
                widget.account.name,
                comment,
                _stars,
                authorId: widget.account.id,
              ),
            );
          },
          child: const Text('Publicar'),
        ),
      ],
    );
  }
}

class _EditPlaceDialog extends StatefulWidget {
  const _EditPlaceDialog({
    required this.place,
    required this.imagePicker,
  });

  final Place place;
  final ImagePicker imagePicker;

  @override
  State<_EditPlaceDialog> createState() => _EditPlaceDialogState();
}

class _EditPlaceDialogState extends State<_EditPlaceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _category;
  late String? _imageBase64;
  String? _error;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.place.name);
    _descriptionController =
        TextEditingController(text: widget.place.description);
    _category = widget.place.category;
    _imageBase64 = widget.place.imageBase64;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isPickingImage) return;
    setState(() {
      _isPickingImage = true;
      _error = null;
    });
    try {
      final pickedFile = await widget.imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (!mounted || pickedFile == null) return;
      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 1024 * 1024) {
        setState(
            () => _error = 'A imagem ficou maior que 1 MB. Escolha outra.');
        return;
      }
      setState(() => _imageBase64 = base64Encode(bytes));
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível abrir a imagem: $error');
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome do lugar.');
      return;
    }
    Navigator.pop(
      context,
      _PlaceEdit(
        name: name,
        category: _category,
        description: _descriptionController.text.trim(),
        imageBase64: _imageBase64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const categories = ['Comida', 'Natureza', 'Cultura', 'Lazer'];
    return AlertDialog(
      scrollable: true,
      title: const Text('Editar lugar'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: categories
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            if (_imageBase64 case final currentImage?)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  base64Decode(currentImage),
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 100,
                    child: Center(child: Text('Imagem inválida')),
                  ),
                ),
              )
            else
              Container(
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: _green,
                  size: 34,
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isPickingImage ? null : _pickImage,
              icon: _isPickingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined),
              label: const Text('Escolher imagem'),
            ),
            if (_imageBase64 != null)
              TextButton.icon(
                onPressed: () => setState(() => _imageBase64 = null),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remover imagem'),
              ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isPickingImage ? null : _save,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _PendingPlace {
  _PendingPlace(this.name, this.category);

  final String name;
  final String category;
}

class _LocationException implements Exception {
  const _LocationException(this.message);

  final String message;
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.place, required this.selected});

  final Place place;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: selected ? 44 : 38,
          height: selected ? 44 : 38,
          decoration: BoxDecoration(
            color: place.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: place.color.withValues(alpha: .35),
                blurRadius: 9,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(place.emoji, style: const TextStyle(fontSize: 18)),
          ),
        ),
        Container(
          width: 0,
          height: 0,
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.transparent, width: 6),
              right: BorderSide(color: Colors.transparent, width: 6),
              top: BorderSide(color: Colors.white, width: 7),
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrentLocationMarker extends StatelessWidget {
  const _CurrentLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF4285F4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .2),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.ownerName,
    required this.canDelete,
    required this.onClose,
    required this.onDelete,
    required this.onDetails,
    required this.onChat,
  });

  final Place place;
  final String ownerName;
  final bool canDelete;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onDetails;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: _softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: place.imageBase64 == null
                      ? ColoredBox(
                          color: place.color.withValues(alpha: .14),
                          child: Center(
                            child: Text(place.emoji,
                                style: const TextStyle(fontSize: 23)),
                          ),
                        )
                      : Image.memory(
                          base64Decode(place.imageBase64!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: place.color.withValues(alpha: .14),
                            child: Center(child: Text(place.emoji)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${place.category} • por $ownerName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.star_rounded,
                  color: Color(0xFFF2B544), size: 19),
              const SizedBox(width: 3),
              Text(
                place.reviews.isEmpty
                    ? 'Novo'
                    : place.rating.toStringAsFixed(1),
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 7),
              if (canDelete)
                IconButton(
                  tooltip: 'Excluir meu lugar',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 20),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: _muted, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CardAction(
                  icon: Icons.open_in_new_rounded,
                  label: 'Ver lugar',
                  onTap: onDetails,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CardAction(
                  icon: Icons.forum_outlined,
                  label:
                      'Conversar${place.messages.isEmpty ? '' : '  ${place.messages.length}'}',
                  primary: true,
                  onTap: onChat,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.places,
    required this.onPlaceTap,
    required this.onBrowse,
  });

  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final preview = places.take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lugares',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onBrowse,
                child: const Text('Explorar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (preview.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nenhum lugar encontrado.',
                  style: TextStyle(color: _muted)),
            )
          else
            ...preview.map(
              (place) => InkWell(
                onTap: () => onPlaceTap(place),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: place.color.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(child: Text(place.emoji)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          place.name,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFF2B544), size: 16),
                      const SizedBox(width: 3),
                      Text(
                        place.reviews.isEmpty
                            ? 'Novo'
                            : place.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, color: _muted, size: 18),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatefulWidget {
  const _CategoryChips({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  State<_CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<_CategoryChips> {
  String _selected = 'Todos';

  @override
  Widget build(BuildContext context) {
    const categories = ['Todos', 'Comida', 'Natureza', 'Cultura', 'Lazer'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((category) {
          final active = category == _selected;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(category),
              selected: active,
              onSelected: (_) {
                setState(() => _selected = category);
                widget.onSelected(category);
              },
              showCheckmark: false,
              labelStyle: TextStyle(
                color: active ? Colors.white : _ink,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: Colors.white,
              selectedColor: _green,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: primary ? _green : const Color(0xFFEFF4F1),
        foregroundColor: primary ? Colors.white : _green,
        minimumSize: const Size(0, 46),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? _green : Colors.white,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, color: filled ? Colors.white : _green, size: 22),
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.place,
    required this.account,
    required this.onDataChanged,
  });

  final Place place;
  final LocalAccount account;
  final Future<void> Function() onDataChanged;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    late final ChatMessage message;
    setState(() {
      message = ChatMessage(
        widget.account.name,
        text,
        TimeOfDay.now().format(context),
        mine: true,
        authorId: widget.account.id,
      );
      widget.place.messages.add(message);
      _messageController.clear();
    });
    try {
      await widget.onDataChanged();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          widget.place.messages.remove(message);
          _messageController.text = text;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar a mensagem: $error')),
        );
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.place.messages;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F2),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: widget.place.color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(widget.place.emoji,
                    style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.place.name,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(35),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, color: _green, size: 42),
                          SizedBox(height: 12),
                          Text(
                            'Comece a conversa',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => _MessageBubble(
                      message: messages[index],
                      mine: messages[index].authorId == widget.account.id ||
                          (messages[index].authorId == null &&
                              messages[index].mine),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Escreva uma mensagem...',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _green,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sendMessage,
                      child: const SizedBox(
                        width: 47,
                        height: 47,
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
        decoration: BoxDecoration(
          color: mine ? _green : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(17),
            topRight: const Radius.circular(17),
            bottomLeft: Radius.circular(mine ? 17 : 5),
            bottomRight: Radius.circular(mine ? 5 : 17),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.author,
                  style: TextStyle(
                    color: mine ? Colors.white70 : _green,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                color: mine ? Colors.white : _ink,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                message.time,
                style: TextStyle(
                  color: mine ? Colors.white70 : _muted,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _softShadow = [
  BoxShadow(
    color: Color(0x160D2E24),
    blurRadius: 22,
    offset: Offset(0, 8),
  ),
];
