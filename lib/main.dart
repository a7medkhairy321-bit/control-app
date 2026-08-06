import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:local_auth/local_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }
  runApp(const SmartGateApp());
}

class SmartGateApp extends StatelessWidget {
  const SmartGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Access Control',
      theme: ThemeData(
        fontFamily: 'sans-serif',
        useMaterial3: true,
      ),
      home: const LockScreen(),
    );
  }
}

// ----------------- شاشة قفل البصمة وكلمة المرور (Fingerprint & Passcode Lock) -----------------
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _pinController = TextEditingController();
  
  String savedPin = '1234'; // رمز الحماية الافتراضي
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
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool isDeviceSupported = await auth.isDeviceSupported();
      
      if (mounted) {
        setState(() {
          isBiometricSupported = canAuthenticateWithBiometrics || isDeviceSupported;
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
        localizedReason: 'يرجى استخدام البصمة للتحكم في البوابة',
      );

      if (authenticated && mounted) {
        _unlockApp();
      }
    } on PlatformException catch (e) {
      setState(() {
        errorMessage = 'فشلت البصمة: ${e.message}';
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
        errorMessage = 'رمز الحماية غير صحيح!';
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
                    color: Color(0xFF2C3E50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fingerprint_rounded, size: 70, color: Colors.white),
                ),
                const SizedBox(height: 20),
                const Text(
                  'تأمين البوابة الذكية 🔒',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  'يرجى تأكيد الهوية بالبصمة أو الرمز للدخول',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 32),

                // Card Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 15, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (errorMessage.isNotEmpty) ...[
                        Text(
                          errorMessage,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 14),
                      ],

                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: '••••',
                          counterText: '',
                          labelText: 'رمز الحماية (Passcode)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                            backgroundColor: const Color(0xFF2C3E50),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _verifyPin,
                          child: const Text('دخول بالرمز', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      if (isBiometricSupported) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            side: const BorderSide(color: Color(0xFF2C3E50)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.fingerprint_rounded, color: Color(0xFF2C3E50)),
                          label: const Text('استخدام البصمة (Fingerprint)', style: TextStyle(color: Color(0xFF2C3E50), fontWeight: FontWeight.bold)),
                          onPressed: isAuthenticating ? null : _authenticateWithBiometrics,
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

// ----------------- نافذة التنقل السفلي (الصفحات الرئيسية) -----------------
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;
  String esp32Ip = '192.168.1.50';
  String deviceToken = 'SEC_TOK_GATE_8892';

  void _generateNewToken() {
    final randomStr = Random().nextInt(999999).toString().padLeft(6, '0');
    setState(() {
      deviceToken = 'SEC_TOK_$randomStr';
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      ControlScreen(esp32Ip: esp32Ip, deviceToken: deviceToken),
      SettingsScreen(
        currentIp: esp32Ip,
        deviceToken: deviceToken,
        onIpChanged: (newIp) => setState(() => esp32Ip = newIp),
        onGenerateNewToken: _generateNewToken,
      ),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: const Color(0xFF8A9EA7),
          selectedItemColor: const Color(0xFF2C3E50),
          unselectedItemColor: Colors.white70,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }
}

// ----------------- صفحة التحكم الأساسية -----------------
class ControlScreen extends StatefulWidget {
  final String esp32Ip;
  final String deviceToken;
  const ControlScreen({super.key, required this.esp32Ip, required this.deviceToken});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
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
      final response = await http.get(Uri.parse('http://${widget.esp32Ip}/')).timeout(const Duration(seconds: 3));
      if (mounted) setState(() => isConnected = response.statusCode == 200);
    } catch (_) {
      if (mounted) setState(() => isConnected = false);
    }
  }

  Future<void> _triggerGate({
    required String gateKey,
    required String endpoint,
    required bool isLoading,
    required void Function(bool openState, bool loadingState) updateState,
  }) async {
    if (isLoading) return;

    setState(() => updateState(true, true));
    final stopwatch = Stopwatch()..start();

    try {
      // 1. تحديث الفايربيس إن كان مهيأً
      if (Firebase.apps.isNotEmpty) {
        try {
          final ref = FirebaseDatabase.instance.ref("devices/${widget.deviceToken}/$gateKey");
          await ref.set({"trigger": true, "timestamp": ServerValue.timestamp});
        } catch (e) {
          debugPrint('Firebase write note: $e');
        }
      }

      // 2. إرسال أمر HTTP مباشر للـ ESP32 مع التوكن
      await sendEspCommand('$endpoint?token=${widget.deviceToken}');
    } finally {
      final elapsedMs = stopwatch.elapsedMilliseconds;
      const targetDurationMs = 1000; // بالضبط ثانية واحدة
      final remainingMs = targetDurationMs - elapsedMs;

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
      final response = await http.get(Uri.parse('http://${widget.esp32Ip}/$endpoint'));
      if (mounted) {
        setState(() => isConnected = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تنفيذ الأمر: ${response.body}'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isConnected = false);
        final bool fbActive = Firebase.apps.isNotEmpty;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(fbActive ? 'أُرسل الإشارة لـ Firebase (ESP IP غير متصل مباشر)' : 'الـ ESP32 غير متصل حالياً برقم الـ IP'),
            backgroundColor: Colors.blueGrey.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE2E7E9),
      body: Stack(
        children: [
          Container(height: 220, color: const Color(0xFF8A9EA7)),
          Positioned.fill(
            top: 185,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFE2E7E9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? Colors.green : Colors.amber.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnected ? 'متصل مباشر (${widget.esp32Ip})' : (Firebase.apps.isNotEmpty ? 'وضع الفايربيس (Firebase Active)' : 'غير متصل (Local Mode)'),
                        style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                        onPressed: checkConnection,
                        tooltip: 'فحص الاتصال المباشر',
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Smart Access Control',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 35),

                  // Welcome Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F6F7),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 15, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text('مرحباً بك ✨', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 6),
                        Text('التوكن النشط: ${widget.deviceToken}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Gate 1 Card
                  _buildGateCard(
                    title: 'البوابة الرئيسية',
                    isOpen: isGate1Open,
                    onPressed: isGate1Loading
                        ? null
                        : () => _triggerGate(
                              gateKey: 'gate1',
                              endpoint: 'gate1/open',
                              isLoading: isGate1Loading,
                              updateState: (open, loading) {
                                isGate1Open = open;
                                isGate1Loading = loading;
                              },
                            ),
                  ),
                  const SizedBox(height: 24),

                  // Gate 2 Card
                  _buildGateCard(
                    title: 'بوابة الجراج',
                    isOpen: isGate2Open,
                    onPressed: isGate2Loading
                        ? null
                        : () => _triggerGate(
                              gateKey: 'gate2',
                              endpoint: 'gate2/open',
                              isLoading: isGate2Loading,
                              updateState: (open, loading) {
                                isGate2Open = open;
                                isGate2Loading = loading;
                              },
                            ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGateCard({required String title, required bool isOpen, required VoidCallback? onPressed}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Icon(
            isOpen ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            size: 56,
            color: const Color(0xFF2C3E50),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 6),
              Text(
                isOpen ? 'الحالة: جاري الفتح...' : 'الحالة: مغلق',
                style: TextStyle(
                  fontSize: 14,
                  color: isOpen ? Colors.green.shade700 : Colors.black45,
                  fontWeight: isOpen ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 130,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOpen ? const Color(0xFFB0B9BE) : const Color(0xFFDEB042),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: onPressed,
                  child: const Text('افتح (Open)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------- صفحة الإعدادات -----------------
class SettingsScreen extends StatelessWidget {
  final String currentIp;
  final String deviceToken;
  final ValueChanged<String> onIpChanged;
  final VoidCallback onGenerateNewToken;

  const SettingsScreen({
    super.key,
    required this.currentIp,
    required this.deviceToken,
    required this.onIpChanged,
    required this.onGenerateNewToken,
  });

  @override
  Widget build(BuildContext context) {
    final ipController = TextEditingController(text: currentIp);

    return Scaffold(
      backgroundColor: const Color(0xFFE2E7E9),
      appBar: AppBar(
        title: const Text('إعدادات الاتصال والتوكن'),
        backgroundColor: const Color(0xFF8A9EA7),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lock Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0xFF2C3E50),
                    child: Icon(Icons.security_rounded, color: Colors.white),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('حماية التطبيق بالبصمة', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('البصمة ورمز الـ Passcode مفعّلان 🔒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Token Section
            const Text('توكن الأمان (Security Token / API Key)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          deviceToken,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0xFF2C3E50)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFFDEB042)),
                        tooltip: 'نسخ التوكن',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: deviceToken));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم نسخ التوكن إلى الحافظة! 📋'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('توليد توكن جديد'),
                      onPressed: () {
                        onGenerateNewToken();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم توليد توكن جديد!'), backgroundColor: Colors.blue, behavior: SnackBarBehavior.floating),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ESP32 IP Section
            const Text('عنوان ESP32 IP المحظر (اختياري)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            const SizedBox(height: 8),
            TextField(
              controller: ipController,
              decoration: InputDecoration(
                hintText: '192.168.1.50',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C3E50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  onIpChanged(ipController.text.trim());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ الـ IP بنجاح!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
                  );
                },
                child: const Text('حفظ الـ IP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}