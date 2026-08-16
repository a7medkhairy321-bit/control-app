import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

// ==========================================
// DVR / NVR DEVICE MODEL (الموديل المحدث)
// ==========================================
class NvrDevice {
  final String id; // Serial Number
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
    this.ip = "192.168.1.100", // قيمة افتراضية بدون طلبها من المستخدم
    this.port = 554, // قيمة افتراضية للبورت
    required this.username,
    required this.password,
    this.channelCount = 4,
    this.isOnline = true,
  });

  String getRtspUrl(int channelIndex, {bool isSubStream = true}) {
    // رابط البث الافتراضي
    return "rtsp://$username:$password@$ip:$port/ch${channelIndex + 1}/${isSubStream ? 'sub' : 'main'}";
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
      if (mounted) {
        setState(() => isBiometricSupported = canCheck || isSupported);
      }
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
      if (mounted) {
        setState(() => errorMessage = 'Biometric Error: ${e.message}');
      }
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
      SuperLiveViewTab(devices: devices),
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
// TAB 1: SUPERLIVE PLUS STYLE LIVE VIEW TAB (RTSP MULTI-GRID)
// =============================================================================
// NOTE: the PTZ (Pan/Tilt/Zoom) directional arrow pad that used to sit under
// the grid-mode switcher has been removed. That control only makes sense for
// motorized cameras that can physically move — it sends direction commands
// over ONVIF/CGI to rotate the camera. Since these are fixed cameras, the
// pad had no wiring behind it and no effect, so it's gone rather than kept
// as dead UI. If a PTZ camera is ever added, this is the natural place to
// bring a control like it back, wired to that specific camera's API.
class SuperLiveViewTab extends StatefulWidget {
  final List<NvrDevice> devices;
  const SuperLiveViewTab({super.key, required this.devices});

  @override
  State<SuperLiveViewTab> createState() => _SuperLiveViewTabState();
}

class _SuperLiveViewTabState extends State<SuperLiveViewTab> {
  int gridLayout = 1; // 1 = 1x1, 4 = 2x2, 9 = 3x3
  int selectedChannel = 1;
  int selectedDeviceIndex = 0;
  bool isMuted = true;
  bool isRecording = false;
  bool isIntercomActive = false;
  bool isHdMode = true;

  @override
  Widget build(BuildContext context) {
    // Keep the index valid even if the device list shrinks/changes.
    final safeIndex = widget.devices.isEmpty
        ? 0
        : selectedDeviceIndex.clamp(0, widget.devices.length - 1);
    final device = widget.devices.isNotEmpty ? widget.devices[safeIndex] : null;

    return Scaffold(
      backgroundColor: SuperLiveTheme.background,
      appBar: AppBar(
        title: Text(
          device != null
              ? '${device.name} (Live View)'
              : 'SuperLive CCTV Stream',
        ),
        actions: [
          // Camera/device switcher — only shown once there's actually a
          // choice to make, so single-NVR setups (the common case) stay
          // uncluttered.
          if (widget.devices.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(
                Icons.dns_outlined,
                color: SuperLiveTheme.cyanAccent,
              ),
              tooltip: 'Switch Device',
              color: SuperLiveTheme.surface,
              onSelected: (index) => setState(() {
                selectedDeviceIndex = index;
                selectedChannel = 1;
              }),
              itemBuilder: (context) => [
                for (int i = 0; i < widget.devices.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Row(
                      children: [
                        Icon(
                          i == safeIndex
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: i == safeIndex
                              ? SuperLiveTheme.cyanAccent
                              : SuperLiveTheme.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          widget.devices[i].name,
                          style: const TextStyle(
                            color: SuperLiveTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
                    // Not wired to real capture yet — see note below the
                    // build method. Telling the user it saved when nothing
                    // was written to disk would be actively misleading.
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Snapshot capture — coming soon'),
                        backgroundColor: SuperLiveTheme.surface,
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
                    // Not wired to real recording yet — same reasoning as
                    // the snapshot button above.
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Recording — coming soon'),
                        backgroundColor: SuperLiveTheme.surface,
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

          // Bottom Section: Grid Switcher Toolbar
          // (PTZ directional pad removed — see class-level note above)
          Container(
            color: SuperLiveTheme.surface,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildGridModeButton('1x1', 1),
                const SizedBox(width: 12),
                _buildGridModeButton('2x2', 4),
                const SizedBox(width: 12),
                _buildGridModeButton('3x3', 9),
              ],
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
        isMuted: isMuted,
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
          isMuted: isMuted,
          // Tapping a tile in the grid jumps straight into a full HD
          // view of that specific channel — previously grid tiles were
          // dead taps and the fullscreen button was permanently stuck
          // showing Channel 1 no matter which tile you were looking at.
          onTap: () {
            setState(() => selectedChannel = chNum);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullscreenPlayerModal(
                  cameraName: 'CH $chNum - ${device.name}',
                  rtspUrl: device.getRtspUrl(chNum, isSubStream: false),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Single Live Stream Player Tile Component
class LiveStreamTile extends StatefulWidget {
  final String channelName;
  final String rtspUrl;
  final bool isMuted;
  final VoidCallback? onTap;

  const LiveStreamTile({
    super.key,
    required this.channelName,
    required this.rtspUrl,
    this.isMuted = true,
    this.onTap,
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
      // ignore: deprecated_member_use
      onInit: () {
        // Apply the current mute state as soon as the stream is ready —
        // without this the mute toggle in the control bar changed the
        // icon but never touched actual playback audio.
        _vlcController.setVolume(widget.isMuted ? 0 : 100);
      },
    );
  }

  @override
  void didUpdateWidget(covariant LiveStreamTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMuted != widget.isMuted) {
      _vlcController.setVolume(widget.isMuted ? 0 : 100);
    }
  }

  @override
  void dispose() {
    _vlcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
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
          // Small tappable hint on grid tiles so it's clear they open a
          // full view, not just decoration.
          if (widget.onTap != null)
            const Positioned(
              bottom: 6,
              right: 6,
              child: Icon(
                Icons.open_in_full_rounded,
                size: 14,
                color: Colors.white70,
              ),
            ),
        ],
      ),
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
// TAB 2: GATES TAB (Firebase + ESP32 Manual Triggers)
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

  // 1. تعريف المتغيرات (Controllers)
  final TextEditingController _serialNumberController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  List<NvrDevice> myDevices = [];

  // 2. تعريف دالة فتح الباركود
  void _openBarcodeScanner() async {
    final scannedCode = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const QRScannerView(), // تأكد إن كلاس الـ QRScannerView موجود تحت في الملف
      ),
    );

    if (scannedCode != null) {
      setState(() {
        _serialNumberController.text = scannedCode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SuperLiveTheme.background,
      appBar: AppBar(title: const Text('Gate Control'), centerTitle: false),
      body: SingleChildScrollView(
        child: SingleChildScrollView(
          // <-- ضيف دي هنا عشان الصفحة ترتفع وتنزيل مع الكيبورد
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Serial Number Field with Barcode Scan Icon
              TextField(
                controller: _serialNumberController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Serial Number',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(
                    Icons.qr_code,
                    color: Colors.blueAccent,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.camera_alt,
                      color: Colors.blueAccent,
                    ),
                    onPressed: _openBarcodeScanner,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Device Name Field
              TextField(
                controller: _deviceNameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Device Name (e.g., Home)',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(
                    Icons.devices,
                    color: Colors.blueAccent,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 3. Username Field
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(
                    Icons.person,
                    color: Colors.blueAccent,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 4. Password Field
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.lock, color: Colors.blueAccent),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 5. Save Button (زرار الحفظ المحدث)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                onPressed: () {
                  // إنشاء كائن الجهاز الجديد بالبيانات المدخلة وتجاوز الـ IP والبورت تلقائياً
                  NvrDevice newDevice = NvrDevice(
                    id: _serialNumberController.text,
                    name: _deviceNameController.text,
                    username: _usernameController.text,
                    password: _passwordController.text,
                  );

                  setState(() {
                    myDevices.add(newDevice);
                  });

                  Navigator.pop(context);
                },
                child: const Text(
                  'Save',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),

              // ---------- Connection status hero ----------
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      SuperLiveTheme.surface,
                      SuperLiveTheme.surface.withValues(alpha: 0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SuperLiveTheme.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            (isConnected
                                    ? SuperLiveTheme.greenOnline
                                    : SuperLiveTheme.cyanAccent)
                                .withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        isConnected ? Icons.wifi_rounded : Icons.cloud_rounded,
                        color: isConnected
                            ? SuperLiveTheme.greenOnline
                            : SuperLiveTheme.cyanAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _LiveDot(
                                color: isConnected
                                    ? SuperLiveTheme.greenOnline
                                    : SuperLiveTheme.cyanAccent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isConnected
                                    ? 'Direct Connection'
                                    : 'Cloud Relay',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: SuperLiveTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isConnected
                                ? widget.esp32Ip
                                : 'Commands are routed via Firebase',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SuperLiveTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: SuperLiveTheme.cyanAccent,
                      ),
                      onPressed: checkConnection,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ---------- Section heading ----------
              const Text(
                'Your Gates',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: SuperLiveTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap a card to send an instant open pulse',
                style: TextStyle(
                  fontSize: 13,
                  color: SuperLiveTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              _AnimatedGateCard(
                title: 'Main Entrance Gate',
                subtitle: '/gate_status',
                icon: Icons.sensor_door_outlined,
                accentColor: SuperLiveTheme.cyanAccent,
                isOpen: isGate1Open,
                isLoading: isGate1Loading,
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

              _AnimatedGateCard(
                title: 'Internal Gate',
                subtitle: '/gate2_status',
                icon: Icons.door_sliding_outlined,
                accentColor: SuperLiveTheme.goldAccent,
                isOpen: isGate2Open,
                isLoading: isGate2Loading,
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
              const SizedBox(height: 22),

              // ---------- Small footer hint ----------
              Row(
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: SuperLiveTheme.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Each trigger sends a 500ms pulse, matching the ESP32 relay timing.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: SuperLiveTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small pulsing status dot used in the connection hero card.
class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
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
        final opacity = 0.5 + (_controller.value * 0.5);
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Animated gate trigger card.
// Adds tasteful motion without a layout overhaul:
//   1. The card border/glow eases smoothly between "idle" and "open" colors
//      instead of snapping instantly (AnimatedContainer).
//   2. The icon does a gentle spring "swing" whenever the gate state flips
//      (AnimatedScale + AnimatedRotation), like a door nudging open.
//   3. A slim animated progress line appears under the button while the
//      pulse command is in flight, so the button doesn't feel frozen.
// Each gate also gets its own accent color so the two cards read as
// distinct devices at a glance rather than duplicate blocks.
// =============================================================================
class _AnimatedGateCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isOpen;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _AnimatedGateCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.isOpen,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isOpen
        ? SuperLiveTheme.greenOnline
        : SuperLiveTheme.redAlert;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SuperLiveTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isOpen
              ? SuperLiveTheme.greenOnline
              : SuperLiveTheme.cardBorder,
          width: isOpen ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOpen ? SuperLiveTheme.greenOnline : accentColor)
                .withValues(alpha: isOpen ? 0.18 : 0.05),
            blurRadius: 18,
            spreadRadius: isOpen ? 1 : 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedScale(
                scale: isLoading ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                child: AnimatedRotation(
                  turns: isOpen ? 0.02 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          (isOpen ? SuperLiveTheme.greenOnline : accentColor)
                              .withValues(alpha: 0.22),
                          (isOpen ? SuperLiveTheme.greenOnline : accentColor)
                              .withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 30,
                      color: isOpen ? SuperLiveTheme.greenOnline : accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: SuperLiveTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 12,
                          color: SuperLiveTheme.textSecondary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: SuperLiveTheme.textSecondary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Container(
                  key: ValueKey('$isOpen-$isLoading'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isOpen ? 'Opening' : 'Closed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOpen
                    ? SuperLiveTheme.greenOnline
                    : accentColor,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPressed,
              icon: Icon(
                isOpen ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                size: 18,
              ),
              label: Text(
                isOpen ? 'Pulse Sent' : 'Trigger Gate',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          backgroundColor: SuperLiveTheme.cardBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accentColor,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
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
                          if (val != null) {
                            setModalState(() => selectedChannels = val);
                          }
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
        separatorBuilder: (_, _) => const SizedBox(height: 14),
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

// Separate Screen for QR/Barcode Scanning
class QRScannerView extends StatelessWidget {
  const QRScannerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Colors.black,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              final String code = barcode.rawValue!;
              Navigator.pop(context, code);
              break;
            }
          }
        },
      ),
    );
  }
}
