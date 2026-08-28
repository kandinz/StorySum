import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/voice_model.dart';
import '../../models/ai_provider_model.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/player_state_provider.dart';

class KtoolSettingsModal extends StatefulWidget {
  const KtoolSettingsModal({Key? key}) : super(key: key);

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const KtoolSettingsModal(),
    );
  }

  @override
  State<KtoolSettingsModal> createState() => _KtoolSettingsModalState();
}

class _KtoolSettingsModalState extends State<KtoolSettingsModal> {
  int _selectedTabIndex = 0; // 0: Audio & Truyện, 1: Dịch & Tóm tắt, 2: Donate

  late TextEditingController _summaryPromptController;
  late TextEditingController _translatePromptController;
  String? _toastMessage;
  Timer? _toastTimer;

  void _showModalToast(String message) {
    _toastTimer?.cancel();
    if (mounted) {
      setState(() {
        _toastMessage = message;
      });
      _toastTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _toastMessage = null;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    _summaryPromptController = TextEditingController(text: settings.systemPrompt);
    _translatePromptController = TextEditingController(text: settings.translatePrompt);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _summaryPromptController.dispose();
    _translatePromptController.dispose();
    super.dispose();
  }

  AppStateProvider get appStateProvider => Provider.of<AppStateProvider>(context, listen: false);

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final settings = context.watch<SettingsProvider>();
    final player = context.watch<PlayerStateProvider>();
    final colors = AppTheme.getColors(settings.appThemeMode, context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colors.border, width: 1.2),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Header kéo & Tiêu đề
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings_rounded, size: 18, color: colors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Cài Đặt',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // 3 TAB SELECTOR (Audio & Truyện - Dịch & Tóm tắt - Donate)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    _buildTabButton(
                      index: 0,
                      icon: Icons.headphones_rounded,
                      label: 'Audio & Truyện',
                      colors: colors,
                    ),
                    _buildTabButton(
                      index: 1,
                      icon: Icons.auto_awesome_rounded,
                      label: 'Dịch & Tóm tắt',
                      colors: colors,
                    ),
                    _buildTabButton(
                      index: 2,
                      icon: Icons.favorite_rounded,
                      label: 'Donate',
                      colors: colors,
                    ),
                  ],
                ),
              ),

              // Nội dung tương ứng với từng Tab
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: [
                    _buildAudioAndStoryTab(context, appState, settings, player, colors),
                    _buildSummaryTab(context, appState, settings, player, colors),
                    _buildDonateTab(context, colors),
                  ],
                ),
              ),
            ],
          ),

          // Thông báo toast nhỏ gọn nằm trên popup modal
          if (_toastMessage != null)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.border, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _toastMessage!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textPrimary,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
    required AppThemeColors colors,
  }) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // UNIFIED SECTION HEADER & ACTION BUTTON HELPERS
  // ===========================================================================
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    Widget? trailing,
    required AppThemeColors colors,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildFieldLabel({
    required IconData icon,
    required String title,
    Widget? trailing,
    required AppThemeColors colors,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.primary),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required AppThemeColors colors,
    Color? customColor,
  }) {
    final activeColor = customColor ?? colors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: activeColor.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: activeColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: activeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: AUDIO & TRUYỆN (Audio nằm trên, Đọc truyện nằm dưới)
  // ===========================================================================
  Widget _buildAudioAndStoryTab(
    BuildContext context,
    AppStateProvider appState,
    SettingsProvider settings,
    PlayerStateProvider player,
    AppThemeColors colors,
  ) {
    return ListView(
      padding: const EdgeInsets.all(14),
      physics: const BouncingScrollPhysics(),
      children: [
        // ======================= PHẦN AUDIO (NẰM TRÊN) =======================
        // 1. Giọng đọc (Tách dòng riêng)
        _buildFieldLabel(
          icon: Icons.record_voice_over_rounded,
          title: 'Giọng đọc',
          trailing: _buildActionButton(
            label: 'Thêm giọng .onnx',
            icon: Icons.add_rounded,
            onTap: () => _handleImportVoice(context, appState, settings, colors),
            colors: colors,
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        _buildVoiceDropdown(context, settings, colors),
        const SizedBox(height: 12),

        // 2. Tốc độ đọc (Tách dòng riêng)
        _buildSectionHeader(
          icon: Icons.speed_rounded,
          title: 'Tốc độ đọc',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${settings.speed}x',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: colors.primary),
            ),
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Center(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: settings.speed,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: '${settings.speed}x',
                activeColor: colors.primary,
                inactiveColor: colors.elevatedBackground,
                onChanged: (val) {
                  final rounded = (val * 10).round() / 10;
                  settings.setSpeed(rounded);
                  player.setSpeed(rounded);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. Tự động chuyển chương, Hẹn giờ dừng phát & Số câu tải trước audio
        _buildSectionHeader(
          icon: Icons.playlist_play_rounded,
          title: 'Tự Động & Hẹn Giờ',
          colors: colors,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCheckboxOption(
                title: 'Tự chuyển chương khi phát hết',
                value: settings.autoNextChapter,
                colors: colors,
                onChanged: (val) => settings.setAutoNextChapter(val ?? false),
              ),
              Divider(color: colors.border, height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildCheckboxOption(
                      title: player.sleepTimerEnabled
                          ? 'Hẹn giờ dừng (${player.formattedSleepTimerRemaining})'
                          : 'Hẹn giờ dừng phát',
                      value: player.sleepTimerEnabled,
                      colors: colors,
                      onChanged: (val) => player.toggleSleepTimer(val ?? false),
                    ),
                  ),
                  _buildSleepTimerDropdown(context, player, colors),
                ],
              ),
              Divider(color: colors.border, height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Số câu tải trước audio',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  // Stepper điều chỉnh số câu [-] [ 5 ] [+]
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          if (settings.audioPrefetchCount > 1) {
                            settings.setAudioPrefetchCount(settings.audioPrefetchCount - 1);
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.elevatedBackground,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.border),
                          ),
                          child: Center(
                            child: Icon(Icons.remove_rounded, size: 16, color: colors.textPrimary),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _showPrefetchCountDialog(context, settings, colors),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 44,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: colors.elevatedBackground,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.primary.withValues(alpha: 0.5)),
                          ),
                          child: Center(
                            child: Text(
                              '${settings.audioPrefetchCount}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (settings.audioPrefetchCount < 50) {
                            settings.setAudioPrefetchCount(settings.audioPrefetchCount + 1);
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.elevatedBackground,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.border),
                          ),
                          child: Center(
                            child: Icon(Icons.add_rounded, size: 16, color: colors.textPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Đường phân cách giữa Audio và Đọc truyện
        Divider(color: colors.border, thickness: 1, height: 1),
        const SizedBox(height: 16),

        // ======================= PHẦN TRUYỆN (NẰM DƯỚI) =======================
        // 4. Font chữ đọc truyện (Tách thành dòng riêng biệt)
        _buildFieldLabel(
          icon: Icons.font_download_rounded,
          title: 'Font chữ đọc truyện',
          colors: colors,
        ),
        const SizedBox(height: 6),
        _buildFontDropdown(context, settings, colors),
        const SizedBox(height: 12),

        // 5. Theme giao diện (Tách thành dòng riêng biệt)
        _buildFieldLabel(
          icon: Icons.palette_outlined,
          title: 'Giao diện',
          colors: colors,
        ),
        const SizedBox(height: 6),
        _buildThemeDropdown(context, settings, colors),
        const SizedBox(height: 12),

        // 6. Cỡ chữ hiển thị
        _buildSectionHeader(
          icon: Icons.format_size_rounded,
          title: 'Cỡ chữ hiển thị',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${settings.fontSize.toInt()} px',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: colors.primary),
            ),
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Center(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: settings.fontSize,
                min: 12.0,
                max: 26.0,
                divisions: 14,
                label: '${settings.fontSize.toInt()}px',
                activeColor: colors.primary,
                inactiveColor: colors.elevatedBackground,
                onChanged: (val) => settings.setFontSize(val),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: TÓM TẮT (Tùy chọn AI, Chọn Model, Multi-Key Gemini, Prompts)
  // ===========================================================================
  Widget _buildSummaryTab(
    BuildContext context,
    AppStateProvider appState,
    SettingsProvider settings,
    PlayerStateProvider player,
    AppThemeColors colors,
  ) {
    return ListView(
      padding: const EdgeInsets.all(14),
      physics: const BouncingScrollPhysics(),
      children: [
        // 1. Tùy chọn Dịch thuật & Tính năng AI
        _buildSectionHeader(
          icon: Icons.psychology_rounded,
          title: 'Tính Năng AI',
          colors: colors,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              _buildCheckboxOption(
                title: 'Dịch nội dung sang tiếng Việt',
                value: settings.translateContent,
                colors: colors,
                onChanged: (val) => settings.setTranslateContent(val ?? false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Provider AI (Dòng 1)
        _buildFieldLabel(
          icon: Icons.cloud_outlined,
          title: 'Provider AI',
          trailing: _buildActionButton(
            label: 'Thêm Provider',
            icon: Icons.add_rounded,
            onTap: () => _showAddAiProviderDialog(context, settings, colors),
            colors: colors,
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        _buildAiProviderDropdown(context, settings, colors),
        const SizedBox(height: 12),

        // 3. Model AI (Dòng 2)
        _buildFieldLabel(
          icon: Icons.smart_toy_outlined,
          title: 'Model AI (${settings.aiProvider})',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (AiProviderModel.defaultBuiltinProviders.any((b) => b.id == settings.activeProviderId)) ...[
                _buildActionButton(
                  label: 'Khôi phục',
                  icon: Icons.restart_alt_rounded,
                  onTap: () => settings.resetProviderModels(settings.activeProviderId),
                  colors: colors,
                ),
                const SizedBox(width: 6),
              ],
              _buildActionButton(
                label: 'Thêm Model',
                icon: Icons.add_rounded,
                onTap: () => _showAddModelDialog(context, settings, colors),
                colors: colors,
              ),
            ],
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        _buildAiModelDropdown(context, settings, colors),
        const SizedBox(height: 14),

        // 3. Quản lý API Keys
        _buildSectionHeader(
          icon: Icons.vpn_key_rounded,
          title: 'API Key ${settings.aiProvider} (${settings.currentProviderApiKeys.length})',
          trailing: _buildActionButton(
            label: 'Thêm Key',
            icon: Icons.add_rounded,
            onTap: () => _showAddApiKeyDialog(context, settings, colors),
            colors: colors,
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        _buildApiKeysManagerCard(context, settings, colors),
        const SizedBox(height: 14),

        // 4. Prompt Tóm Tắt AI
        _buildSectionHeader(
          icon: Icons.summarize_rounded,
          title: 'Prompt Tóm Tắt Chương',
          trailing: _buildActionButton(
            label: 'Mặc định',
            icon: Icons.restart_alt_rounded,
            onTap: () {
              _summaryPromptController.text = AppConstants.defaultSummaryPrompt;
              settings.setSystemPrompt(AppConstants.defaultSummaryPrompt);
            },
            colors: colors,
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: TextField(
            controller: _summaryPromptController,
            maxLines: 3,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Nhập prompt tóm tắt chương...',
              contentPadding: const EdgeInsets.all(10),
              fillColor: colors.elevatedBackground,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            onChanged: (val) => settings.setSystemPrompt(val),
          ),
        ),
        const SizedBox(height: 14),

        // 5. Prompt Dịch sang Tiếng Việt
        _buildSectionHeader(
          icon: Icons.translate_rounded,
          title: 'Prompt Dịch Sang Tiếng Việt',
          trailing: _buildActionButton(
            label: 'Mặc định',
            icon: Icons.restart_alt_rounded,
            onTap: () {
              _translatePromptController.text = AppConstants.defaultTranslatePrompt;
              settings.setTranslatePrompt(AppConstants.defaultTranslatePrompt);
            },
            colors: colors,
          ),
          colors: colors,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: TextField(
            controller: _translatePromptController,
            maxLines: 3,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Nhập prompt dịch thuật...',
              contentPadding: const EdgeInsets.all(10),
              fillColor: colors.elevatedBackground,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            onChanged: (val) => settings.setTranslatePrompt(val),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // IMPORT VOICE HANDLER
  // ===========================================================================
  Future<void> _handleImportVoice(
    BuildContext context,
    AppStateProvider appState,
    SettingsProvider settings,
    AppThemeColors colors,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['onnx'],
      );
      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        final cleanVoiceName = file.name
            .replaceAll('.onnx', '')
            .replaceAll('(ONNX)', '')
            .replaceAll('ONNX', '')
            .trim();

        final voice = await appState.onnxTtsService.importCustomOnnxModel(
          file.path!,
          cleanVoiceName.isNotEmpty ? cleanVoiceName : 'Giọng tùy biến',
        );
        await settings.addCustomVoice(voice);
        await settings.setSelectedVoice(voice.id);
        if (context.mounted) {
          final player = Provider.of<PlayerStateProvider>(context, listen: false);
          await appState.onVoiceChanged(settings: settings, player: player);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Đã nạp thành công giọng: ${voice.name}')),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Lỗi khi nạp file ONNX: $e')),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  // ===========================================================================
  // SELECTBOXES & DROPDOWNS
  // ===========================================================================
  IconData _getProviderIcon(String providerId) {
    switch (providerId) {
      case 'google-gemini':
        return Icons.auto_awesome_rounded;
      case 'openai':
        return Icons.chat_bubble_outline_rounded;
      case 'anthropic':
        return Icons.psychology_alt_rounded;
      case 'deepseek':
        return Icons.travel_explore_rounded;
      case 'mimo':
        return Icons.smart_toy_rounded;
      case 'openrouter':
        return Icons.alt_route_rounded;
      case 'groq':
        return Icons.bolt_rounded;
      default:
        return Icons.hub_outlined;
    }
  }

  Widget _buildAiProviderDropdown(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    return PopupMenuButton<String>(
      onSelected: (providerId) => settings.setActiveProviderById(providerId),
      color: colors.elevatedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (ctx) {
        return settings.providers.map((provider) {
          final isSelected = provider.id == settings.activeProviderId;
          final domainDisplay = provider.domain.replaceAll('https://', '').replaceAll('http://', '');

          return PopupMenuItem<String>(
            value: provider.id,
            height: 46,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? colors.primary.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    _getProviderIcon(provider.id),
                    size: 17,
                    color: isSelected ? colors.primary : colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                provider.name,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? colors.primary : colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (provider.isCustom) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colors.accent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Custom', style: TextStyle(fontSize: 8.5, color: colors.accent)),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${domainDisplay.isNotEmpty ? "$domainDisplay • " : ""}${provider.models.length} model • ${provider.apiKeys.length} key',
                          style: TextStyle(fontSize: 9.5, color: colors.textMuted),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAddAiProviderDialog(context, settings, colors, provider);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit_outlined, size: 14, color: colors.textMuted),
                    ),
                  ),
                  if (provider.isCustom) ...[
                    const SizedBox(width: 2),
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _confirmDeleteProvider(context, settings, colors, provider);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline_rounded, size: 14, color: const Color(0xFFEF4444)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(_getProviderIcon(settings.activeProviderId), size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      settings.aiProvider,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (settings.currentProviderDomain.isNotEmpty)
                      Text(
                        settings.currentProviderDomain.replaceAll('https://', '').replaceAll('http://', ''),
                        style: TextStyle(fontSize: 10, color: colors.textMuted),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
                ),
              ],
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAiModelDropdown(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    return PopupMenuButton<String>(
      onSelected: (model) => settings.setSelectedModel(model),
      color: colors.elevatedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (ctx) {
        final models = settings.currentProviderModels;
        final builtinMatch = AiProviderModel.defaultBuiltinProviders.firstWhere(
          (b) => b.id == settings.activeProviderId,
          orElse: () => settings.activeProvider,
        );

        return models.map((model) {
          final isSelected = model == settings.selectedModel;
          final isCustom = settings.activeProvider.isCustom || !builtinMatch.models.contains(model);

          return PopupMenuItem<String>(
            value: model,
            height: 38,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            model,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? colors.primary : colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Tùy biến', style: TextStyle(fontSize: 9, color: colors.accent)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (models.length > 1 && !isSelected)
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        settings.removeModelFromActiveProvider(model);
                      },
                      child: Icon(Icons.close_rounded, size: 14, color: colors.textMuted),
                    ),
                ],
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                settings.selectedModel,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceDropdown(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    return PopupMenuButton<String>(
      onSelected: (val) async {
        await settings.setSelectedVoice(val);
        if (context.mounted) {
          final appState = Provider.of<AppStateProvider>(context, listen: false);
          final player = Provider.of<PlayerStateProvider>(context, listen: false);
          await appState.onVoiceChanged(settings: settings, player: player);
        }
      },
      color: colors.elevatedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (ctx) {
        return settings.availableVoices.map((voice) {
          final isSelected = voice.id == settings.selectedVoiceId;
          final isCustom = !VoiceModel.defaultVoices.any((dv) => dv.id == voice.id);
          final displayName = voice.name.replaceAll('(ONNX)', '').replaceAll('.onnx', '').trim();

          return PopupMenuItem<String>(
            value: voice.id,
            height: 38,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? colors.primary : colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Tùy biến', style: TextStyle(fontSize: 9, color: colors.accent)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isCustom && !isSelected)
                    InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        settings.deleteCustomVoice(voice.id);
                      },
                      child: Icon(Icons.close_rounded, size: 14, color: colors.textMuted),
                    ),
                ],
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                settings.currentVoice.name.replaceAll('(ONNX)', '').replaceAll('.onnx', '').trim(),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFontDropdown(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    return PopupMenuButton<String>(
      onSelected: (font) => settings.setFontFamily(font),
      color: colors.elevatedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (ctx) {
        return SettingsProvider.storyFonts.map((font) {
          final isSelected = font['name'] == settings.fontFamily;
          return PopupMenuItem<String>(
            value: font['name'],
            height: 38,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  font['label'] ?? font['name']!,
                  style: TextStyle(
                    fontFamily: font['name'],
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colors.primary : colors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                settings.fontFamily,
                style: TextStyle(
                  fontFamily: settings.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  void _showPrefetchCountDialog(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    final controller = TextEditingController(text: settings.audioPrefetchCount.toString());
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: colors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.border),
          ),
          title: Row(
            children: [
              Icon(Icons.queue_music_rounded, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Số câu tải trước audio',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhập số câu muốn tải trước khi phát audio (mặc định: 5 câu):',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Nhập số câu (1 - 50)',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  fillColor: colors.cardBackground,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Gợi ý nhanh:',
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [3, 5, 10, 15, 20].map((count) {
                  final isCurrent = settings.audioPrefetchCount == count;
                  return InkWell(
                    onTap: () {
                      controller.text = count.toString();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCurrent ? colors.primary : colors.cardBackground,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isCurrent ? colors.primary : colors.border),
                      ),
                      child: Text(
                        '$count câu',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? Colors.white : colors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Hủy', style: TextStyle(color: colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final val = int.tryParse(controller.text.trim());
                if (val != null && val >= 1) {
                  settings.setAudioPrefetchCount(val);
                }
                Navigator.pop(dialogCtx);
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeDropdown(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    return PopupMenuButton<AppThemeMode>(
      onSelected: (mode) => settings.setAppThemeMode(mode),
      color: colors.elevatedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (ctx) {
        return SettingsProvider.themeOptions.map((opt) {
          final mode = opt['mode'] as AppThemeMode;
          final isSelected = mode == settings.appThemeMode;

          return PopupMenuItem<AppThemeMode>(
            value: mode,
            height: 38,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  opt['label'] as String,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colors.primary : colors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                SettingsProvider.themeOptions.firstWhere(
                  (o) => o['mode'] == settings.appThemeMode,
                  orElse: () => SettingsProvider.themeOptions.first,
                )['label'] as String,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepTimerDropdown(BuildContext context, PlayerStateProvider player, AppThemeColors colors) {
    return PopupMenuButton<int>(
      onSelected: (minutes) => player.setSleepTimerMinutes(minutes),
      color: colors.elevatedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border),
      ),
      offset: const Offset(0, 36),
      itemBuilder: (ctx) {
        return PlayerStateProvider.sleepTimerPresets.map((m) {
          final isSelected = m == player.sleepTimerMinutes;
          return PopupMenuItem<int>(
            value: m,
            height: 36,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$m phút',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? colors.primary : colors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.elevatedBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: player.sleepTimerEnabled ? colors.primary : colors.border,
            width: player.sleepTimerEnabled ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${player.sleepTimerMinutes}p',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: player.sleepTimerEnabled ? colors.primary : colors.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // API KEYS MANAGER CARD & DIALOGS
  // ===========================================================================
  Widget _buildApiKeysManagerCard(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    final currentKeys = settings.currentProviderApiKeys;

    if (currentKeys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Icon(Icons.key_off_rounded, size: 28, color: colors.textMuted),
            const SizedBox(height: 8),
            Text(
              'Chưa có API Key cho ${settings.aiProvider}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Vui lòng nhấn "Thêm Key" để nhập API key cho ${settings.aiProvider}. Hỗ trợ xoay vòng nhiều key tự động.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: colors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => _showAddApiKeyDialog(context, settings, colors),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Thêm Key Mới', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: currentKeys.length,
            separatorBuilder: (_, __) => Divider(color: colors.border, height: 10),
            itemBuilder: (context, index) {
              final key = currentKeys[index];
              final isFailed = settings.failedKeysInSession.contains(key);
              final isFirstWorking = !isFailed && settings.workingApiKeys.isNotEmpty && settings.workingApiKeys.first == key;

              // Rút gọn hiển thị key
              final displayKey = key.length > 12
                  ? '${key.substring(0, 6)}...${key.substring(key.length - 4)}'
                  : key;

              return Row(
                children: [
                  Icon(
                    isFailed
                        ? Icons.error_outline_rounded
                        : (isFirstWorking ? Icons.check_circle_rounded : Icons.vpn_key_outlined),
                    size: 16,
                    color: isFailed
                        ? const Color(0xFFEF4444)
                        : (isFirstWorking ? const Color(0xFF10B981) : colors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayKey,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: isFailed ? colors.textMuted : colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isFailed
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                    : (isFirstWorking
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : colors.elevatedBackground),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isFailed
                                  ? 'Hết quota/Lỗi phiên này'
                                  : (isFirstWorking ? 'Đang dùng' : 'Dự phòng'),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isFailed
                                    ? const Color(0xFFEF4444)
                                    : (isFirstWorking ? const Color(0xFF10B981) : colors.textMuted),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: colors.textMuted),
                  onPressed: () => settings.removeApiKeyFromActiveProvider(key),
                  tooltip: 'Xóa key này',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                ),
              ],
            );
          },
        ),
        if (settings.failedKeysInSession.isNotEmpty) ...[
          Divider(color: colors.border, height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${settings.failedKeysInSession.length} key lỗi trong phiên',
                style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
              ),
              _buildActionButton(
                label: 'Thử lại',
                icon: Icons.refresh_rounded,
                onTap: () => settings.resetFailedKeys(),
                colors: colors,
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

  void _showAddApiKeyDialog(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: colors.border)),
        title: Row(
          children: [
            Icon(Icons.vpn_key_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text('Thêm API Key (${settings.aiProvider})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nhập hoặc dán API key cho ${settings.aiProvider}:',
              style: TextStyle(fontSize: 12, color: colors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Nhập API key...',
                      hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                      fillColor: colors.elevatedBackground,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(Icons.content_paste_rounded, size: 20, color: colors.primary),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null && data!.text!.trim().isNotEmpty) {
                      controller.text = data.text!.trim();
                    }
                  },
                  tooltip: 'Dán từ clipboard',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                settings.addApiKeyToActiveProvider(key);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Thêm Key'),
          ),
        ],
      ),
    );
  }

  void _showAddModelDialog(BuildContext context, SettingsProvider settings, AppThemeColors colors) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: colors.border)),
        title: Row(
          children: [
            Icon(Icons.add_box_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text('Thêm Model (${settings.aiProvider})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nhập định danh model cho ${settings.aiProvider} (ví dụ: gemini-2.5-flash, deepseek-chat, gpt-4o-mini...):',
              style: TextStyle(fontSize: 12, color: colors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Tên model...',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                fillColor: colors.elevatedBackground,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final model = controller.text.trim();
              if (model.isNotEmpty) {
                settings.addModelToActiveProvider(model);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProvider(
    BuildContext context,
    SettingsProvider settings,
    AppThemeColors colors,
    AiProviderModel provider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: colors.border)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Text('Xóa Provider AI?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa provider "${provider.name}" và toàn bộ API key của provider này không?',
          style: TextStyle(fontSize: 12.5, color: colors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              settings.deleteCustomProvider(provider.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  void _showAddAiProviderDialog(
    BuildContext context,
    SettingsProvider settings,
    AppThemeColors colors, [
    AiProviderModel? existingProvider,
  ]) {
    final isEditing = existingProvider != null;
    final nameController = TextEditingController(text: existingProvider?.name ?? '');
    final domainController = TextEditingController(text: existingProvider?.domain ?? '');
    final modelController = TextEditingController(text: existingProvider?.selectedModel ?? '');

    final presets = [
      {'name': 'SiliconFlow', 'domain': 'https://api.siliconflow.cn/v1', 'model': 'deepseek-ai/DeepSeek-V3'},
      {'name': 'Mistral AI', 'domain': 'https://api.mistral.ai/v1', 'model': 'mistral-small-latest'},
      {'name': 'Moonshot (Kimi)', 'domain': 'https://api.moonshot.cn/v1', 'model': 'moonshot-v1-8k'},
      {'name': 'Ollama Local', 'domain': 'http://localhost:11434/v1', 'model': 'llama3.2'},
      {'name': 'LM Studio Local', 'domain': 'http://localhost:1234/v1', 'model': 'local-model'},
      {'name': 'Custom OpenAI', 'domain': 'https://api.openai.com/v1', 'model': 'gpt-4o-mini'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: colors.border)),
        title: Row(
          children: [
            Icon(isEditing ? Icons.edit_rounded : Icons.add_circle_outline_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              isEditing ? 'Sửa Provider AI' : 'Thêm Provider AI Mới',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isEditing) ...[
                Text('Mẫu cấu hình nhanh:', style: TextStyle(fontSize: 11, color: colors.textMuted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presets.map((p) {
                    return InkWell(
                      onTap: () {
                        nameController.text = p['name']!;
                        domainController.text = p['domain']!;
                        modelController.text = p['model']!;
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.elevatedBackground,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          p['name']!,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: colors.primary),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              Text('Tên Provider:', style: TextStyle(fontSize: 11.5, color: colors.textMuted)),
              const SizedBox(height: 5),
              TextField(
                controller: nameController,
                readOnly: isEditing && !existingProvider.isCustom,
                autofocus: !isEditing,
                style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ví dụ: SiliconFlow, Mistral, Ollama...',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                  fillColor: colors.elevatedBackground,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
                ),
              ),
              const SizedBox(height: 12),
              Text('Domain / Base URL (Ví dụ: https://api.openai.com/v1):',
                  style: TextStyle(fontSize: 11.5, color: colors.textMuted)),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: domainController,
                      style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'https://api.openai.com/v1',
                        hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                        fillColor: colors.elevatedBackground,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.content_paste_rounded, size: 20, color: colors.primary),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null && data!.text!.trim().isNotEmpty) {
                        domainController.text = data.text!.trim();
                      }
                    },
                    tooltip: 'Dán từ clipboard',
                  ),
                ],
              ),
              if (!isEditing) ...[
                const SizedBox(height: 12),
                Text('Model khởi tạo (Ví dụ: deepseek-chat, gpt-4o-mini...):',
                    style: TextStyle(fontSize: 11.5, color: colors.textMuted)),
                const SizedBox(height: 5),
                TextField(
                  controller: modelController,
                  style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'deepseek-chat',
                    hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                    fillColor: colors.elevatedBackground,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final domain = domainController.text.trim();
              final defaultModel = modelController.text.trim();

              if (name.isNotEmpty && domain.isNotEmpty) {
                if (isEditing) {
                  if (existingProvider.isCustom) {
                    settings.updateCustomProvider(
                      providerId: existingProvider.id,
                      name: name,
                      domain: domain,
                    );
                  } else {
                    settings.updateProviderDomain(
                      providerId: existingProvider.id,
                      domain: domain,
                    );
                  }
                } else {
                  settings.addCustomProvider(
                    name: name,
                    domain: domain,
                    defaultModel: defaultModel.isNotEmpty ? defaultModel : null,
                  );
                }
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(isEditing ? 'Lưu' : 'Thêm'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // OPTIONS HELPERS (CHECKBOX)
  // ===========================================================================
  Widget _buildCheckboxOption({
    required String title,
    required bool value,
    required AppThemeColors colors,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 18,
              color: value ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                  color: value ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 4: DONATE (ỦNG HỘ TÁC GIẢ)
  // ===========================================================================
  Widget _buildDonateTab(BuildContext context, AppThemeColors colors) {
    return ListView(
      padding: const EdgeInsets.all(14),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSectionHeader(
          icon: Icons.favorite_rounded,
          title: 'Ủng Hộ Tác Giả (Donate)',
          colors: colors,
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Nếu bạn yêu thích StorySum, hãy ủng hộ tác giả một ly cà phê để tiếp tục duy trì và phát triển ứng dụng nhé! ❤️',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Khung hiển thị mã QR
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.border.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/icons/donate.png',
                      width: 200,
                      height: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 200,
                        height: 200,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: Text(
                          'Không thể tải ảnh QR',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2 Button: Tải ảnh mã QR về máy & Chia sẻ mã QR
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadDonateImage(context, colors),
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text(
                        'Tải Mã QR',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareDonateImage(context, colors),
                      icon: Icon(Icons.share_rounded, size: 17, color: colors.primary),
                      label: Text(
                        'Chia Sẻ QR',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: colors.primary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Label số tài khoản kèm icon copy
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Số tài khoản:',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const SelectableText(
                            '0929672867',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: '0929672867'));
                        _showModalToast('Đã sao chép số tài khoản');
                      },
                      icon: Icon(
                        Icons.copy_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                      tooltip: 'Sao chép số tài khoản',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _downloadDonateImage(BuildContext context, AppThemeColors colors) async {
    try {
      final byteData = await rootBundle.load('assets/icons/donate.png');
      final bytes = byteData.buffer.asUint8List();

      if (Platform.isAndroid) {
        try {
          await [
            Permission.storage,
            Permission.photos,
          ].request();
        } catch (_) {}
      }

      final List<Directory> candidateDirs = [];

      if (Platform.isAndroid) {
        // 1. Thư mục Download chính
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          candidateDirs.add(downloadDir);
        }
        // 2. Thư mục Pictures
        final picturesDir = Directory('/storage/emulated/0/Pictures');
        if (await picturesDir.exists()) {
          candidateDirs.add(picturesDir);
        }
        // 3. getExternalStorageDirectories
        try {
          final extDownloads = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          if (extDownloads != null && extDownloads.isNotEmpty) {
            candidateDirs.addAll(extDownloads);
          }
          final extPictures = await getExternalStorageDirectories(type: StorageDirectory.pictures);
          if (extPictures != null && extPictures.isNotEmpty) {
            candidateDirs.addAll(extPictures);
          }
        } catch (_) {}

        final extDir = await getExternalStorageDirectory();
        if (extDir != null) candidateDirs.add(extDir);
      } else {
        final dl = await getDownloadsDirectory();
        if (dl != null) candidateDirs.add(dl);
      }

      final appDoc = await getApplicationDocumentsDirectory();
      candidateDirs.add(appDoc);

      String? savedPath;
      for (final dir in candidateDirs) {
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final targetPath = p.join(dir.path, 'StorySum_Donate_QR.png');
          final file = File(targetPath);
          await file.writeAsBytes(bytes, flush: true);
          savedPath = targetPath;
          break;
        } catch (_) {
          // Thử candidate kế tiếp nếu bị từ chối quyền thư mục này
          continue;
        }
      }

      if (savedPath != null) {
        _showModalToast('Đã tải thành công');
      } else {
        // Fallback lưu vào temp và gọi share sheet
        final tempDir = await getTemporaryDirectory();
        final fallbackPath = p.join(tempDir.path, 'StorySum_Donate_QR.png');
        final file = File(fallbackPath);
        await file.writeAsBytes(bytes, flush: true);

        await Share.shareXFiles(
          [XFile(fallbackPath)],
          text: 'Mã QR Donate StorySum',
        );

        _showModalToast('Đã tải thành công');
      }
    } catch (e) {
      _showModalToast('Lỗi khi tải ảnh');
    }
  }

  Future<void> _shareDonateImage(BuildContext context, AppThemeColors colors) async {
    try {
      final byteData = await rootBundle.load('assets/icons/donate.png');
      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final sharePath = p.join(tempDir.path, 'StorySum_Donate_QR.png');
      final file = File(sharePath);
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(sharePath)],
        text: 'Ủng hộ tác giả StorySum (Momo / Ngân hàng: 0929672867)',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi chia sẻ ảnh: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
