import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class ProviderConfigScreen extends ConsumerStatefulWidget {
  const ProviderConfigScreen({super.key});

  @override
  ConsumerState<ProviderConfigScreen> createState() =>
      _ProviderConfigScreenState();
}

class _ProviderConfigScreenState extends ConsumerState<ProviderConfigScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _timeoutController;
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _loaded = false;
  bool _testing = false;
  bool _obscureApiKey = true;
  String? _testResult;
  AiServiceType _serviceType = AiServiceType.openai;
  bool _isPrivate = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _modelController = TextEditingController();
    _apiKeyController = TextEditingController();
    _timeoutController = TextEditingController(text: '60');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfig());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    if (_loaded) return;
    final config =
        await ref.read(settingsRepositoryProvider).getAiProviderConfig();
    if (config != null && mounted) {
      _urlController.text = config.baseUrl;
      _modelController.text = config.model;
      _apiKeyController.text = config.apiKey;
      _timeoutController.text = config.timeoutSeconds.toString();
      setState(() {
        _serviceType = config.serviceType;
        _isPrivate = config.isPrivate;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final success = _testResult?.contains('成功') ?? false;
    final statusColor = success ? AppColors.success : AppColors.warning;
    final statusBg = success
        ? AppColors.successContainerLight
        : AppColors.warningContainerLight;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.providerConfigTitle),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/settings/provider'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              TextFormField(
                controller: _urlController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? AppStrings.providerConfigUrlRequired
                    : null,
                decoration: const InputDecoration(
                  labelText: AppStrings.providerConfigUrlLabel,
                  hintText: AppStrings.providerConfigUrlHint,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('私有服务'),
                subtitle: const Text('仅在确认数据不会发送到公共云服务时开启'),
                value: _isPrivate,
                onChanged: (value) => setState(() => _isPrivate = value),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _modelController,
                validator: (value) => value == null || value.trim().isEmpty
                    ? AppStrings.providerConfigModelRequired
                    : null,
                decoration: const InputDecoration(
                  labelText: AppStrings.providerConfigModelLabel,
                  hintText: AppStrings.providerConfigModelHint,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _apiKeyController,
                obscureText: _obscureApiKey,
                validator: (value) => value == null || value.trim().isEmpty
                    ? AppStrings.providerConfigApiKeyRequired
                    : null,
                decoration: InputDecoration(
                  labelText: AppStrings.providerConfigApiKeyLabel,
                  hintText: AppStrings.providerConfigApiKeyHint,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureApiKey
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash),
                    onPressed: () => setState(
                        () => _obscureApiKey = !_obscureApiKey),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Phase 12-3：AI 服务类型下拉（OpenAI / Anthropic / 自定义）。
              DropdownButtonFormField<AiServiceType>(
                value: _serviceType,
                decoration: const InputDecoration(
                  labelText: 'AI 服务类型',
                  hintText: '选择上游协议约定',
                ),
                items: AiServiceType.values
                    .map((type) => DropdownMenuItem<AiServiceType>(
                          value: type,
                          child: Text(type.label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _serviceType = value);
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.only(
                    left: AppSpace.sm, top: AppSpace.xs, right: AppSpace.sm),
                child: Text(
                  _serviceType.hint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Phase 12-3：单次请求超时秒数。
              TextFormField(
                controller: _timeoutController,
                keyboardType: TextInputType.number,
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  final n = int.tryParse(raw);
                  if (n == null || n <= 0) {
                    return '请输入大于 0 的整数（默认 60 秒）';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: '请求超时（秒）',
                  hintText: '默认 60，超大题量可调到 120',
                  suffixText: '秒',
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              if (_testResult != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark
                        ? statusColor.withValues(alpha: 0.14)
                        : statusBg,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    border: Border.all(
                      color: statusColor.withValues(alpha: isDark ? 0.35 : 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        success
                            ? CupertinoIcons.checkmark_circle
                            : CupertinoIcons.exclamationmark_triangle,
                        color: statusColor,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? statusColor
                                : (success
                                    ? AppColors.successDark
                                    : AppColors.warningDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(CupertinoIcons.wifi, size: 18),
                      label: Text(_testing
                          ? AppStrings.providerConfigTesting
                          : AppStrings.providerConfigTest),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading ? null : _save,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(AppStrings.providerConfigSave),
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _testResult = null;
    });
    final config = AiProviderConfig(
      id: 'default',
      displayName: '默认',
      baseUrl: _urlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      timeoutSeconds: int.parse(_timeoutController.text.trim()),
      serviceType: _serviceType,
      isPrivate: _isPrivate,
    );
    await ref.read(settingsRepositoryProvider).saveAiProviderConfig(config);
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(AppStrings.providerConfigSaved)));
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final config = AiProviderConfig(
      id: 'default',
      displayName: '默认',
      baseUrl: _urlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      timeoutSeconds: int.parse(_timeoutController.text.trim()),
      serviceType: _serviceType,
      isPrivate: _isPrivate,
    );

    setState(() {
      _testing = true;
      _testResult = '正在保存配置...\nURL: ${config.baseUrl}\n模型: ${config.model}';
    });

    try {
      debugPrint('[ProviderConfig] Saving config...');
      await ref.read(settingsRepositoryProvider).saveAiProviderConfig(config);
      debugPrint('[ProviderConfig] Config saved successfully');

      final savedConfig =
          await ref.read(settingsRepositoryProvider).getAiProviderConfig();
      debugPrint(
          '[ProviderConfig] Saved config: ${savedConfig?.baseUrl}, ${savedConfig?.model}');

      if (savedConfig == null) {
        setState(() => _testResult = AppStrings.providerConfigSaveFailed);
        return;
      }

      setState(() => _testResult =
          '配置已保存，正在连接 AI...\nURL: ${savedConfig.baseUrl}\n模型: ${savedConfig.model}');

      final service = ref.read(aiAnalysisServiceProvider);
      await service.testConnection(savedConfig);

      if (mounted) {
        setState(() => _testResult = AppStrings.providerConfigTestSuccess);
      }
    } catch (e) {
      debugPrint('[ProviderConfig] Test failed: $e');
      if (mounted) {
        setState(() => _testResult =
            '${AppStrings.providerConfigTestFailed}${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }
}
