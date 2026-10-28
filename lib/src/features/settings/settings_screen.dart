import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/tts/tts_provider.dart';
import '../app_providers.dart';

/// Man hinh cai dat: thu tu provider, voice theo tung provider (load tu API
/// that), toc do doc. Luu don gian trong StateProvider (du cho v1).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<VoiceInfo>? _vieneuVoices;
  List<VoiceInfo>? _kokoroVoices;
  bool _loadingVoices = true;
  String? _voicesError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoices());
  }

  Future<void> _loadVoices() async {
    setState(() {
      _loadingVoices = true;
      _voicesError = null;
    });
    try {
      final vieneu = await ref.read(vieneuProvider).listVoices();
      final kokoro = await ref.read(kokoroProvider).listVoices();
      // Voice dang chon phai ton tai trong list that; neu khong thi reset
      // ve mac dinh (tranh gui voice id rac len server).
      _ensureVoiceValid(vieneu, kokoro);
      setState(() {
        _vieneuVoices = vieneu;
        _kokoroVoices = kokoro;
      });
    } catch (e) {
      setState(() => _voicesError = 'Không tải được danh sách giọng: $e');
    } finally {
      if (mounted) setState(() => _loadingVoices = false);
    }
  }

  void _ensureVoiceValid(List<VoiceInfo> vieneu, List<VoiceInfo> kokoro) {
    final vVoice = ref.read(vieneuVoiceSettingProvider);
    if (vieneu.isNotEmpty && !vieneu.any((v) => v.id == vVoice)) {
      ref.read(vieneuVoiceSettingProvider.notifier).state = DefaultVoice.vieneu;
    }
    final kVoice = ref.read(kokoroVoiceSettingProvider);
    if (kokoro.isNotEmpty && !kokoro.any((v) => v.id == kVoice)) {
      ref.read(kokoroVoiceSettingProvider.notifier).state = DefaultVoice.kokoro;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(providerOrderSettingProvider);
    final vieneuVoice = ref.watch(vieneuVoiceSettingProvider);
    final kokoroVoice = ref.watch(kokoroVoiceSettingProvider);
    final speed = ref.watch(speedSettingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Thứ tự provider', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'vieneu_first', label: Text('Vieneu trước')),
                  ButtonSegment(value: 'kokoro_first', label: Text('Kokoro trước')),
                ],
                selected: {order},
                onSelectionChanged: (set) =>
                    ref.read(providerOrderSettingProvider.notifier).state = set.first,
              ),
              const SizedBox(height: 8),
              const Text(
                'Khi provider đầu lỗi/timeout, app tự chuyển sang provider còn lại.',
              ),
              const Divider(height: 32),
              Text('Giọng đọc', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_loadingVoices)
                const Center(child: CircularProgressIndicator())
              else if (_voicesError != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_voicesError!)),
                        TextButton(onPressed: _loadVoices, child: const Text('Thử lại')),
                      ],
                    ),
                  ),
                )
              else ...[
                _VoiceDropdown(
                  label: 'Vieneu',
                  voices: _vieneuVoices ?? const [],
                  value: vieneuVoice,
                  hint: DefaultVoice.vieneu,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(vieneuVoiceSettingProvider.notifier).state = v;
                    }
                  },
                ),
                const SizedBox(height: 12),
                _VoiceDropdown(
                  label: 'Kokoro',
                  voices: _kokoroVoices ?? const [],
                  value: kokoroVoice,
                  hint: DefaultVoice.kokoro,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(kokoroVoiceSettingProvider.notifier).state = v;
                    }
                  },
                ),
              ],
              const Divider(height: 32),
              Text('Tốc độ đọc (${speed.toStringAsFixed(1)}x)',
                  style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: speed.clamp(SpeedRange.min, SpeedRange.max).toDouble(),
                min: SpeedRange.min,
                max: SpeedRange.max,
                divisions: 10,
                label: '${speed.toStringAsFixed(1)}x',
                onChanged: (v) =>
                    ref.read(speedSettingProvider.notifier).state = v,
              ),
              const Text('Áp dụng cho Kokoro (0.5–1.5). Vieneu dùng tốc độ mặc định của server.'),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceDropdown extends StatelessWidget {
  const _VoiceDropdown({
    required this.label,
    required this.voices,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final List<VoiceInfo> voices;
  final String value;
  final String hint;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final items = voices.map((v) {
      return DropdownMenuItem<String>(
        value: v.id,
        child: Text(v.label, overflow: TextOverflow.ellipsis),
      );
    }).toList();
    // Neu voice dang chon khong co trong list that -> hien hint mac dinh.
    final effectiveValue = voices.any((v) => v.id == value) ? value : null;
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          hint: Text(hint),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
