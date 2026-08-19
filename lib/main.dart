import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }

  runApp(const SuperLiveSmartHomeApp());
}

// ============================================================================
// THEME
// ============================================================================

class SuperLiveTheme {
  static const BoxDecoration darkCalmGradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF0B0F19),
        Color(0xFF131A2B),
        Color(0xFF1A233A),
        Color(0xFF0F172A),
      ],
      stops: [0.0, 0.4, 0.8, 1.0],
    ),
  );

  static const BoxDecoration lightCalmGradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFF8FAFC),
        Color(0xFFF1F5F9),
        Color(0xFFE2E8F0),
        Color(0xFFCBD5E1),
      ],
      stops: [0.0, 0.4, 0.8, 1.0],
    ),
  );

  static const Color darkBackground = Color(0xFF0B0F19);
  static const Color darkSurface = Color(0xCC1A233A);
  static const Color darkCardBorder = Color(0x4038BDF8);
  static const Color darkCyanAccent = Color(0xFF38BDF8);
  static const Color darkGoldAccent = Color(0xFFEAB308);
  static const Color greenOnline = Color(0xFF10B981);
  static const Color redAlert = Color(0xFFEF4444);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xCCFFFFFF);
  static const Color lightCardBorder = Color(0x400284C7);
  static const Color lightCyanAccent = Color(0xFF0284C7);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
}

PreferredSizeWidget buildCustomHeaderBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  Widget? titleWidget,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xEE1E293B) : const Color(0xEEFFFFFF),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? SuperLiveTheme.darkCardBorder
                : SuperLiveTheme.lightCardBorder,
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black38 : Colors.black12,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child:
                  titleWidget ??
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? SuperLiveTheme.darkTextPrimary
                          : SuperLiveTheme.lightTextPrimary,
                    ),
                  ),
            ),
            ...?actions,
          ],
        ),
      ),
    ),
  );
}

// ============================================================================
// DVR / NVR MODEL
// ============================================================================

class NvrDevice {
  final String id;
  String name;
  String serialNumber;
  String username;
  String password;
  String ip;
  int port;
  int channelCount;
  bool isOnline;
  String rtspPath;

  NvrDevice({
    required this.id,
    required this.name,
    required this.serialNumber,
    required this.username,
    required this.password,
    this.ip = '192.168.1.100',
    this.port = 554,
    this.channelCount = 4,
    this.isOnline = true,
    this.rtspPath = '/ch{channel}/{stream}',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'serialNumber': serialNumber,
    'username': username,
    'password': password,
    'ip': ip,
    'port': port,
    'channelCount': channelCount,
    'isOnline': isOnline,
    'rtspPath': rtspPath,
  };

  factory NvrDevice.fromJson(Map<String, dynamic> json) {
    return NvrDevice(
      id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      name: (json['name'] ?? 'Home DVR').toString(),
      serialNumber: (json['serialNumber'] ?? '').toString(),
      username: (json['username'] ?? 'admin').toString(),
      password: (json['password'] ?? '').toString(),
      ip: (json['ip'] ?? '192.168.1.100').toString(),
      port: _toInt(json['port'], 554),
      channelCount: _toInt(json['channelCount'], 4),
      isOnline: json['isOnline'] is bool ? json['isOnline'] as bool : true,
      rtspPath: (json['rtspPath'] ?? '/ch{channel}/{stream}').toString(),
    );
  }

  static int _toInt(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String getRtspUrl(int channelIndex, {bool isSubStream = true}) {
    final authPart = username.isNotEmpty && password.isNotEmpty
        ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@'
        : '';

    final streamType = isSubStream ? 'sub' : 'main';
    final host = ip.trim().isNotEmpty ? ip.trim() : serialNumber.trim();

    final path = rtspPath
        .replaceAll('{channel}', channelIndex.toString())
        .replaceAll('{stream}', streamType);

    return 'rtsp://$authPart$host:$port$path';
  }
}

// ============================================================================
// APP
// ============================================================================

class SuperLiveSmartHomeApp extends StatefulWidget {
  const SuperLiveSmartHomeApp({super.key});

  static SuperLiveSmartHomeAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<SuperLiveSmartHomeAppState>();
  }

  @override
  State<SuperLiveSmartHomeApp> createState() => SuperLiveSmartHomeAppState();
}

class SuperLiveSmartHomeAppState extends State<SuperLiveSmartHomeApp> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _themeStorageKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    try {
      final savedTheme = await _storage.read(key: _themeStorageKey);

      if (!mounted) return;

      setState(() {
        _themeMode = savedTheme == 'light' ? ThemeMode.light : ThemeMode.dark;
      });
    } catch (e) {
      debugPrint('Error loading saved theme: $e');
    }
  }

  Future<void> toggleTheme(bool isDark) async {
    final newMode = isDark ? ThemeMode.dark : ThemeMode.light;

    setState(() {
      _themeMode = newMode;
    });

    try {
      await _storage.write(
        key: _themeStorageKey,
        value: isDark ? 'dark' : 'light',
      );
    } catch (e) {
      debugPrint('Error saving theme: $e');
    }
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SuperLive Smart Home',
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.light(
          primary: SuperLiveTheme.lightCyanAccent,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: SuperLiveTheme.lightTextPrimary,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: SuperLiveTheme.darkCyanAccent,
          surface: SuperLiveTheme.darkSurface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: SuperLiveTheme.darkTextPrimary,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const AppLockScreen(),
    );
  }
}

// ============================================================================
// LOCK SCREEN
// ============================================================================

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final LocalAuthentication auth = LocalAuthentication();

  static const String _savedPin = '2011';

  bool isBiometricSupported = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();

      final supported = canCheck || isSupported;

      if (!mounted) return;

      setState(() {
        isBiometricSupported = supported;
      });

      if (supported) {
        await _authenticateBiometrics();
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric check error: $e');
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  Future<void> _authenticateBiometrics() async {
    try {
      final ok = await auth.authenticate(
        localizedReason: 'Authenticate to access SuperLive',
      );

      if (ok && mounted) {
        _unlockApp();
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric authentication error: $e');
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
    }
  }

  void _verifyPin() {
    if (_pinController.text == _savedPin) {
      _unlockApp();
    } else {
      setState(() {
        errorMessage = 'Wrong PIN, try again';
      });
      _pinController.clear();
    }
  }

  void _unlockApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigationWrapper()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    final gradientDeco = isDark
        ? SuperLiveTheme.darkCalmGradient
        : SuperLiveTheme.lightCalmGradient;

    return Container(
      decoration: gradientDeco,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: isDark
                          ? SuperLiveTheme.darkSurface
                          : SuperLiveTheme.lightSurface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      color: primaryColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Enter PIN',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? SuperLiveTheme.darkTextPrimary
                          : SuperLiveTheme.lightTextPrimary,
                    ),
                  ),
                  if (errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorMessage,
                        style: const TextStyle(
                          color: SuperLiveTheme.redAlert,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? SuperLiveTheme.darkSurface
                          : SuperLiveTheme.lightSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? SuperLiveTheme.darkCardBorder
                            : SuperLiveTheme.lightCardBorder,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      autofocus: true,
                      style: TextStyle(
                        fontSize: 30,
                        letterSpacing: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? SuperLiveTheme.darkTextPrimary
                            : SuperLiveTheme.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '····',
                        hintStyle: TextStyle(
                          color: isDark
                              ? SuperLiveTheme.darkTextSecondary
                              : SuperLiveTheme.lightTextSecondary,
                          letterSpacing: 12,
                        ),
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        if (errorMessage.isNotEmpty) {
                          setState(() => errorMessage = '');
                        }

                        if (value.length == 4) {
                          _verifyPin();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _verifyPin,
                      child: const Text(
                        'Unlock',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (isBiometricSupported) ...[
                    const SizedBox(height: 14),
                    TextButton.icon(
                      icon: Icon(
                        Icons.fingerprint_rounded,
                        color: primaryColor,
                        size: 22,
                      ),
                      label: Text(
                        'Use Biometrics',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: _authenticateBiometrics,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MAIN NAVIGATION
// ============================================================================

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _storageKey = 'saved_nvr_devices';
  static const String _espStorageKey = 'esp32_ip';

  int _currentIndex = 0;
  String esp32Ip = '192.168.1.50';

  List<NvrDevice> devices = [];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    try {
      final jsonString = await _storage.read(key: _storageKey);
      final savedIp = await _storage.read(key: _espStorageKey);

      if (!mounted) return;

      final loadedDevices = <NvrDevice>[];

      if (jsonString != null && jsonString.isNotEmpty) {
        final decoded = jsonDecode(jsonString);

        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              loadedDevices.add(
                NvrDevice.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      }

      setState(() {
        devices = loadedDevices;
        if (savedIp != null && savedIp.trim().isNotEmpty) {
          esp32Ip = savedIp.trim();
        }
      });
    } catch (e) {
      debugPrint('Error loading saved data: $e');
    }
  }

  Future<void> _saveDevices() async {
    try {
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(devices.map((device) => device.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving devices: $e');
    }
  }

  Future<void> _saveEspIp(String ip) async {
    try {
      await _storage.write(key: _espStorageKey, value: ip);
    } catch (e) {
      debugPrint('Error saving ESP32 IP: $e');
    }
  }

  void _addDevice(NvrDevice device) {
    setState(() => devices.add(device));
    _saveDevices();
  }

  void _updateDevice(NvrDevice device) {
    setState(() {
      final index = devices.indexWhere((d) => d.id == device.id);
      if (index != -1) {
        devices[index] = device;
      }
    });
    _saveDevices();
  }

  void _deleteDevice(String id) {
    setState(() {
      devices.removeWhere((device) => device.id == id);
    });
    _saveDevices();
  }

  void _onSmartScanAddAndOpen(NvrDevice device) {
    setState(() {
      final index = devices.indexWhere(
        (d) => d.serialNumber == device.serialNumber,
      );

      if (index != -1) {
        devices[index] = device;
      } else {
        devices.add(device);
      }

      _currentIndex = 0;
    });

    _saveDevices();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    final gradientDeco = isDark
        ? SuperLiveTheme.darkCalmGradient
        : SuperLiveTheme.lightCalmGradient;

    final pages = [
      SuperLiveViewTab(device: devices.isNotEmpty ? devices.first : null),
      GatesControlTab(esp32Ip: esp32Ip),
      DeviceListTab(
        devices: devices,
        onDeviceAdded: _addDevice,
        onDeviceUpdated: _updateDevice,
        onDeviceDeleted: _deleteDevice,
        onSmartScanAddAndOpen: _onSmartScanAddAndOpen,
      ),
      SettingsTab(
        esp32Ip: esp32Ip,
        onEspIpSaved: (newIp) {
          setState(() => esp32Ip = newIp);
          _saveEspIp(newIp);
        },
      ),
    ];

    return Container(
      decoration: gradientDeco,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(index: _currentIndex, children: pages),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF01E293B) : const Color(0xF0FFFFFF),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? SuperLiveTheme.darkCardBorder
                    : SuperLiveTheme.lightCardBorder,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black54 : Colors.black12,
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            backgroundColor: Colors.transparent,
            selectedItemColor: primaryColor,
            unselectedItemColor: isDark
                ? SuperLiveTheme.darkTextSecondary
                : SuperLiveTheme.lightTextSecondary,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            onTap: (index) {
              setState(() => _currentIndex = index);
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.videocam_outlined),
                activeIcon: Icon(Icons.videocam),
                label: 'Live View',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.sensor_door_outlined),
                activeIcon: Icon(Icons.sensor_door),
                label: 'Gates',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.devices_outlined),
                activeIcon: Icon(Icons.devices),
                label: 'Devices',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LIVE VIEW
// ============================================================================

class SuperLiveViewTab extends StatefulWidget {
  final NvrDevice? device;

  const SuperLiveViewTab({super.key, required this.device});

  @override
  State<SuperLiveViewTab> createState() => _SuperLiveViewTabState();
}

class _SuperLiveViewTabState extends State<SuperLiveViewTab> {
  int gridLayout = 1;
  int selectedChannel = 1;
  int gridPage = 0;
  bool isMuted = true;
  bool isRecording = false;
  bool isIntercomActive = false;
  bool isHdMode = true;

  void _nextChannel(int totalChannels) {
    if (totalChannels <= 0) return;

    setState(() {
      selectedChannel = (selectedChannel % totalChannels) + 1;
    });
  }

  void _prevChannel(int totalChannels) {
    if (totalChannels <= 0) return;

    setState(() {
      selectedChannel =
          (selectedChannel - 2 + totalChannels) % totalChannels + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: buildCustomHeaderBar(
        context,
        title: '',
        titleWidget: Row(
          children: [
            Icon(Icons.videocam_outlined, color: primaryColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                device != null ? '${device.name} (Live)' : 'CCTV Stream',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isHdMode ? Icons.hd_rounded : Icons.sd_rounded,
              color: primaryColor,
            ),
            tooltip: 'HD/SD Quality',
            onPressed: () {
              setState(() => isHdMode = !isHdMode);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.black,
              child: device == null
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_off_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No Camera Device Configured',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        _buildGridPlayerView(device),
                        if (gridLayout == 1) ...[
                          Positioned(
                            left: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black45,
                                ),
                                icon: const Icon(
                                  Icons.chevron_left_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                onPressed: () {
                                  _prevChannel(device.channelCount);
                                },
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black45,
                                ),
                                icon: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                onPressed: () {
                                  _nextChannel(device.channelCount);
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: isDark
                ? SuperLiveTheme.darkSurface
                : SuperLiveTheme.lightSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: Icon(
                    isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: isMuted ? Colors.grey : primaryColor,
                  ),
                  onPressed: () {
                    setState(() => isMuted = !isMuted);
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.mic_rounded,
                    color: isIntercomActive ? primaryColor : Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      isIntercomActive = !isIntercomActive;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.camera_alt_rounded,
                    color: isDark
                        ? Colors.white
                        : SuperLiveTheme.lightTextPrimary,
                  ),
                  onPressed: () {
                    _showMessage(
                      context,
                      'Snapshot button pressed 📸',
                      primaryColor,
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.fiber_manual_record_rounded,
                    color: isRecording ? SuperLiveTheme.redAlert : Colors.grey,
                  ),
                  onPressed: () {
                    setState(() => isRecording = !isRecording);
                    _showMessage(
                      context,
                      isRecording
                          ? 'Recording started 🔴'
                          : 'Recording stopped',
                      isRecording ? SuperLiveTheme.redAlert : primaryColor,
                    );
                  },
                ),
                IconButton(
                  icon: Icon(Icons.fullscreen_rounded, color: primaryColor),
                  onPressed: () {
                    if (device == null) return;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullscreenPlayerModal(
                          cameraName:
                              'Channel $selectedChannel - ${device.name}',
                          rtspUrl: device.getRtspUrl(
                            selectedChannel,
                            isSubStream: false,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark
                ? SuperLiveTheme.darkCardBorder
                : SuperLiveTheme.lightCardBorder,
          ),
          Container(
            color: isDark
                ? SuperLiveTheme.darkSurface
                : SuperLiveTheme.lightSurface,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Grid Layout Switcher',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? SuperLiveTheme.darkTextSecondary
                        : SuperLiveTheme.lightTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildGridModeButton('1x1', 1, primaryColor),
                    const SizedBox(width: 16),
                    _buildGridModeButton('2x2', 4, primaryColor),
                    const SizedBox(width: 16),
                    _buildGridModeButton('3x3', 9, primaryColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildGridModeButton(String label, int mode, Color primaryColor) {
    final isSelected = gridLayout == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        final device = widget.device;
        if (device == null) return;

        setState(() {
          if (gridLayout == mode) {
            final totalPages = (device.channelCount / mode).ceil();

            if (totalPages > 0) {
              gridPage = (gridPage + 1) % totalPages;
            }
          } else {
            gridLayout = mode;
            gridPage = 0;
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.15)
              : (isDark ? Colors.black26 : SuperLiveTheme.lightBackground),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : (isDark
                      ? SuperLiveTheme.darkCardBorder
                      : SuperLiveTheme.lightCardBorder),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? primaryColor : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildGridPlayerView(NvrDevice device) {
    if (gridLayout == 1) {
      return LiveStreamTile(
        channelName: 'Channel $selectedChannel',
        rtspUrl: device.getRtspUrl(selectedChannel, isSubStream: !isHdMode),
      );
    }

    final camerasPerPage = gridLayout;
    final startChannel = (gridPage * camerasPerPage) + 1;
    final remaining = device.channelCount - startChannel + 1;

    final channelsOnPage = remaining > camerasPerPage
        ? camerasPerPage
        : remaining;

    if (channelsOnPage <= 0) {
      return const Center(
        child: Text(
          'No cameras available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final crossCount = gridLayout == 4 ? 2 : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      itemCount: channelsOnPage,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        childAspectRatio: 16 / 9,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        final channelNumber = startChannel + index;

        return LiveStreamTile(
          channelName: 'CH $channelNumber',
          rtspUrl: device.getRtspUrl(channelNumber, isSubStream: true),
        );
      },
    );
  }
}

// ============================================================================
// VLC TILE
// ============================================================================

class LiveStreamTile extends StatefulWidget {
  final String channelName;
  final String rtspUrl;

  const LiveStreamTile({
    super.key,
    required this.channelName,
    required this.rtspUrl,
  });

  @override
  State<LiveStreamTile> createState() => _LiveStreamTileState();
}

class _LiveStreamTileState extends State<LiveStreamTile> {
  late final VlcPlayerController _vlcController;

  @override
  void initState() {
    super.initState();

    final safeUrl = widget.rtspUrl.isNotEmpty
        ? widget.rtspUrl
        : 'rtsp://127.0.0.1:554';

    _vlcController = VlcPlayerController.network(
      safeUrl,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(['--rtsp-tcp', '--network-caching=300']),
      ),
    );
  }

  @override
  void dispose() {
    _vlcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    return Stack(
      fit: StackFit.expand,
      children: [
        VlcPlayer(
          controller: _vlcController,
          aspectRatio: 16 / 9,
          placeholder: Center(
            child: CircularProgressIndicator(
              color: primaryColor,
              strokeWidth: 2,
            ),
          ),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.channelName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FULLSCREEN PLAYER
// ============================================================================

class FullscreenPlayerModal extends StatefulWidget {
  final String cameraName;
  final String rtspUrl;

  const FullscreenPlayerModal({
    super.key,
    required this.cameraName,
    required this.rtspUrl,
  });

  @override
  State<FullscreenPlayerModal> createState() => _FullscreenPlayerModalState();
}

class _FullscreenPlayerModalState extends State<FullscreenPlayerModal> {
  late final VlcPlayerController _vlcController;

  @override
  void initState() {
    super.initState();

    final safeUrl = widget.rtspUrl.isNotEmpty
        ? widget.rtspUrl
        : 'rtsp://127.0.0.1:554';

    _vlcController = VlcPlayerController.network(
      safeUrl,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(['--rtsp-tcp', '--network-caching=300']),
      ),
    );
  }

  @override
  void dispose() {
    _vlcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.cameraName,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: VlcPlayer(
            controller: _vlcController,
            aspectRatio: 16 / 9,
            placeholder: const Center(
              child: CircularProgressIndicator(
                color: SuperLiveTheme.darkCyanAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// GATES
// ============================================================================

class GatesControlTab extends StatefulWidget {
  final String esp32Ip;

  const GatesControlTab({super.key, required this.esp32Ip});

  @override
  State<GatesControlTab> createState() => _GatesControlTabState();
}

class _GatesControlTabState extends State<GatesControlTab> {
  bool isGate1Open = false;
  bool isGate2Open = false;
  bool isGate1Loading = false;
  bool isGate2Loading = false;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    checkConnection();
  }

  @override
  void didUpdateWidget(covariant GatesControlTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.esp32Ip != widget.esp32Ip) {
      checkConnection();
    }
  }

  Future<void> checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('http://${widget.esp32Ip}/'))
          .timeout(const Duration(seconds: 2));

      if (mounted) {
        setState(() {
          isConnected = response.statusCode == 200;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => isConnected = false);
      }
    }
  }

  Future<void> _triggerGate({
    required String firebasePath,
    required String localEndpoint,
    required bool isLoading,
    required void Function(bool open, bool loading) updateState,
  }) async {
    if (isLoading) return;

    setState(() => updateState(true, true));

    final stopwatch = Stopwatch()..start();

    try {
      if (Firebase.apps.isNotEmpty) {
        try {
          await FirebaseDatabase.instance.ref(firebasePath).set(1);
        } catch (e) {
          debugPrint('Firebase write error: $e');
        }
      }

      await sendEspCommand(localEndpoint);
    } finally {
      final elapsedMs = stopwatch.elapsedMilliseconds;
      const targetPulseMs = 500;
      final remainingMs = targetPulseMs - elapsedMs;

      if (remainingMs > 0) {
        await Future.delayed(Duration(milliseconds: remainingMs));
      }

      if (mounted) {
        setState(() => updateState(false, false));
      }
    }
  }

  Future<void> sendEspCommand(String endpoint) async {
    try {
      final response = await http
          .get(Uri.parse('http://${widget.esp32Ip}/$endpoint'))
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      setState(() => isConnected = true);

      _showSnackBar(
        'Command Executed: ${response.body}',
        SuperLiveTheme.greenOnline,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() => isConnected = false);

      final fbActive = Firebase.apps.isNotEmpty;

      _showSnackBar(
        fbActive ? 'Signal sent to Firebase Cloud 🚀' : 'Direct IP unreachable',
        fbActive ? SuperLiveTheme.darkCyanAccent : SuperLiveTheme.redAlert,
      );
    }
  }

  void _showSnackBar(String text, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: buildCustomHeaderBar(context, title: 'Gate Access Controls'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? SuperLiveTheme.darkSurface
                    : SuperLiveTheme.lightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? SuperLiveTheme.darkCardBorder
                      : SuperLiveTheme.lightCardBorder,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? SuperLiveTheme.greenOnline
                          : primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isConnected
                          ? 'Direct Connected (${widget.esp32Ip})'
                          : 'Firebase Cloud Online ⚡',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: primaryColor,
                    ),
                    onPressed: checkConnection,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Manual Gate Triggers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            AnimatedGateCardWidget(
              title: 'Main Entrance Gate',
              icon: Icons.door_front_door_outlined,
              isOpen: isGate1Open,
              onPressed: isGate1Loading
                  ? null
                  : () => _triggerGate(
                      firebasePath: 'gate_status',
                      localEndpoint: 'gate1/open',
                      isLoading: isGate1Loading,
                      updateState: (open, loading) {
                        isGate1Open = open;
                        isGate1Loading = loading;
                      },
                    ),
            ),
            const SizedBox(height: 16),
            AnimatedGateCardWidget(
              title: 'Inside Entrance Gate',
              icon: Icons.sensor_door_outlined,
              isOpen: isGate2Open,
              onPressed: isGate2Loading
                  ? null
                  : () => _triggerGate(
                      firebasePath: 'gate2_status',
                      localEndpoint: 'gate2/open',
                      isLoading: isGate2Loading,
                      updateState: (open, loading) {
                        isGate2Open = open;
                        isGate2Loading = loading;
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedGateCardWidget extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isOpen;
  final VoidCallback? onPressed;

  const AnimatedGateCardWidget({
    super.key,
    required this.title,
    required this.icon,
    required this.isOpen,
    required this.onPressed,
  });

  @override
  State<AnimatedGateCardWidget> createState() => _AnimatedGateCardWidgetState();
}

class _AnimatedGateCardWidgetState extends State<AnimatedGateCardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedGateCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isOpen && !oldWidget.isOpen) {
      _animate();
    }
  }

  Future<void> _animate() async {
    if (!mounted) return;

    try {
      await _animController.forward();
      if (mounted) {
        await _animController.reverse();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    final statusColor = widget.isOpen
        ? SuperLiveTheme.greenOnline
        : SuperLiveTheme.redAlert;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? SuperLiveTheme.darkSurface
                : SuperLiveTheme.lightSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isOpen
                  ? SuperLiveTheme.greenOnline
                  : (isDark
                        ? SuperLiveTheme.darkCardBorder
                        : SuperLiveTheme.lightCardBorder),
              width: widget.isOpen ? 2 : 1,
            ),
            boxShadow: [
              if (widget.isOpen)
                BoxShadow(
                  color: SuperLiveTheme.greenOnline.withValues(
                    alpha: 0.3 * (1 - _animController.value),
                  ),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Transform.translate(
                    offset: Offset(_slideAnimation.value, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.isOpen
                            ? SuperLiveTheme.greenOnline.withValues(alpha: 0.15)
                            : primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.isOpen
                            ? Icons.door_sliding_outlined
                            : widget.icon,
                        size: 32,
                        color: widget.isOpen
                            ? SuperLiveTheme.greenOnline
                            : primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.isOpen ? 'OPENING...' : 'CLOSED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isOpen
                        ? SuperLiveTheme.greenOnline
                        : primaryColor,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: widget.onPressed,
                  child: Text(
                    widget.isOpen ? 'OPENING GATE...' : 'OPEN GATE',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// DEVICE LIST + QR SCANNER
// ============================================================================

class QrScanResult {
  final String raw;
  final String serialNumber;
  final String username;
  final String password;
  final String name;
  final String ip;
  final int? port;

  const QrScanResult({
    required this.raw,
    this.serialNumber = '',
    this.username = '',
    this.password = '',
    this.name = '',
    this.ip = '',
    this.port,
  });

  bool get hasUsefulData =>
      serialNumber.isNotEmpty ||
      username.isNotEmpty ||
      password.isNotEmpty ||
      name.isNotEmpty ||
      ip.isNotEmpty ||
      port != null;
}

class DeviceListTab extends StatelessWidget {
  final List<NvrDevice> devices;
  final ValueChanged<NvrDevice> onDeviceAdded;
  final ValueChanged<NvrDevice> onDeviceUpdated;
  final ValueChanged<String> onDeviceDeleted;
  final ValueChanged<NvrDevice> onSmartScanAddAndOpen;

  const DeviceListTab({
    super.key,
    required this.devices,
    required this.onDeviceAdded,
    required this.onDeviceUpdated,
    required this.onDeviceDeleted,
    required this.onSmartScanAddAndOpen,
  });

  void _showAddOrEditDeviceModal(
    BuildContext context, {
    NvrDevice? existingDevice,
  }) {
    final nameCtrl = TextEditingController(text: existingDevice?.name ?? '');
    final serialCtrl = TextEditingController(
      text: existingDevice?.serialNumber ?? '',
    );
    final userCtrl = TextEditingController(
      text: existingDevice?.username ?? 'admin',
    );
    final passCtrl = TextEditingController(
      text: existingDevice?.password ?? '',
    );
    final ipCtrl = TextEditingController(
      text: existingDevice?.ip ?? '192.168.1.100',
    );
    final portCtrl = TextEditingController(
      text: (existingDevice?.port ?? 554).toString(),
    );
    final rtspPathCtrl = TextEditingController(
      text: existingDevice?.rtspPath ?? '/ch{channel}/{stream}',
    );

    int selectedChannelCount = existingDevice?.channelCount ?? 4;
    bool showAdvanced = false;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF172033) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            existingDevice == null
                                ? 'Add DVR Device'
                                : 'Edit Device',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor.withValues(
                              alpha: 0.15,
                            ),
                            foregroundColor: primaryColor,
                            elevation: 0,
                          ),
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Smart Scan',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () {
                            _openCameraScanner(
                              ctx,
                              onDetected: (result) {
                                setModalState(() {
                                  if (result.name.isNotEmpty) {
                                    nameCtrl.text = result.name;
                                  }
                                  if (result.serialNumber.isNotEmpty) {
                                    serialCtrl.text = result.serialNumber;
                                  }
                                  if (result.username.isNotEmpty) {
                                    userCtrl.text = result.username;
                                  }
                                  if (result.password.isNotEmpty) {
                                    passCtrl.text = result.password;
                                  }
                                  if (result.ip.isNotEmpty) {
                                    ipCtrl.text = result.ip;
                                  }
                                  if (result.port != null) {
                                    portCtrl.text = result.port.toString();
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Device Name',
                        hintText: 'Home DVR',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: serialCtrl,
                      decoration: InputDecoration(
                        labelText: 'Serial Number / P2P ID',
                        hintText: 'e.g. HIK884920193',
                        prefixIcon: const Icon(Icons.qr_code_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.qr_code_scanner_rounded,
                            color: primaryColor,
                          ),
                          onPressed: () {
                            _openCameraScanner(
                              ctx,
                              onDetected: (result) {
                                setModalState(() {
                                  if (result.name.isNotEmpty) {
                                    nameCtrl.text = result.name;
                                  }
                                  if (result.serialNumber.isNotEmpty) {
                                    serialCtrl.text = result.serialNumber;
                                  }
                                  if (result.username.isNotEmpty) {
                                    userCtrl.text = result.username;
                                  }
                                  if (result.password.isNotEmpty) {
                                    passCtrl.text = result.password;
                                  }
                                  if (result.ip.isNotEmpty) {
                                    ipCtrl.text = result.ip;
                                  }
                                  if (result.port != null) {
                                    portCtrl.text = result.port.toString();
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: userCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: passCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 🌟 اختيار عدد الكاميرات بالخارج بأسلوب منظم وسهل 🌟
                    DropdownButtonFormField<int>(
                      initialValue:
                          [
                            1,
                            2,
                            4,
                            8,
                            16,
                            32,
                            64,
                          ].contains(selectedChannelCount)
                          ? selectedChannelCount
                          : 4,
                      decoration: const InputDecoration(
                        labelText: 'Number of Channels / عدد الكاميرات',
                        prefixIcon: Icon(Icons.videocam_outlined),
                      ),
                      dropdownColor: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      items: const [
                        DropdownMenuItem(
                          value: 1,
                          child: Text('1 Channel (1 كاميرا)'),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text('2 Channels (2 كاميرا)'),
                        ),
                        DropdownMenuItem(
                          value: 4,
                          child: Text('4 Channels (4 كاميرات)'),
                        ),
                        DropdownMenuItem(
                          value: 8,
                          child: Text('8 Channels (8 كاميرات)'),
                        ),
                        DropdownMenuItem(
                          value: 16,
                          child: Text('16 Channels (16 كاميرا)'),
                        ),
                        DropdownMenuItem(
                          value: 32,
                          child: Text('32 Channels (32 كاميرا)'),
                        ),
                        DropdownMenuItem(
                          value: 64,
                          child: Text('64 Channels (64 كاميرا)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedChannelCount = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        setModalState(() {
                          showAdvanced = !showAdvanced;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              color: primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Advanced Settings (IP, Port, Path)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              showAdvanced
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showAdvanced) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: ipCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Local IP / Host',
                          hintText: '192.168.1.100',
                          prefixIcon: Icon(Icons.router_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: portCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'RTSP Port',
                          hintText: '554',
                          prefixIcon: Icon(Icons.settings_ethernet),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: rtspPathCtrl,
                        decoration: const InputDecoration(
                          labelText: 'RTSP Path',
                          hintText: '/ch{channel}/{stream}',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Advanced RTSP settings. Use {channel} and {stream} in the path.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          if (nameCtrl.text.trim().isEmpty &&
                              serialCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Enter a Device Name or Serial Number first.',
                                ),
                              ),
                            );
                            return;
                          }

                          final dev = NvrDevice(
                            id:
                                existingDevice?.id ??
                                DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                            name: nameCtrl.text.trim().isNotEmpty
                                ? nameCtrl.text.trim()
                                : 'Home DVR',
                            serialNumber: serialCtrl.text.trim(),
                            username: userCtrl.text.trim(),
                            password: passCtrl.text.trim(),
                            ip: ipCtrl.text.trim().isNotEmpty
                                ? ipCtrl.text.trim()
                                : '192.168.1.100',
                            port: int.tryParse(portCtrl.text.trim()) ?? 554,
                            channelCount: selectedChannelCount,
                            rtspPath: rtspPathCtrl.text.trim().isNotEmpty
                                ? rtspPathCtrl.text.trim()
                                : '/ch{channel}/{stream}',
                          );

                          if (existingDevice == null) {
                            onDeviceAdded(dev);
                          } else {
                            onDeviceUpdated(dev);
                          }

                          Navigator.pop(ctx);
                        },
                        child: Text(
                          existingDevice == null
                              ? 'SAVE DEVICE'
                              : 'UPDATE DEVICE',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openCameraScanner(
    BuildContext context, {
    required ValueChanged<QrScanResult> onDetected,
  }) {
    bool handled = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: 560,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan DVR QR / Barcode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Point the camera at the QR code shown by the DVR/NVR.',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          onDetect: (capture) {
                            if (handled) return;

                            for (final barcode in capture.barcodes) {
                              final raw = barcode.rawValue?.trim() ?? '';
                              if (raw.isEmpty) continue;

                              final result = _parseQrData(raw);

                              if (!result.hasUsefulData) {
                                handled = true;
                                Navigator.pop(ctx);
                                if (context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (dialogCtx) => AlertDialog(
                                      title: const Text(
                                        'QR scanned, but format is not recognized',
                                      ),
                                      content: SelectableText(
                                        raw,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return;
                              }

                              handled = true;
                              onDetected(result);
                              Navigator.pop(ctx);

                              if (context.mounted) {
                                final found = <String>[];
                                if (result.serialNumber.isNotEmpty) {
                                  found.add('S/N');
                                }
                                if (result.username.isNotEmpty) {
                                  found.add('User');
                                }
                                if (result.password.isNotEmpty) {
                                  found.add('Password');
                                }
                                if (result.name.isNotEmpty) found.add('Name');

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'QR scanned successfully: ${found.join(', ')}',
                                    ),
                                    backgroundColor: SuperLiveTheme.greenOnline,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                              return;
                            }
                          },
                        ),
                        Center(
                          child: Container(
                            width: 250,
                            height: 180,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: SuperLiveTheme.darkCyanAccent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'SuperLive QR codes normally provide the serial number and user. Password and device name can stay manual.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openSmartScanAndJump(BuildContext context) {
    _openCameraScanner(
      context,
      onDetected: (result) {
        final device = NvrDevice(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result.name.isNotEmpty ? result.name : 'Home DVR',
          serialNumber: result.serialNumber,
          username: result.username.isNotEmpty ? result.username : 'admin',
          password: result.password,
          ip: result.ip.isNotEmpty ? result.ip : '192.168.1.100',
          port: result.port ?? 554,
          channelCount: 4,
        );

        onSmartScanAddAndOpen(device);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Device ${device.serialNumber.isNotEmpty ? device.serialNumber : device.name} scanned. Opening Live View 📹',
            ),
            backgroundColor: SuperLiveTheme.greenOnline,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _confirmDeleteDevice(BuildContext context, NvrDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Device?'),
        content: Text('Are you sure you want to remove "${device.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: SuperLiveTheme.redAlert,
            ),
            onPressed: () {
              onDeviceDeleted(device.id);
              Navigator.pop(ctx);
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  QrScanResult _parseQrData(String rawQrData) {
    final raw = rawQrData.trim();

    String serial = '';
    String username = '';
    String password = '';
    String name = '';
    String ip = '';
    int? port;

    void assign(String key, String value) {
      final k = key.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
      final v = Uri.decodeComponent(value.trim());
      if (v.isEmpty) return;

      if ([
        'sn',
        'serial',
        'serialnumber',
        'serialno',
        'deviceid',
        'device',
        'server',
        'mac',
        'macaddress',
        'p2pid',
        'p2p',
      ].contains(k)) {
        if (serial.isEmpty) serial = v;
      } else if ([
        'user',
        'username',
        'userid',
        'account',
        'admin',
      ].contains(k)) {
        if (username.isEmpty) username = v;
      } else if (['pass', 'password', 'pwd'].contains(k)) {
        if (password.isEmpty) password = v;
      } else if ([
        'name',
        'devicename',
        'devname',
        'nickname',
        'nick',
        'title',
      ].contains(k)) {
        if (name.isEmpty) name = v;
      } else if (['ip', 'host', 'hostname', 'address'].contains(k)) {
        if (ip.isEmpty) ip = v;
      } else if (['port', 'rtspport'].contains(k)) {
        port ??= int.tryParse(v);
      }
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (value != null) assign(key.toString(), value.toString());
        });
      }
    } catch (_) {}

    if (raw.contains('<') && raw.contains('>')) {
      const tags = [
        'sn',
        'serial',
        'serialNumber',
        'serialno',
        'deviceid',
        'device',
        'server',
        'mac',
        'user',
        'username',
        'admin',
        'pass',
        'password',
        'pwd',
        'name',
        'deviceName',
        'devname',
        'nickname',
        'ip',
        'host',
        'port',
      ];

      for (final tag in tags) {
        final match = RegExp(
          '<$tag[^>]*>(.*?)</$tag>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(raw);

        if (match?.group(1) != null) {
          assign(tag, match!.group(1)!);
        }
      }
    }

    final queryParts = raw.replaceAll('?', '&').split(RegExp(r'[&;\n,]'));
    for (final part in queryParts) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        assign(part.substring(0, eq), part.substring(eq + 1));
      }
    }

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      for (final entry in uri.queryParameters.entries) {
        assign(entry.key, entry.value);
      }
    }

    if (serial.isEmpty && _looksLikeDeviceId(raw)) {
      serial = raw;
    }

    return QrScanResult(
      raw: raw,
      serialNumber: serial.trim(),
      username: username.trim(),
      password: password.trim(),
      name: name.trim(),
      ip: ip.trim(),
      port: port,
    );
  }

  bool _looksLikeDeviceId(String value) {
    final v = value.trim();

    if (v.isEmpty || v.length > 64) return false;
    if (v.startsWith('http://') || v.startsWith('https://')) return false;
    if (v.contains(' ') || v.contains('\n') || v.contains('\r')) return false;

    if (RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$').hasMatch(v)) {
      return true;
    }

    return RegExp(r'^[A-Za-z0-9._:\-]{6,64}$').hasMatch(v);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: buildCustomHeaderBar(
        context,
        title: 'Device List (NVR / DVR)',
        actions: [
          IconButton(
            icon: Icon(
              Icons.qr_code_scanner_rounded,
              color: primaryColor,
              size: 24,
            ),
            tooltip: 'Instant Smart QR Scan',
            onPressed: () => _openSmartScanAndJump(context),
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, color: primaryColor, size: 26),
            onPressed: () => _showAddOrEditDeviceModal(context),
          ),
        ],
      ),
      body: devices.isEmpty
          ? const Center(
              child: Text(
                'No DVR/NVR devices yet.\nPress + or scan a QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: devices.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final device = devices[index];

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? SuperLiveTheme.darkSurface
                        : SuperLiveTheme.lightSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? SuperLiveTheme.darkCardBorder
                          : SuperLiveTheme.lightCardBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.dns_rounded,
                          color: primaryColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: InkWell(
                          onTap: () => _showAddOrEditDeviceModal(
                            context,
                            existingDevice: device,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'S/N: ${device.serialNumber.isNotEmpty ? device.serialNumber : '-'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? SuperLiveTheme.darkTextSecondary
                                      : SuperLiveTheme.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'IP: ${device.ip}:${device.port} • ${device.channelCount} CH',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? SuperLiveTheme.darkTextSecondary
                                      : SuperLiveTheme.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.edit_rounded,
                          color: primaryColor,
                          size: 20,
                        ),
                        onPressed: () => _showAddOrEditDeviceModal(
                          context,
                          existingDevice: device,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: SuperLiveTheme.redAlert,
                          size: 20,
                        ),
                        onPressed: () => _confirmDeleteDevice(context, device),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================================
// SETTINGS
// ============================================================================

class SettingsTab extends StatefulWidget {
  final String esp32Ip;
  final ValueChanged<String> onEspIpSaved;

  const SettingsTab({
    super.key,
    required this.esp32Ip,
    required this.onEspIpSaved,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController espController;

  @override
  void initState() {
    super.initState();
    espController = TextEditingController(text: widget.esp32Ip);
  }

  @override
  void didUpdateWidget(covariant SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.esp32Ip != widget.esp32Ip &&
        espController.text != widget.esp32Ip) {
      espController.text = widget.esp32Ip;
    }
  }

  @override
  void dispose() {
    espController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = SuperLiveSmartHomeApp.of(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: buildCustomHeaderBar(context, title: 'System Settings'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'App Theme Mode',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? SuperLiveTheme.darkSurface
                    : SuperLiveTheme.lightSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? SuperLiveTheme.darkCardBorder
                      : SuperLiveTheme.lightCardBorder,
                ),
              ),
              child: SwitchListTile(
                activeThumbColor: primaryColor,
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: primaryColor,
                ),
                title: Text(
                  isDark
                      ? 'Dark Theme (الوضع الداكن)'
                      : 'Light Theme (الوضع الفاتح)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  isDark
                      ? 'Calm charcoal dark UI active'
                      : 'Soft pearl light UI active',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                value: isDark,
                onChanged: (value) {
                  appState?.toggleTheme(value);
                },
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'ESP32 Local Gateway IP',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: espController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: '192.168.1.50',
                filled: true,
                fillColor: isDark
                    ? SuperLiveTheme.darkSurface
                    : SuperLiveTheme.lightSurface,
                prefixIcon: Icon(Icons.router_outlined, color: primaryColor),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: primaryColor),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final ip = espController.text.trim();

                  if (ip.isEmpty) return;

                  widget.onEspIpSaved(ip);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ESP32 IP Updated Successfully!'),
                      backgroundColor: SuperLiveTheme.greenOnline,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text(
                  'SAVE GATEWAY IP',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
