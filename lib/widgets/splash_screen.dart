import 'dart:async';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.nextScreen});

  final Widget nextScreen;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _iconScaleController;
  late final AnimationController _titleFadeController;
  late final Animation<double> _iconScale;
  late final Animation<double> _titleFade;
  Timer? _transitionTimer;

  @override
  void initState() {
    super.initState();
    _iconScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _titleFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _iconScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _iconScaleController,
        curve: Curves.easeOutCubic,
      ),
    );
    _titleFade = CurvedAnimation(
      parent: _titleFadeController,
      curve: Curves.easeOut,
    );

    _iconScaleController.forward();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _titleFadeController.forward();
      }
    });

    _transitionTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: widget.nextScreen,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    _iconScaleController.dispose();
    _titleFadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _iconScale,
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 88,
                height: 88,
              ),
            ),
            const SizedBox(height: 18),
            FadeTransition(
              opacity: _titleFade,
              child: const Text(
                'Jamie',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
