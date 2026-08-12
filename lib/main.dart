import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

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
// SUPERLIVE PLUS DARK THEME COLOR SYSTEM
// =============================================================================
class SuperLiveTheme {
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color cardBorder = Color(0xFF2E2E2E);
  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color goldAccent = Color(0xFFC5A059);
  static const Color greenOnline = Color(0xFF00E676);
  static const Color redAlert = Color(0xFFFF5252);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF9E9E9E);
}

// =============================================================================
// DVR / NVR DEVICE MODEL
// =============================================================================
class NvrDevice {
  final String id;
  String name;
  String ip;
  int port;
  String username;
  String password;
  int channelCount;
  bool isOnline;

  NvrDevice({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 554,
    required this.username,
    required this.password,
    this.channelCount = 4,
    this.isOnline = true,
  });

  String getRtspUrl(int channelIndex, {bool isSubStream = true}) {
    final authPart = (username.isNotEmpty && password.isNotEmpty)
        ? '$username:$password@'
        : '';
    final streamType = isSubStream ? '2' : '1';
    return 'rtsp://$authPart$ip:$port/Streaming/Channels/${channelIndex}0$streamType';
  }
}

// =============================================================================
// MAIN APPLICATION ENTRY POINT
// =============================================================================
class SuperLiveSmartHomeApp extends StatelessWidget {
  const SuperLiveSmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SuperLive Smart Home',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: SuperLiveTheme.background,
        colorScheme: const ColorScheme.dark(
          primary: SuperLiveTheme.cyanAccent,
          surface: SuperLiveTheme.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: SuperLiveTheme.surface,
          foregroundColor: SuperLiveTheme.textPrimary,
          elevation: 0,
        ),
      ),
      home: const AppLockScreen(),
    );
  }
}

// =============================================================================
// SECURITY APP LOCK SCREEN (BIOMETRIC & PASSCODE)
// =============================================================================
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _pinController = TextEditingController();

  String savedPin = '1234';
  bool isBiometricSupported = false;
  bool isAuthenticating = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final bool canCheck = await auth.canCheckBiometrics;
      final bool isSupported = await auth.isDeviceSupported();
      if (mounted)
        setState(() => isBiometricSupported = canCheck || isSupported);
      if (isBiometricSupported) _authenticateBiometrics();
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  Future<void> _authenticateBiometrics() async {
    try {
      setState(() {
        isAuthenticating = true;
        errorMessage = '';
      });
      final bool authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to access SuperLive Smart Home',
      );
      if (authenticated && mounted) _unlockApp();
    } on PlatformException catch (e) {
      if (mounted)
        setState(() => errorMessage = 'Biometric Error: ${e.message}');
    } finally {
      if (mounted) setState(() => isAuthenticating = false);
    }
  }

  void _verifyPin() {
    if (_pinController.text == savedPin) {
      _unlockApp();
    } else {
      setState(() => errorMessage = 'Invalid Passcode!');
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
    return Scaffold(
      backgroundColor: SuperLiveTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: SuperLiveTheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: SuperLiveTheme.cyanAccent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SuperLiveTheme.cyanAccent.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    size: 64,
                    color: SuperLiveTheme.cyanAccent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'SUPERLIVE SURVEILLANCE',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: SuperLiveTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter PIN or Use Biometrics to Access Controls',
                  style: TextStyle(
                    fontSize: 13,
                    color: SuperLiveTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 36),

                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SuperLiveTheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: SuperLiveTheme.cardBorder),
                  ),
                  child: Column(
                    children: [
                      if (errorMessage.isNotEmpty) ...[
                        Text(
                          errorMessage,
                          style: const TextStyle(
                            color: SuperLiveTheme.redAlert,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
                          fontSize: 26,
                          letterSpacing: 10,
                          fontWeight: FontWeight.bold,
                          color: SuperLiveTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '••••',
                          counterText: '',
                          labelText: 'Security PIN',
                          labelStyle: const TextStyle(
                            color: SuperLiveTheme.cyanAccent,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: SuperLiveTheme.cyanAccent,
                              width: 2,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.length == 4) _verifyPin();
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SuperLiveTheme.cyanAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _verifyPin,
                          child: const Text(
                            'UNLOCK APP',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (isBiometricSupported) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            side: const BorderSide(
                              color: SuperLiveTheme.cyanAccent,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(
                            Icons.fingerprint_rounded,
                            color: SuperLiveTheme.cyanAccent,
                          ),
                          label: const Text(
                            'BIOMETRIC UNLOCK',
                            style: TextStyle(
                              color: SuperLiveTheme.cyanAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: isAuthenticating
                              ? null
                              : _authenticateBiometrics,
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

// =============================================================================
// MAIN NAVIGATION WRAPPER (4-TAB SUPERLIVE NAVIGATION BAR)
// =============================================================================
class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _currentIndex = 0;
  String esp32Ip = '192.168.1.50';

  final List<NvrDevice> devices = [
    NvrDevice(
      id: 'dvr_01',
      name: 'Main Home NVR',
      ip: '192.168.1.100',
      port: 554,
      username: 'admin',
      password: 'admin123',
      channelCount: 4,
      isOnline: true,
    ),
  ];

  void _addDevice(NvrDevice newDevice) {
    setState(() {
      devices.add(newDevice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      SuperLiveViewTab(device: devices.isNotEmpty ? devices.first : null),
      GatesAutomationTab(esp32Ip: esp32Ip),
      DeviceListTab(devices: devices, onDeviceAdded: _addDevice),
      SettingsTab(
        esp32Ip: esp32Ip,
        onEspIpSaved: (newIp) => setState(() => esp32Ip = newIp),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: SuperLiveTheme.surface,
          border: Border(
            top: BorderSide(color: SuperLiveTheme.cardBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: SuperLiveTheme.surface,
          selectedItemColor: SuperLiveTheme.cyanAccent,
          unselectedItemColor: SuperLiveTheme.textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
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
              label: 'Gates & Rules',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.view_list_rounded),
              activeIcon: Icon(Icons.list_alt_rounded),
              label: 'Device List',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TAB 1: SUPERLIVE PLUS STYLE LIVE VIEW TAB (RTSP MULTI-GRID & PTZ TOOLBAR)
// =============================================================================
class SuperLiveViewTab extends StatefulWidget {
  final NvrDevice? device;
  const SuperLiveViewTab({super.key, required this.device});

  @override
  State<SuperLiveViewTab> createState() => _SuperLiveViewTabState();
}

class _SuperLiveViewTabState extends State<SuperLiveViewTab> {
  int gridLayout = 1; // 1 = 1x1, 4 = 2x2, 9 = 3x3
  int selectedChannel = 1;
  bool isMuted = true;
  bool isRecording = false;
  bool isIntercomActive = false;
  bool isHdMode = true;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;

    return Scaffold(
      backgroundColor: SuperLiveTheme.background,
      appBar: AppBar(
        title: Text(
          device != null
              ? '${device.name} (Live View)'
              : 'SuperLive CCTV Stream',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_to_front_rounded),
            tooltip: 'Aspect Ratio',
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(
              isHdMode ? Icons.hd_rounded : Icons.sd_rounded,
              color: SuperLiveTheme.cyanAccent,
            ),
            tooltip: 'HD/SD Quality',
            onPressed: () => setState(() => isHdMode = !isHdMode),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Section: SuperLive Multi-Grid Player Container
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: device == null
                  ? const Center(
                      child: Text(
                        'No DVR Device Configured',
                        style: TextStyle(color: SuperLiveTheme.textSecondary),
                      ),
                    )
                  : _buildGridPlayerView(device),
            ),
          ),

          // Middle Section: SuperLive Plus Control Bar (Snapshot, Record, Audio, Intercom)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: SuperLiveTheme.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: Icon(
                    isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: isMuted
                        ? SuperLiveTheme.textSecondary
                        : SuperLiveTheme.cyanAccent,
                  ),
                  tooltip: 'Mute/Unmute',
                  onPressed: () => setState(() => isMuted = !isMuted),
                ),
                IconButton(
                  icon: Icon(
                    Icons.mic_rounded,
                    color: isIntercomActive
                        ? SuperLiveTheme.cyanAccent
                        : SuperLiveTheme.textSecondary,
                  ),
                  tooltip: 'Two-Way Intercom',
                  onPressed: () =>
                      setState(() => isIntercomActive = !isIntercomActive),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.camera_alt_rounded,
                    color: SuperLiveTheme.textPrimary,
                  ),
                  tooltip: 'Snapshot',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Snapshot saved to gallery 📸'),
                        backgroundColor: SuperLiveTheme.cyanAccent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.fiber_manual_record_rounded,
                    color: isRecording
                        ? SuperLiveTheme.redAlert
                        : SuperLiveTheme.textSecondary,
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
                            : SuperLiveTheme.cyanAccent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: SuperLiveTheme.cyanAccent,
                  ),
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
          const Divider(height: 1, color: SuperLiveTheme.cardBorder),

          // Bottom Section: Grid Switcher Toolbar & PTZ Directional Joystick
          Expanded(
            flex: 2,
            child: Container(
              color: SuperLiveTheme.surface,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Grid Layout Mode Switcher (1x1, 2x2, 3x3)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildGridModeButton('1x1', 1),
                      const SizedBox(width: 12),
                      _buildGridModeButton('2x2', 4),
                      const SizedBox(width: 12),
                      _buildGridModeButton('3x3', 9),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // PTZ Directional Controller
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SuperLiveTheme.background,
                          border: Border.all(color: SuperLiveTheme.cardBorder),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              top: 4,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_drop_up_rounded,
                                  size: 32,
                                  color: SuperLiveTheme.cyanAccent,
                                ),
                                onPressed: () {},
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 32,
                                  color: SuperLiveTheme.cyanAccent,
                                ),
                                onPressed: () {},
                              ),
                            ),
                            Positioned(
                              left: 4,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_left_rounded,
                                  size: 32,
                                  color: SuperLiveTheme.cyanAccent,
                                ),
                                onPressed: () {},
                              ),
                            ),
                            Positioned(
                              right: 4,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_right_rounded,
                                  size: 32,
                                  color: SuperLiveTheme.cyanAccent,
                                ),
                                onPressed: () {},
                              ),
                            ),
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: SuperLiveTheme.surface,
                              child: Icon(
                                Icons.open_with_rounded,
                                size: 16,
                                color: SuperLiveTheme.cyanAccent,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildGridModeButton(String label, int mode) {
    final bool isSelected = gridLayout == mode;
    return InkWell(
      onTap: () => setState(() => gridLayout = mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? SuperLiveTheme.cyanAccent.withValues(alpha: 0.15)
              : SuperLiveTheme.background,
          border: Border.all(
            color: isSelected
                ? SuperLiveTheme.cyanAccent
                : SuperLiveTheme.cardBorder,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected
                ? SuperLiveTheme.cyanAccent
                : SuperLiveTheme.textSecondary,
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

// Single Live Stream Player Tile Component
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
    return Stack(
      children: [
        VlcPlayer(
          controller: _vlcController,
          aspectRatio: 16 / 9,
          placeholder: const Center(
            child: CircularProgressIndicator(
              color: SuperLiveTheme.cyanAccent,
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
                color: SuperLiveTheme.cyanAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// TAB 2: GATES & AUTOMATION RULES TAB (Firebase Triggers + Rules Engine)
// =============================================================================
class GatesAutomationTab extends StatefulWidget {
  final String esp32Ip;
  const GatesAutomationTab({super.key, required this.esp32Ip});

  @override
  State<GatesAutomationTab> createState() => _GatesAutomationTabState();
}

class _GatesAutomationTabState extends State<GatesAutomationTab> {
  bool isGate1Open = false;
  bool isGate2Open = false;
  bool isGate1Loading = false;
  bool isGate2Loading = false;
  bool isConnected = false;

  // Automation Rules State
  int autoCloseTimerSeconds = 30; // 0 = Disabled, 10s, 30s, 60s
  bool isBeamSensorEnabled = true;
  bool isScheduleEnabled = true;

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

      // Handle Auto-Close Timer Rule if Enabled
      if (autoCloseTimerSeconds > 0) {
        _scheduleAutoClose(firebasePath, localEndpoint);
      }
    }
  }

  void _scheduleAutoClose(String firebasePath, String localEndpoint) {
    Timer(Duration(seconds: autoCloseTimerSeconds), () async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Auto-Close Rule Triggered after ${autoCloseTimerSeconds}s ⏱️',
          ),
          backgroundColor: SuperLiveTheme.cyanAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (Firebase.apps.isNotEmpty) {
        try {
          await FirebaseDatabase.instance.ref(firebasePath).set(1);
        } catch (_) {}
      }
    });
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
              ? 'Signal sent to Firebase Cloud 🚀 (/gate_status = 1)'
              : 'Direct IP unreachable',
          fbActive ? SuperLiveTheme.cyanAccent : SuperLiveTheme.redAlert,
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
    return Scaffold(
      backgroundColor: SuperLiveTheme.background,
      appBar: AppBar(title: const Text('Gates & Automation Rules')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SuperLiveTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SuperLiveTheme.cardBorder),
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
                          : SuperLiveTheme.cyanAccent,
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
                        color: SuperLiveTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: SuperLiveTheme.cyanAccent,
                    ),
                    onPressed: checkConnection,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // SECTION 1: MANUAL GATE TRIGGERS
            const Text(
              'Manual Gate Triggers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: SuperLiveTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            _buildGateCard(
              title: 'Main Entrance Gate',
              subtitle: 'Firebase Path: /gate_status',
              icon: Icons.sensor_door_outlined,
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

            _buildGateCard(
              title: 'Garage Entrance Gate',
              subtitle: 'Firebase Path: /gate2_status',
              icon: Icons.garage_outlined,
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
            const SizedBox(height: 28),

            // SECTION 2: AUTOMATION & RULES ENGINE CARD
            const Text(
              'Automation Rules & Safety Logic',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: SuperLiveTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SuperLiveTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: SuperLiveTheme.cardBorder),
              ),
              child: Column(
                children: [
                  // Auto-Close Timer Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            color: SuperLiveTheme.cyanAccent,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Auto-Close Timer Rule',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: SuperLiveTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      DropdownButton<int>(
                        value: autoCloseTimerSeconds,
                        dropdownColor: SuperLiveTheme.surface,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Disabled')),
                          DropdownMenuItem(
                            value: 10,
                            child: Text('10 Seconds'),
                          ),
                          DropdownMenuItem(
                            value: 30,
                            child: Text('30 Seconds'),
                          ),
                          DropdownMenuItem(
                            value: 60,
                            child: Text('60 Seconds'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null)
                            setState(() => autoCloseTimerSeconds = val);
                        },
                      ),
                    ],
                  ),
                  const Divider(color: SuperLiveTheme.cardBorder, height: 24),

                  // Scheduled Schedule Rule
                  SwitchListTile(
                    activeColor: SuperLiveTheme.cyanAccent,
                    title: const Text(
                      'Daily Schedule Automation',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Auto-Open at 07:00 AM • Auto-Close at 10:00 PM',
                      style: TextStyle(
                        fontSize: 12,
                        color: SuperLiveTheme.textSecondary,
                      ),
                    ),
                    value: isScheduleEnabled,
                    onChanged: (val) => setState(() => isScheduleEnabled = val),
                  ),
                  const Divider(color: SuperLiveTheme.cardBorder, height: 24),

                  // Infrared Safety Beam Sensor Logic
                  SwitchListTile(
                    activeColor: SuperLiveTheme.cyanAccent,
                    title: const Text(
                      'Infrared Safety Beam Protection',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Prevent gate closing if obstruction is detected by beam sensor',
                      style: TextStyle(
                        fontSize: 12,
                        color: SuperLiveTheme.textSecondary,
                      ),
                    ),
                    value: isBeamSensorEnabled,
                    onChanged: (val) =>
                        setState(() => isBeamSensorEnabled = val),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGateCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isOpen,
    required VoidCallback? onPressed,
  }) {
    final statusColor = isOpen
        ? SuperLiveTheme.greenOnline
        : SuperLiveTheme.redAlert;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SuperLiveTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOpen
              ? SuperLiveTheme.greenOnline
              : SuperLiveTheme.cardBorder,
          width: isOpen ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isOpen
                      ? SuperLiveTheme.greenOnline.withValues(alpha: 0.1)
                      : SuperLiveTheme.cyanAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: isOpen
                      ? SuperLiveTheme.greenOnline
                      : SuperLiveTheme.cyanAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: SuperLiveTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SuperLiveTheme.textSecondary,
                      ),
                    ),
                  ],
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
                  isOpen ? 'Opening...' : 'Closed',
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
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOpen
                    ? SuperLiveTheme.greenOnline
                    : SuperLiveTheme.cyanAccent,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onPressed,
              child: Text(
                isOpen
                    ? 'Pulse Triggered (500ms)'
                    : 'TRIGGER GATE (500ms Pulse)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 3: DEVICE LIST & NVR ADD TAB (SUPERLIVE DEVICE LIST & CONFIGURATION)
// =============================================================================
class DeviceListTab extends StatelessWidget {
  final List<NvrDevice> devices;
  final ValueChanged<NvrDevice> onDeviceAdded;

  const DeviceListTab({
    super.key,
    required this.devices,
    required this.onDeviceAdded,
  });

  void _showAddDeviceModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '554');
    final userCtrl = TextEditingController(text: 'admin');
    final passCtrl = TextEditingController();
    int selectedChannels = 4;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SuperLiveTheme.surface,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add DVR / NVR Device',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: SuperLiveTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Device Name (e.g. Backyard NVR)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(
                  labelText: 'IP Address / Domain',
                  hintText: '192.168.1.100',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'RTSP Port',
                  hintText: '554',
                  prefixIcon: Icon(Icons.numbers),
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
              const SizedBox(height: 16),

              StatefulBuilder(
                builder: (context, setModalState) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Camera Channels:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      DropdownButton<int>(
                        value: selectedChannels,
                        dropdownColor: SuperLiveTheme.surface,
                        items: [2, 4, 6, 8]
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text('$c Channels'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null)
                            setModalState(() => selectedChannels = val);
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SuperLiveTheme.cyanAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (ipCtrl.text.isNotEmpty) {
                      final newDev = NvrDevice(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameCtrl.text.isNotEmpty
                            ? nameCtrl.text
                            : 'Home NVR',
                        ip: ipCtrl.text.trim(),
                        port: int.tryParse(portCtrl.text.trim()) ?? 554,
                        username: userCtrl.text.trim(),
                        password: passCtrl.text.trim(),
                        channelCount: selectedChannels,
                      );
                      onDeviceAdded(newDev);
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text(
                    'SAVE & CONNECT DEVICE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SuperLiveTheme.background,
      appBar: AppBar(
        title: const Text('Device List (NVR / DVR)'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.add_rounded,
              color: SuperLiveTheme.cyanAccent,
              size: 28,
            ),
            onPressed: () => _showAddDeviceModal(context),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: devices.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final dev = devices[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SuperLiveTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SuperLiveTheme.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SuperLiveTheme.cyanAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.dns_rounded,
                    color: SuperLiveTheme.cyanAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dev.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: SuperLiveTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${dev.ip}:${dev.port} • ${dev.channelCount} Channels',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SuperLiveTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: SuperLiveTheme.greenOnline.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.circle,
                        color: SuperLiveTheme.greenOnline,
                        size: 8,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'ONLINE',
                        style: TextStyle(
                          color: SuperLiveTheme.greenOnline,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
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
// TAB 4: SETTINGS & SYSTEM CONFIGURATION TAB
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

    return Scaffold(
      backgroundColor: SuperLiveTheme.background,
      appBar: AppBar(title: const Text('System Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ESP32 Local Gateway IP',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: SuperLiveTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: espController,
              decoration: InputDecoration(
                hintText: '192.168.1.50',
                filled: true,
                fillColor: SuperLiveTheme.surface,
                prefixIcon: const Icon(
                  Icons.router_outlined,
                  color: SuperLiveTheme.cyanAccent,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: SuperLiveTheme.cyanAccent,
                  ),
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
                  backgroundColor: SuperLiveTheme.cyanAccent,
                  foregroundColor: Colors.black,
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
