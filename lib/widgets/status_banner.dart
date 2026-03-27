import 'package:flutter/material.dart';

import '../state/app_phase.dart';

class StatusBanner extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (phase == AppPhase.idle) {
      return const SizedBox.shrink();
    }
    final canCancel = phase == AppPhase.thinking || phase == AppPhase.speaking;

    final color = switch (phase) {
      AppPhase.recording => Colors.red.shade500,
      AppPhase.thinking => Colors.blue.shade500,
      AppPhase.speaking => Colors.green.shade500,
      AppPhase.error => Colors.orange.shade600,
      AppPhase.idle => Colors.transparent,
    };
    final icon = switch (phase) {
      AppPhase.recording => Icons.mic_rounded,
      AppPhase.thinking => Icons.psychology_alt_rounded,
      AppPhase.speaking => Icons.volume_up_rounded,
      AppPhase.error => Icons.error_outline_rounded,
      AppPhase.idle => Icons.circle,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: canCancel ? onCancel : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _buildText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (phase == AppPhase.error)
                  FilledButton.tonal(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('다시 시도'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildText() {
    return switch (phase) {
      AppPhase.recording => '녹음 중 ${_formatElapsed(recordingElapsed)}',
      AppPhase.thinking => '생각 중 (탭하여 취소)',
      AppPhase.speaking => '말하는 중 (탭하여 중단)',
      AppPhase.error => '오류: ${errorMessage ?? '알 수 없는 오류'}',
      AppPhase.idle => '',
    };
  }

  String _formatElapsed(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
