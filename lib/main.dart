import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ================= App Colors =================
class AppColors {
  static const navy = Color(0xFF1E3A5F);
  static const lightBlue = Color(0xFF5B9BD5);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const white = Color(0xFFF8FAFC);
  static const gold = Color(0xFFF4C542);
  static const darkBg = Color(0xFF0F172A);
  static const darkCard = Color(0xFF1E293B);
}

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'sans-serif',
  scaffoldBackgroundColor: AppColors.white,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    brightness: Brightness.light,
    primary: AppColors.navy,
    secondary: AppColors.gold,
  ),
  cardColor: Colors.white,
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'sans-serif',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.darkBg,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.lightBlue,
    brightness: Brightness.dark,
    primary: AppColors.lightBlue,
    secondary: AppColors.gold,
  ),
  cardColor: AppColors.darkCard,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }
  final savedDark = await SecureStorageService.instance.getDarkMode();
  themeModeNotifier.value = savedDark ? ThemeMode.dark : ThemeMode.light;
  runApp(const SmartGateApp());
}

// ================= Secure Storage Service =================
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _pinKey = 'app_pin';
  static const _tokenKey = 'device_token';
  static const _ipKey = 'esp32_ip';
  static const _darkModeKey = 'dark_mode';

  static const String _defaultIp = '192.168.1.50';
  static const String _defaultPin = '1764'; // Fixed Default PIN

  String _generateToken() {
    final randomStr = Random.secure()
        .nextInt(999999)
        .toString()
        .padLeft(6, '0');
    return 'SEC_TOK_$randomStr';
  }

  Future<String> getPin() async {
    final existing = await _storage.read(key: _pinKey);
    if (existing != null && existing.isNotEmpty) return existing;
    await _storage.write(key: _pinKey, value: _defaultPin);
    return _defaultPin;
  }

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  Future<String> getToken() async {
    final existing = await _storage.read(key: _tokenKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _generateToken();
    await _storage.write(key: _tokenKey, value: generated);
    return generated;
  }

  Future<String> regenerateToken() async {
    final generated = _generateToken();
    await _storage.write(key: _tokenKey, value: generated);
    return generated;
  }

  Future<String> getIp() async {
    final existing = await _storage.read(key: _ipKey);
    if (existing != null && existing.isNotEmpty) return existing;
    await _storage.write(key: _ipKey, value: _defaultIp);
    return _defaultIp;
  }

  Future<void> setIp(String ip) async {
    await _storage.write(key: _ipKey, value: ip);
  }

  Future<bool> getDarkMode() async {
    final v = await _storage.read(key: _darkModeKey);
    return v == 'true';
  }

  Future<void> setDarkMode(bool value) async {
    await _storage.write(key: _darkModeKey, value: value.toString());
  }
}

class SmartGateApp extends StatelessWidget {
  const SmartGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Smart Access Control',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          home: const LockScreen(),
        );
      },
    );
  }
}

// ================= Lock Screen =================
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _pinController = TextEditingController();
  final _storage = SecureStorageService.instance;

  String? savedPin;
  bool isLoadingPin = true;
  bool isBiometricSupported = false;
  bool isAuthenticating = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initLock();
  }

  Future<void> _initLock() async {
    final pin = await _storage.getPin();
    if (!mounted) return;
    setState(() {
      savedPin = pin;
      isLoadingPin = false;
    });
    await _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool isDeviceSupported = await auth.isDeviceSupported();

      if (mounted) {
        setState(() {
          isBiometricSupported =
              canAuthenticateWithBiometrics || isDeviceSupported;
        });
      }

      if (isBiometricSupported) {
        _authenticateWithBiometrics();
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      setState(() {
        isAuthenticating = true;
        errorMessage = '';
      });

      final bool authenticated = await auth.authenticate(
        localizedReason: 'Please authenticate to unlock gate controls',
      );

      if (authenticated && mounted) {
        _unlockApp();
      }
    } on PlatformException catch (e) {
      setState(() {
        errorMessage = 'Biometric authentication failed: ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          isAuthenticating = false;
        });
      }
    }
  }

  void _verifyPin() {
    if (_pinController.text == savedPin) {
      _unlockApp();
    } else {
      setState(() {
        errorMessage = 'Invalid Passcode!';
      });
      _pinController.clear();
    }
  }

  void _unlockApp() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainNavigator()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingPin) {
      return const Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF8A9EA7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    size: 70,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Smart Gate Security 🔒',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please authenticate via biometric or passcode',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (errorMessage.isNotEmpty) ...[
                        Text(
                          errorMessage,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: '••••',
                          counterText: '',
                          labelText: 'Passcode',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length == 4) {
                            _verifyPin();
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _verifyPin,
                          child: const Text(
                            'Unlock with Passcode',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (isBiometricSupported) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            side: const BorderSide(color: AppColors.navy),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.fingerprint_rounded,
                            color: AppColors.navy,
                          ),
                          label: const Text(
                            'Use Fingerprint',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: isAuthenticating
                              ? null
                              : _authenticateWithBiometrics,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================= Main Navigator =================
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  final _storage = SecureStorageService.instance;
  String? esp32Ip;
  String? deviceToken;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ip = await _storage.getIp();
    final token = await _storage.getToken();
    if (!mounted) return;
    setState(() {
      esp32Ip = ip;
      deviceToken = token;
      isLoading = false;
    });
  }

  Future<void> _updateIp(String ip) async {
    await _storage.setIp(ip);
    if (mounted) setState(() => esp32Ip = ip);
  }

  Future<void> _regenerateToken() async {
    final t = await _storage.regenerateToken();
    if (mounted) setState(() => deviceToken = t);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || esp32Ip == null || deviceToken == null) {
      return const Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return HomeScreen(
      esp32Ip: esp32Ip!,
      deviceToken: deviceToken!,
      onIpChanged: _updateIp,
      onGenerateNewToken: _regenerateToken,
    );
  }
}

// ================= Home Screen =================
class HomeScreen extends StatefulWidget {
  final String esp32Ip;
  final String deviceToken;
  final ValueChanged<String> onIpChanged;
  final VoidCallback onGenerateNewToken;

  const HomeScreen({
    super.key,
    required this.esp32Ip,
    required this.deviceToken,
    required this.onIpChanged,
    required this.onGenerateNewToken,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = SecureStorageService.instance;

  bool isConnected = false;
  bool isGate1Loading = false;
  bool isGate2Loading = false;
  bool gate1DoorOpen = false;
  bool gate2DoorOpen = false;

  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _gate1CloseTimer;
  Timer? _gate2CloseTimer;

  @override
  void initState() {
    super.initState();
    checkConnection();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _gate1CloseTimer?.cancel();
    _gate2CloseTimer?.cancel();
    super.dispose();
  }

  Future<void> checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('http://${widget.esp32Ip}/'))
          .timeout(const Duration(seconds: 3));
      if (mounted) setState(() => isConnected = response.statusCode == 200);
    } catch (_) {
      if (mounted) setState(() => isConnected = false);
    }
  }

  Future<void> sendEspCommand(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('http://${widget.esp32Ip}/$endpoint'),
      );
      if (mounted) setState(() => isConnected = true);
      debugPrint('ESP response: ${response.body}');
    } catch (e) {
      if (mounted) setState(() => isConnected = false);
      debugPrint('ESP command note: $e');
    }
  }

  Future<void> _triggerMainGate() async {
    if (isGate1Loading) return;
    setState(() => isGate1Loading = true);
    try {
      if (Firebase.apps.isNotEmpty) {
        try {
          final ref = FirebaseDatabase.instance.ref(
            "devices/${widget.deviceToken}/gate1",
          );
          await ref.set({"trigger": true, "timestamp": ServerValue.timestamp});
        } catch (e) {
          debugPrint('Firebase write note: $e');
        }
      }
      await sendEspCommand('gate1/open?token=${widget.deviceToken}');
    } finally {
      if (mounted) {
        setState(() {
          isGate1Loading = false;
          gate1DoorOpen = true;
        });
        _showSuccessBanner('Main Gate Opened Successfully ✅');
        _gate1CloseTimer?.cancel();
        _gate1CloseTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => gate1DoorOpen = false);
        });
      }
    }
  }

  Future<void> _triggerInternalGate() async {
    if (isGate2Loading) return;
    setState(() => isGate2Loading = true);
    try {
      if (Firebase.apps.isNotEmpty) {
        try {
          final ref = FirebaseDatabase.instance.ref(
            "devices/${widget.deviceToken}/gate2",
          );
          await ref.set({"trigger": true, "timestamp": ServerValue.timestamp});
        } catch (e) {
          debugPrint('Firebase write note: $e');
        }
      }
      await sendEspCommand('gate2/open?token=${widget.deviceToken}');
    } finally {
      if (mounted) {
        setState(() {
          isGate2Loading = false;
          gate2DoorOpen = true;
        });
        _showSuccessBanner('Internal Gate Opened Successfully ✅');
        _gate2CloseTimer?.cancel();
        _gate2CloseTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => gate2DoorOpen = false);
        });
      }
    }
  }

  void _showSuccessBanner(String message) {
    final overlayState = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 12,
        left: 20,
        right: 20,
        child: _SuccessBanner(message: message, onDone: () => entry.remove()),
      ),
    );
    overlayState.insert(entry);
  }

  Future<void> _showChangePinDialog(BuildContext parentContext) async {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? dialogError;

    await showDialog(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                'Change Passcode',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dialogError != null) ...[
                    Text(
                      dialogError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: currentPinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Current Passcode',
                      counterText: '',
                    ),
                  ),
                  TextField(
                    controller: newPinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'New Passcode',
                      counterText: '',
                    ),
                  ),
                  TextField(
                    controller: confirmPinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Passcode',
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final storedPin = await _storage.getPin();
                    if (currentPinController.text != storedPin) {
                      setDialogState(
                        () => dialogError = 'Current passcode is incorrect',
                      );
                      return;
                    }
                    if (newPinController.text.length != 4 ||
                        int.tryParse(newPinController.text) == null) {
                      setDialogState(
                        () => dialogError = 'New passcode must be 4 digits',
                      );
                      return;
                    }
                    if (newPinController.text != confirmPinController.text) {
                      setDialogState(
                        () => dialogError = 'Passcodes do not match',
                      );
                      return;
                    }
                    await _storage.setPin(newPinController.text);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    _showSuccessBanner('Passcode changed successfully 🔐');
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openSettingsDialog() async {
    final ipController = TextEditingController(text: widget.esp32Ip);
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.settings_rounded, color: AppColors.navy),
                  SizedBox(width: 8),
                  Text(
                    'Settings',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ESP32 IP Address',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: ipController,
                      decoration: InputDecoration(
                        hintText: '192.168.1.50',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dark Mode 🌙',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: themeModeNotifier,
                          builder: (context, mode, _) {
                            return Switch(
                              value: mode == ThemeMode.dark,
                              activeTrackColor: AppColors.navy,
                              onChanged: (val) async {
                                themeModeNotifier.value = val
                                    ? ThemeMode.dark
                                    : ThemeMode.light;
                                await _storage.setDarkMode(val);
                                setDialogState(() {});
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Security Token',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.deviceToken,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 20),
                          tooltip: 'Copy Token',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.deviceToken),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'Regenerate Token',
                          onPressed: () {
                            widget.onGenerateNewToken();
                            setDialogState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _showChangePinDialog(context),
                        icon: const Icon(Icons.lock_reset_rounded, size: 18),
                        label: const Text('Change Passcode'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    widget.onIpChanged(ipController.text.trim());
                    Navigator.of(dialogContext).pop();
                    _showSuccessBanner('Settings saved ✅');
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDateTime(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final wd = weekdays[dt.weekday - 1];
    final mo = months[dt.month - 1];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$wd, $mo ${dt.day} ${dt.year} • $hour12:$minute $ampm';
  }

  Widget _statChip(String label, String value, Color color, bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: dark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: dark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? AppColors.darkBg : AppColors.white,
      body: Stack(
        children: [
          ClipPath(
            clipper: _TopWaveClipper(),
            child: Container(
              height: 230,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.navy, AppColors.lightBlue],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.sensor_door_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            Positioned(
                              right: -3,
                              bottom: -3,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppColors.gold,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.wifi_rounded,
                                  size: 10,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Welcome Home 👋',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDateTime(_now),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.settings_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _openSettingsDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Connection Status
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PulseDot(
                          color: isConnected ? AppColors.green : AppColors.red,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isConnected ? 'ESP32 Online' : 'ESP32 Offline',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: checkConnection,
                          child: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Mini Stats
                  Row(
                    children: [
                      Expanded(
                        child: _statChip(
                          'Connection',
                          isConnected ? 'Online' : 'Offline',
                          isConnected ? AppColors.green : AppColors.red,
                          dark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statChip(
                          'Main Gate',
                          gate1DoorOpen ? 'Open' : 'Closed',
                          gate1DoorOpen ? AppColors.green : Colors.grey,
                          dark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statChip(
                          'Internal Gate',
                          gate2DoorOpen ? 'Open' : 'Closed',
                          gate2DoorOpen ? AppColors.green : Colors.grey,
                          dark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // House & Gates Visualization
                  Center(
                    child: SizedBox(
                      width: 260,
                      height: 150,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Positioned(
                            bottom: 14,
                            child: Icon(
                              Icons.cottage_rounded,
                              size: 88,
                              color: dark ? Colors.white : AppColors.navy,
                            ),
                          ),
                          Positioned(
                            bottom: 22,
                            left: 14,
                            child: _GateDoor(
                              isOpen: gate1DoorOpen,
                              color: AppColors.gold,
                              hinge: Alignment.centerRight,
                            ),
                          ),
                          Positioned(
                            bottom: 22,
                            right: 14,
                            child: _GateDoor(
                              isOpen: gate2DoorOpen,
                              color: AppColors.green,
                              hinge: Alignment.centerLeft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Gate Cards
                  _GateCard(
                    title: 'Main Gate',
                    icon: Icons.meeting_room_rounded,
                    isOpen: gate1DoorOpen,
                    isLoading: isGate1Loading,
                    accent: AppColors.gold,
                    dark: dark,
                    onPressed: _triggerMainGate,
                  ),
                  const SizedBox(height: 18),
                  _GateCard(
                    title: 'Internal Gate',
                    icon: Icons.garage_rounded,
                    isOpen: gate2DoorOpen,
                    isLoading: isGate2Loading,
                    accent: AppColors.green,
                    dark: dark,
                    onPressed: _triggerInternalGate,
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

// ================= Helper Widgets =================

class _TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.72);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.82,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.64,
      size.width,
      size.height * 0.86,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.85 + (_controller.value * 0.35);
        final opacity = 0.55 + (_controller.value * 0.45);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GateDoor extends StatelessWidget {
  final bool isOpen;
  final Color color;
  final Alignment hinge;
  const _GateDoor({
    required this.isOpen,
    required this.color,
    required this.hinge,
  });

  @override
  Widget build(BuildContext context) {
    final targetAngle = isOpen
        ? (hinge == Alignment.centerLeft ? 1.15 : -1.15)
        : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: targetAngle),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Transform(
          alignment: hinge,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(value),
          child: child,
        );
      },
      child: Container(
        width: 26,
        height: 58,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(2, 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _GateCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isOpen;
  final bool isLoading;
  final Color accent;
  final bool dark;
  final VoidCallback onPressed;

  const _GateCard({
    required this.title,
    required this.icon,
    required this.isOpen,
    required this.isLoading,
    required this.accent,
    required this.dark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: RotationTransition(turns: anim, child: child),
                ),
                child: Container(
                  key: ValueKey(isOpen),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOpen ? Icons.lock_open_rounded : icon,
                    color: accent,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: dark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOpen ? AppColors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOpen ? 'Open' : 'Closed',
                          style: TextStyle(
                            fontSize: 13,
                            color: dark ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isLoading
                    ? accent.withValues(alpha: 0.6)
                    : accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: isLoading ? null : onPressed,
              child: isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Opening...',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  : const Text(
                      'OPEN GATE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  const _SuccessBanner({required this.message, required this.onDone});

  @override
  State<_SuccessBanner> createState() => _SuccessBannerState();
}

class _SuccessBannerState extends State<_SuccessBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) setState(() => _visible = true);
    });
    Timer(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      setState(() => _visible = false);
      await Future.delayed(const Duration(milliseconds: 300));
      widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, -0.6),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
