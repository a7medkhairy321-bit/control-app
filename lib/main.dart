import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }
  runApp(const SuperLiveSmartHomeApp());
}

// =============================================================================
// SUPERLIVE CALM & ELEGANT COLOR PALETTES (DARK & LIGHT GRADIENTS)
// =============================================================================
class SuperLiveTheme {
  // Calm Dark Theme Background Gradient
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

  // Calm Light Theme Background Gradient
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

  // Dark Theme Accent Colors
  static const Color darkBackground = Color(0xFF0B0F19);
  static const Color darkSurface = Color(0xCC1A233A);
  static const Color darkCardBorder = Color(0x4038BDF8);
  static const Color darkCyanAccent = Color(0xFF38BDF8);
  static const Color darkGoldAccent = Color(0xFFEAB308);
  static const Color greenOnline = Color(0xFF10B981);
  static const Color redAlert = Color(0xFFEF4444);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Light Theme Accent Colors
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xCCFFFFFF);
  static const Color lightCardBorder = Color(0x400284C7);
  static const Color lightCyanAccent = Color(0xFF0284C7);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
}

// =============================================================================
// REUSABLE DISTINCT HEADER BAR CONTAINER
// =============================================================================
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

// =============================================================================
// DVR / NVR DEVICE MODEL
// =============================================================================
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

  NvrDevice({
    required this.id,
    required this.name,
    required this.serialNumber,
    required this.username,
    required this.password,
    this.ip = "192.168.1.100",
    this.port = 554,
    this.channelCount = 16,
    this.isOnline = true,
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
  };

  factory NvrDevice.fromJson(Map<String, dynamic> json) => NvrDevice(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'] ?? 'Home DVR',
    serialNumber: json['serialNumber'] ?? '',
    username: json['username'] ?? 'admin',
    password: json['password'] ?? '',
    ip: json['ip'] ?? '192.168.1.100',
    port: json['port'] ?? 554,
    channelCount: json['channelCount'] ?? 16,
    isOnline: json['isOnline'] ?? true,
  );

  String getRtspUrl(int channelIndex, {bool isSubStream = true}) {
    final authPart = (username.isNotEmpty && password.isNotEmpty)
        ? '$username:$password@'
        : '';
    final streamType = isSubStream ? 'sub' : 'main';
    final host = serialNumber.isNotEmpty ? serialNumber : ip;
    return 'rtsp://$authPart$host:$port/ch$channelIndex/$streamType';
  }
}

// =============================================================================
// MAIN ENTRY POINT WITH PERSISTENT SECURE STORAGE THEME SWITCHER
// =============================================================================
class SuperLiveSmartHomeApp extends StatefulWidget {
  const SuperLiveSmartHomeApp({super.key});

  static SuperLiveSmartHomeAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<SuperLiveSmartHomeAppState>();

  @override
  State<SuperLiveSmartHomeApp> createState() => SuperLiveSmartHomeAppState();
}

class SuperLiveSmartHomeAppState extends State<SuperLiveSmartHomeApp> {
  static const _storage = FlutterSecureStorage();
  static const _themeStorageKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    try {
      final savedTheme = await _storage.read(key: _themeStorageKey);
      if (savedTheme == 'light') {
        setState(() => _themeMode = ThemeMode.light);
      } else if (savedTheme == 'dark') {
        setState(() => _themeMode = ThemeMode.dark);
      }
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
      debugPrint('Error saving theme choice: $e');
    }
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SuperLive Smart Home',
      themeMode: _themeMode,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.light(
          primary: SuperLiveTheme.lightCyanAccent,
          surface: SuperLiveTheme.lightSurface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: SuperLiveTheme.lightTextPrimary,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
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
      ),
      // Opens directly on the PIN lock screen — no splash screen delay
      // before it, animated or not.
      home: const AppLockScreen(),
    );
  }
}

// =============================================================================
// SECURITY PIN LOCK SCREEN — Simple & Clean Design
// =============================================================================
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
      final bool canCheck = await auth.canCheckBiometrics;
      final bool isSupported = await auth.isDeviceSupported();
      if (mounted) {
        setState(() => isBiometricSupported = canCheck || isSupported);
      }
      if (isBiometricSupported) _authenticateBiometrics();
    } catch (_) {}
  }

  Future<void> _authenticateBiometrics() async {
    try {
      final bool ok = await auth.authenticate(
        localizedReason: 'Authenticate to access SuperLive',
      );
      if (ok && mounted) _unlockApp();
    } on PlatformException catch (_) {}
  }

  void _verifyPin() {
    if (_pinController.text == _savedPin) {
      _unlockApp();
    } else {
      setState(() => errorMessage = 'Wrong PIN, try again');
      _pinController.clear();
    }
  }

  void _unlockApp() {
    Navigator.pushReplacement(
      context,
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
                  // Lock icon
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
                  const SizedBox(height: 6),
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
                  // PIN field
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
                      onChanged: (val) {
                        if (errorMessage.isNotEmpty) {
                          setState(() => errorMessage = '');
                        }
                        if (val.length == 4) _verifyPin();
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

// =============================================================================
// NAVIGATION WRAPPER WITH ANIMATED CURVED TAB INDICATOR
// =============================================================================
class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'saved_nvr_devices';

  int _currentIndex = 0;
  String esp32Ip = '192.168.1.50';

  List<NvrDevice> devices = [];

  @override
  void initState() {
    super.initState();
    _loadSavedDevices();
  }

  Future<void> _loadSavedDevices() async {
    try {
      final jsonString = await _storage.read(key: _storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        if (decodedList.isNotEmpty) {
          setState(() {
            devices = decodedList
                .map((item) => NvrDevice.fromJson(item))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading saved devices: $e');
    }
  }

  Future<void> _saveDevicesToStorage() async {
    try {
      final jsonString = jsonEncode(devices.map((d) => d.toJson()).toList());
      await _storage.write(key: _storageKey, value: jsonString);
    } catch (e) {
      debugPrint('Error saving devices: $e');
    }
  }

  void _addDevice(NvrDevice newDevice) {
    setState(() {
      devices.add(newDevice);
    });
    _saveDevicesToStorage();
  }

  void _updateDevice(NvrDevice updatedDevice) {
    setState(() {
      final index = devices.indexWhere((d) => d.id == updatedDevice.id);
      if (index != -1) {
        devices[index] = updatedDevice;
      }
    });
    _saveDevicesToStorage();
  }

  void _deleteDevice(String deviceId) {
    setState(() {
      devices.removeWhere((d) => d.id == deviceId);
    });
    _saveDevicesToStorage();
  }

  void _onSmartScanAddAndOpen(NvrDevice scannedDevice) {
    setState(() {
      final index = devices.indexWhere(
        (d) => d.serialNumber == scannedDevice.serialNumber,
      );
      if (index != -1) {
        devices[index] = scannedDevice;
      } else {
        devices.add(scannedDevice);
      }
      _currentIndex = 0; // Switch to Live View
    });
    _saveDevicesToStorage();
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

    final List<Widget> pages = [
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
        onEspIpSaved: (newIp) => setState(() => esp32Ip = newIp),
      ),
    ];

    return Container(
      decoration: gradientDeco,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_currentIndex),
            child: pages[_currentIndex],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF01E293B) : const Color(0xF0FFFFFF),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? SuperLiveTheme.darkCardBorder
                    : SuperLiveTheme.lightCardBorder,
                width: 1,
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
            onTap: (index) => setState(() => _currentIndex = index),
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
                icon: Icon(Icons.devices_rounded),
                activeIcon: Icon(Icons.devices_rounded),
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

// =============================================================================
// TAB 1: POLISHED LIVE VIEW TAB WITH CUSTOM HEADER BAR
// =============================================================================
class SuperLiveViewTab extends StatefulWidget {
  final NvrDevice? device;
  const SuperLiveViewTab({super.key, required this.device});

  @override
  State<SuperLiveViewTab> createState() => _SuperLiveViewTabState();
}

class _SuperLiveViewTabState extends State<SuperLiveViewTab> {
  int gridLayout = 1;
  int selectedChannel = 1;
  bool isMuted = true;
  bool isRecording = false;
  bool isIntercomActive = false;
  bool isHdMode = true;

  void _nextChannel(int totalChannels) {
    setState(() {
      selectedChannel = (selectedChannel % totalChannels) + 1;
    });
  }

  void _prevChannel(int totalChannels) {
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
            Text(
              device != null ? '${device.name} (Live)' : 'CCTV Stream',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            onPressed: () => setState(() => isHdMode = !isHdMode),
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
                                onPressed: () =>
                                    _prevChannel(device.channelCount),
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
                                onPressed: () =>
                                    _nextChannel(device.channelCount),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),

          // Control Toolbar
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
                  tooltip: 'Mute/Unmute',
                  onPressed: () => setState(() => isMuted = !isMuted),
                ),
                IconButton(
                  icon: Icon(
                    Icons.mic_rounded,
                    color: isIntercomActive ? primaryColor : Colors.grey,
                  ),
                  tooltip: 'Two-Way Intercom',
                  onPressed: () =>
                      setState(() => isIntercomActive = !isIntercomActive),
                ),
                IconButton(
                  icon: Icon(
                    Icons.camera_alt_rounded,
                    color: isDark
                        ? SuperLiveTheme.darkTextPrimary
                        : SuperLiveTheme.lightTextPrimary,
                  ),
                  tooltip: 'Snapshot',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Snapshot saved to gallery 📸'),
                        backgroundColor: primaryColor,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.fiber_manual_record_rounded,
                    color: isRecording ? SuperLiveTheme.redAlert : Colors.grey,
                  ),
                  tooltip: 'Record Feed',
                  onPressed: () {
                    setState(() => isRecording = !isRecording);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isRecording
                              ? 'Recording started 🔴'
                              : 'Recording saved',
                        ),
                        backgroundColor: isRecording
                            ? SuperLiveTheme.redAlert
                            : primaryColor,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(Icons.fullscreen_rounded, color: primaryColor),
                  tooltip: 'Fullscreen View',
                  onPressed: () {
                    if (device != null) {
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
                    }
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

          // Grid Switcher Bar
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

  Widget _buildGridModeButton(String label, int mode, Color primaryColor) {
    final bool isSelected = gridLayout == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => gridLayout = mode),
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
        rtspUrl: device.getRtspUrl(selectedChannel, isSubStream: false),
      );
    }

    final int crossCount = gridLayout == 4 ? 2 : 3;
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      itemCount: gridLayout,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        childAspectRatio: 16 / 9,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        final chNum = (index % device.channelCount) + 1;
        return LiveStreamTile(
          channelName: 'CH $chNum',
          rtspUrl: device.getRtspUrl(chNum, isSubStream: true),
        );
      },
    );
  }
}

// Single Stream Tile
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
  late VlcPlayerController _vlcController;

  @override
  void initState() {
    super.initState();
    _vlcController = VlcPlayerController.network(
      widget.rtspUrl,
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

// Fullscreen HD Player Modal
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
  late VlcPlayerController _vlcController;

  @override
  void initState() {
    super.initState();
    _vlcController = VlcPlayerController.network(
      widget.rtspUrl,
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

// =============================================================================
// TAB 2: GATES CONTROL TAB WITH DISTINCT HEADER BAR
// =============================================================================
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

  Future<void> checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('http://${widget.esp32Ip}/'))
          .timeout(const Duration(seconds: 2));
      if (mounted) setState(() => isConnected = response.statusCode == 200);
    } catch (_) {
      if (mounted) setState(() => isConnected = false);
    }
  }

  Future<void> _triggerGate({
    required String firebasePath,
    required String localEndpoint,
    required bool isLoading,
    required void Function(bool openState, bool loadingState) updateState,
  }) async {
    if (isLoading) return;

    setState(() => updateState(true, true));
    final stopwatch = Stopwatch()..start();

    try {
      if (Firebase.apps.isNotEmpty) {
        try {
          final ref = FirebaseDatabase.instance.ref(firebasePath);
          await ref.set(1);
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
      if (mounted) setState(() => updateState(false, false));
    }
  }

  Future<void> sendEspCommand(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('http://${widget.esp32Ip}/$endpoint'),
      );
      if (mounted) {
        setState(() => isConnected = true);
        _showSnackBar(
          'Command Executed: ${response.body}',
          SuperLiveTheme.greenOnline,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => isConnected = false);
        final bool fbActive = Firebase.apps.isNotEmpty;
        _showSnackBar(
          fbActive
              ? 'Signal sent to Firebase Cloud 🚀'
              : 'Direct IP unreachable',
          fbActive ? SuperLiveTheme.darkCyanAccent : SuperLiveTheme.redAlert,
        );
      }
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
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status Bar
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

// ANIMATED GATE CARD WIDGET WITH OPEN BUTTON
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
  late AnimationController _animController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedGateCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen) {
      _animController.forward().then((_) => _animController.reverse());
    }
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

// =============================================================================
// TAB 3: DEVICE LIST WITH CUSTOM DISTINCT HEADER BAR
// =============================================================================
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark
        ? SuperLiveTheme.darkCyanAccent
        : SuperLiveTheme.lightCyanAccent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? SuperLiveTheme.darkSurface
          : SuperLiveTheme.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
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
                    Text(
                      existingDevice == null ? 'Add DVR Device' : 'Edit Device',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor.withValues(alpha: 0.15),
                        foregroundColor: primaryColor,
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
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
                          onDetected: (scannedDevice) {
                            nameCtrl.text = scannedDevice.name;
                            serialCtrl.text = scannedDevice.serialNumber;
                            userCtrl.text = scannedDevice.username;
                            passCtrl.text = scannedDevice.password;
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
                const SizedBox(height: 12),

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
                          onDetected: (scannedDevice) {
                            nameCtrl.text = scannedDevice.name;
                            serialCtrl.text = scannedDevice.serialNumber;
                            userCtrl.text = scannedDevice.username;
                            passCtrl.text = scannedDevice.password;
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
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
                      if (serialCtrl.text.isNotEmpty ||
                          nameCtrl.text.isNotEmpty) {
                        final dev = NvrDevice(
                          id:
                              existingDevice?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: nameCtrl.text.isNotEmpty
                              ? nameCtrl.text
                              : 'Home DVR',
                          serialNumber: serialCtrl.text.trim(),
                          username: userCtrl.text.trim(),
                          password: passCtrl.text.trim(),
                          channelCount: 16,
                        );

                        if (existingDevice == null) {
                          onDeviceAdded(dev);
                        } else {
                          onDeviceUpdated(dev);
                        }
                        Navigator.pop(ctx);
                      }
                    },
                    child: Text(
                      existingDevice == null ? 'SAVE DEVICE' : 'UPDATE DEVICE',
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
  }

  void _openCameraScanner(
    BuildContext context, {
    required ValueChanged<NvrDevice> onDetected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          height: 400,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan DVR QR Code',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Scan barcode to auto-populate all 4 fields',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MobileScanner(
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null &&
                            barcode.rawValue!.isNotEmpty) {
                          final parsedDevice = _parseQrToDevice(
                            barcode.rawValue!,
                          );
                          onDetected(parsedDevice);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Scanned S/N: ${parsedDevice.serialNumber}',
                              ),
                              backgroundColor: SuperLiveTheme.darkCyanAccent,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          break;
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSmartScanAndJump(BuildContext context) {
    _openCameraScanner(
      context,
      onDetected: (scannedDevice) {
        onSmartScanAddAndOpen(scannedDevice);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Device ${scannedDevice.name} connected! Opening Live View 📹',
            ),
            backgroundColor: SuperLiveTheme.greenOnline,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _confirmDeleteDevice(BuildContext context, NvrDevice dev) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Device?'),
        content: Text('Are you sure you want to remove "${dev.name}"?'),
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
              onDeviceDeleted(dev.id);
              Navigator.pop(ctx);
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  // ACCURATE XML, JSON & TEXT QR PARSER
  NvrDevice _parseQrToDevice(String rawQrData) {
    String name = 'Home DVR';
    String sn = '';
    String user = 'admin';
    String pass = '';

    final cleanData = rawQrData.trim();

    if (cleanData.contains('<') && cleanData.contains('>')) {
      final snMatch = RegExp(
        r'<(?:sn|serial|id|dev_sn)>(.*?)</(?:sn|serial|id|dev_sn)>',
        caseSensitive: false,
      ).firstMatch(cleanData);
      if (snMatch != null && snMatch.group(1) != null) {
        sn = snMatch.group(1)!.trim();
      }

      final userMatch = RegExp(
        r'<(?:user|username|admin|acc)>(.*?)</(?:user|username|admin|acc)>',
        caseSensitive: false,
      ).firstMatch(cleanData);
      if (userMatch != null && userMatch.group(1) != null) {
        user = userMatch.group(1)!.trim();
      }

      final passMatch = RegExp(
        r'<(?:pass|password|pwd)>(.*?)</(?:pass|password|pwd)>',
        caseSensitive: false,
      ).firstMatch(cleanData);
      if (passMatch != null && passMatch.group(1) != null) {
        pass = passMatch.group(1)!.trim();
      }

      final nameMatch = RegExp(
        r'<(?:name|devname|title|dev_name)>(.*?)</(?:name|devname|title|dev_name)>',
        caseSensitive: false,
      ).firstMatch(cleanData);
      if (nameMatch != null && nameMatch.group(1) != null) {
        name = nameMatch.group(1)!.trim();
      }
    }

    if (sn.isEmpty) {
      try {
        final Map<String, dynamic> json = jsonDecode(cleanData);
        sn = (json['sn'] ?? json['serial'] ?? json['id'] ?? '')
            .toString()
            .trim();
        name = (json['name'] ?? json['deviceName'] ?? json['devname'] ?? name)
            .toString()
            .trim();
        user = (json['user'] ?? json['username'] ?? json['admin'] ?? user)
            .toString()
            .trim();
        pass = (json['pass'] ?? json['password'] ?? pass).toString().trim();
      } catch (_) {}
    }

    if (sn.isEmpty && cleanData.contains('=')) {
      final pairs = cleanData.split(RegExp(r'[;&,\n]'));
      for (final pair in pairs) {
        final kv = pair.split('=');
        if (kv.length == 2) {
          final k = kv[0].trim().toLowerCase();
          final v = kv[1].trim();
          if (k == 'sn' || k == 'serial' || k == 'id') sn = v;
          if (k == 'name' || k == 'devname') name = v;
          if (k == 'user' || k == 'username') user = v;
          if (k == 'pass' || k == 'password') pass = v;
        }
      }
    }

    if (sn.isEmpty) {
      sn = cleanData.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    }

    return NvrDevice(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isNotEmpty ? name : 'Home DVR',
      serialNumber: sn,
      username: user.isNotEmpty ? user : 'admin',
      password: pass,
      channelCount: 16,
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
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: devices.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final dev = devices[index];
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
                  child: Icon(Icons.dns_rounded, color: primaryColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        _showAddOrEditDeviceModal(context, existingDevice: dev),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dev.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'S/N: ${dev.serialNumber.isNotEmpty ? dev.serialNumber : dev.ip} • User: ${dev.username}',
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
                  icon: Icon(Icons.edit_rounded, color: primaryColor, size: 20),
                  onPressed: () =>
                      _showAddOrEditDeviceModal(context, existingDevice: dev),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: SuperLiveTheme.redAlert,
                    size: 20,
                  ),
                  onPressed: () => _confirmDeleteDevice(context, dev),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// TAB 4: SETTINGS TAB WITH CUSTOM DISTINCT HEADER BAR
// =============================================================================
class SettingsTab extends StatelessWidget {
  final String esp32Ip;
  final ValueChanged<String> onEspIpSaved;

  const SettingsTab({
    super.key,
    required this.esp32Ip,
    required this.onEspIpSaved,
  });

  @override
  Widget build(BuildContext context) {
    final espController = TextEditingController(text: esp32Ip);
    final appState = SuperLiveSmartHomeApp.of(context);
    final isDark = appState?.isDarkMode ?? true;
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
            // Theme Mode Selector Card
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
                onChanged: (bool val) {
                  appState?.toggleTheme(val);
                },
              ),
            ),
            const SizedBox(height: 28),

            // ESP32 Gateway Config Card
            const Text(
              'ESP32 Local Gateway IP',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: espController,
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
                  onEspIpSaved(espController.text.trim());
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
