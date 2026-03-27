import 'package:flutter/material.dart';

import '../state/app_phase.dart';

class StatusBanner extends StatefulWidget {
  const StatusBanner({
    super.key,
    required this.phase,
    required this.errorMessage,
    required this.recordingElapsed,
    required this.onRetry,
    required this.onCancel,
  });

  final AppPhase phase;
  final String? errorMessage;
  final Duration recordingElapsed;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  State<StatusBanner> createState() => _StatusBannerState();
}

class _StatusBannerState extends State<StatusBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.phase == AppPhase.idle) {
      return const SizedBox.shrink();
    }
    if (widget.phase == AppPhase.recording) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.mic_rounded, color: Color(0xFFE53935), size: 16),
            const SizedBox(width: 8),
            Text(
              '녹음 중 ${_formatElapsed(widget.recordingElapsed)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
    }

    final canCancel =
        widget.phase == AppPhase.thinking || widget.phase == AppPhase.speaking;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: InkWell(
          onTap: canCancel ? widget.onCancel : null,
          borderRadius: BorderRadius.circular(10),
          child: widget.phase == AppPhase.error
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(
                        '오류: ${widget.errorMessage ?? '알 수 없는 오류'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: widget.onRetry,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      child: const Text('다시 시도'),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.phase == AppPhase.thinking ? '생각 중' : '말하는 중',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _TypingDots(animation: _dotsController),
                  ],
                ),
        ),
      ),
    );
  }

  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Row(
          children: List.generate(3, (index) {
            final offset = (t - index * 0.2).clamp(0.0, 1.0);
            final opacity =
                0.25 + (0.75 * (0.5 + 0.5 * (1 - (offset - 0.5).abs() * 2)));
            return Container(
              width: 6,
              height: 6,
              margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
