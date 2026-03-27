import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_wear_os_connectivity/flutter_wear_os_connectivity.dart';

void main() {
  runApp(const WatchPttApp());
}

class WatchPttApp extends StatelessWidget {
  const WatchPttApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PTT Watch Companion',
      debugShowCheckedModeBanner: false,
      home: const WatchHomeScreen(),
    );
  }
}

class WatchHomeScreen extends StatefulWidget {
  const WatchHomeScreen({super.key});

  @override
  State<WatchHomeScreen> createState() => _WatchHomeScreenState();
}

class _WatchHomeScreenState extends State<WatchHomeScreen> {
  final FlutterWearOsConnectivity _connectivity = FlutterWearOsConnectivity();
  StreamSubscription<List<DataEvent>>? _stateSubscription;
  String _status = 'idle';
  String? _phoneDeviceId;

  @override
  void initState() {
    super.initState();
    _initializeWearConnectivity();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _connectivity.removeDataListener(
      pathURI: Uri(scheme: 'wear', host: '*', path: '/ptt/state'),
    );
    super.dispose();
  }

  Future<void> _initializeWearConnectivity() async {
    await _connectivity.configureWearableAPI();
    _stateSubscription = _connectivity
        .dataChanged(pathURI: Uri(scheme: 'wear', host: '*', path: '/ptt/state'))
        .listen((events) {
      for (final event in events) {
        final nextStatus = event.dataItem.mapData['status'];
        if (nextStatus is String && mounted) {
          setState(() {
            _status = nextStatus;
          });
        }
      }
    });

    final local = await _connectivity.getLocalDevice();
    final devices = await _connectivity.getConnectedDevices();
    final phone = devices.where((device) => device.id != local.id);
    if (phone.isNotEmpty && mounted) {
      setState(() {
        _phoneDeviceId = phone.first.id;
      });
    }
  }

  Future<void> _sendToggle() async {
    final target = _phoneDeviceId;
    if (target == null) {
      final local = await _connectivity.getLocalDevice();
      final devices = await _connectivity.getConnectedDevices();
      final phone = devices.where((device) => device.id != local.id);
      if (phone.isEmpty) {
        return;
      }
      _phoneDeviceId = phone.first.id;
    }

    await _connectivity.sendMessage(
      Uint8List(0),
      deviceId: _phoneDeviceId!,
      path: '/ptt/toggle',
      priority: MessagePriority.high,
    );
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _backgroundColorForStatus(_status);
    final statusLabel = _statusLabel(_status);
    final isSpeaking = _status == 'speaking';

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                statusLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 120,
                height: 120,
                child: ElevatedButton(
                  onPressed: _sendToggle,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 0,
                  ),
                  child: Text(
                    isSpeaking ? '⏹' : '🎤',
                    style: const TextStyle(fontSize: 40),
                  ),
                ),
              ),
              if (isSpeaking) ...[
                const SizedBox(height: 12),
                const Text(
                  '탭하여 정지',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color _backgroundColorForStatus(String status) {
  switch (status) {
    case 'recording':
      return Colors.red.shade800;
    case 'thinking':
      return Colors.blue.shade800;
    case 'speaking':
      return Colors.green.shade800;
    case 'error':
      return Colors.orange.shade800;
    case 'idle':
    default:
      return Colors.black;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'recording':
      return '녹음중';
    case 'thinking':
      return '생각중';
    case 'speaking':
      return '말하는중';
    case 'error':
      return '오류';
    case 'idle':
    default:
      return '대기';
  }
}
