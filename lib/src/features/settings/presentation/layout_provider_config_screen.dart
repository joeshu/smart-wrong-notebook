import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/data/services/provider_connection_test_service.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_feedback.dart';

class LayoutProviderConfigScreen extends ConsumerStatefulWidget {
  const LayoutProviderConfigScreen({super.key});
  @override
  ConsumerState<LayoutProviderConfigScreen> createState() => _LayoutProviderConfigScreenState();
}

class _LayoutProviderConfigScreenState extends ConsumerState<LayoutProviderConfigScreen> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _secondaryKey;
  LayoutProviderType _type = LayoutProviderType.currentVision;
  bool _loaded = false;
  bool _saving = false;
  bool _testing = false;
  ConnectionTestResult? _testResult;
  bool _hasStoredPaddle = false;
  bool _hasStoredMineru = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController();
    _key = TextEditingController();
    _secondaryKey = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _secondaryKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    final config = await restoreLayoutProviderConfig(ref);
    final layoutRepository = ref.read(layoutProviderRepositoryProvider);
    final paddle = await layoutRepository.readPaddleToken();
    final mineru = await layoutRepository.readMineruToken();
    if (!mounted) return;
    setState(() {
      _type = config.type;
      _url.text = config.baseUrl;
      _key.text = config.apiKey;
      _secondaryKey.text = config.secondaryApiKey;
      _hasStoredPaddle = paddle.isNotEmpty;
      _hasStoredMineru = mineru.isNotEmpty;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('试卷版面识别')),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const Text('候选题框来源', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        RadioGroup<LayoutProviderType>(
          groupValue: _type,
          onChanged: (v) {
            if (v != null) setState(() => _type = v);
          },
          child: Column(
            children: <Widget>[
              RadioListTile<LayoutProviderType>(
                value: LayoutProviderType.currentVision,
                title: const Text('当前 AI 视觉模型'),
                subtitle: const Text('零额外配置；复用 AI 服务商配置生成候选框。'),
              ),
              RadioListTile<LayoutProviderType>(
                value: LayoutProviderType.paddleCloud,
                title: const Text('PaddleOCR AI Studio（PP-StructureV3）'),
                subtitle: const Text('云端异步识别；Token 安全存储，不写入备份或日志。'),
              ),
              RadioListTile<LayoutProviderType>(
                value: LayoutProviderType.mineruCloud,
                title: const Text('MinerU 精准解析（VLM）'),
                subtitle: const Text('适合公式、多栏和复杂扫描试卷；按题号聚合为候选题框。'),
              ),
              RadioListTile<LayoutProviderType>(
                value: LayoutProviderType.autoCloud,
                title: const Text('自动：PaddleOCR 优先，MinerU 兜底'),
                subtitle: const Text('先走快速识别；题框数量、覆盖率或重叠异常时自动升级 VLM。'),
              ),
              RadioListTile<LayoutProviderType>(
                value: LayoutProviderType.customHttp,
                title: const Text('NAS / MinerU / 自定义 HTTP 服务'),
                subtitle: const Text('适用于 PP-Structure Docker、MinerU 网关或自建版面服务。'),
              ),
              RadioListTile<LayoutProviderType>(
                value: LayoutProviderType.manualOnly,
                title: const Text('仅手动框选'),
                subtitle: const Text('不上传整页试卷到任何版面识别服务。'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ConfigurationStatusCard(
          type: _type,
          apiKey: _key.text,
          secondaryApiKey: _secondaryKey.text,
          loaded: _loaded,
          hasStoredToken: _type == LayoutProviderType.mineruCloud ? _hasStoredMineru : _hasStoredPaddle,
          hasStoredSecondaryToken: _hasStoredMineru,
        ),
        const SizedBox(height: 12),
        _ConnectionTestPanel(
          testing: _testing,
          result: _testResult,
          onPaddle: () => _testConnection(_ConnectionTarget.paddle),
          onMineru: () => _testConnection(_ConnectionTarget.mineru),
          onAi: () => _testConnection(_ConnectionTarget.ai),
        ),
        if (_type == LayoutProviderType.customHttp || _type == LayoutProviderType.paddleCloud || _type == LayoutProviderType.mineruCloud || _type == LayoutProviderType.autoCloud) ...<Widget>[
          const SizedBox(height: 16),
          if (_type == LayoutProviderType.customHttp)
            TextField(controller: _url, keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: '服务地址', hintText: 'http://nas.local:8000')),
          if (_type == LayoutProviderType.customHttp) const SizedBox(height: 12),
          TextField(controller: _key, obscureText: true,
              decoration: InputDecoration(
                labelText: _type == LayoutProviderType.paddleCloud ? 'AI Studio Token' : _type == LayoutProviderType.mineruCloud ? 'MinerU Token' : _type == LayoutProviderType.autoCloud ? 'PaddleOCR AI Studio Token' : '访问令牌（可选）',
                hintText: _type == LayoutProviderType.paddleCloud ? 'PaddleOCR AI Studio Token 将安全存储' : _type == LayoutProviderType.mineruCloud ? '在 MinerU API 管理页面创建的 Token 将安全存储' : _type == LayoutProviderType.autoCloud ? '快速优先服务的 Token，将安全存储' : 'Bearer Token 将安全存储',
              )),
          if (_type == LayoutProviderType.autoCloud) ...<Widget>[
            const SizedBox(height: 12),
            TextField(controller: _secondaryKey, obscureText: true,
              decoration: const InputDecoration(labelText: 'MinerU Token', hintText: '兜底 VLM 服务的 Token，将安全存储')),
          ],
          const SizedBox(height: 12),
          if (_type == LayoutProviderType.customHttp) const _ProtocolCard()
          else if (_type == LayoutProviderType.paddleCloud) const _PaddleCloudCard()
          else if (_type == LayoutProviderType.mineruCloud) const _MineruCloudCard()
          else const _AutoCloudCard(),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存...' : '保存版面识别设置'),
        ),
      ]),
    );
  }

  Future<void> _testConnection(_ConnectionTarget target) async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final service = ProviderConnectionTestService();
    final layoutRepository = ref.read(layoutProviderRepositoryProvider);
    // cloud 模式下优先用文本框里的 Token；文本框为空时回退到系统安全存储
    // 中已保存（且已验证可用）的 Token，避免“已调通却因文本框为空而测失败”。
    final paddleStored = await layoutRepository.readPaddleToken();
    final mineruStored = await layoutRepository.readMineruToken();
    final paddleToken = _type == LayoutProviderType.paddleCloud ||
            _type == LayoutProviderType.autoCloud
        ? (_key.text.trim().isNotEmpty ? _key.text.trim() : paddleStored)
        : paddleStored;
    final mineruToken = _type == LayoutProviderType.mineruCloud
        ? (_key.text.trim().isNotEmpty ? _key.text.trim() : mineruStored)
        : _type == LayoutProviderType.autoCloud
            ? (_secondaryKey.text.trim().isNotEmpty
                ? _secondaryKey.text.trim()
                : mineruStored)
            : mineruStored;
    final result = switch (target) {
      _ConnectionTarget.paddle => await service.testPaddle(paddleToken),
      _ConnectionTarget.mineru => await service.testMineru(mineruToken),
      _ConnectionTarget.ai => await service.testAi(
          await ref.read(settingsRepositoryProvider).getAiProviderConfig(),
        ),
    };
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _save() async {
    if (_type == LayoutProviderType.customHttp && _url.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写 NAS 或云 API 服务地址')));
      return;
    }
    if ((_type == LayoutProviderType.paddleCloud || _type == LayoutProviderType.mineruCloud) && _key.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_type == LayoutProviderType.mineruCloud ? '请填写 MinerU Token' : '请填写 PaddleOCR AI Studio Token')));
      return;
    }
    if (_type == LayoutProviderType.autoCloud && (_key.text.trim().isEmpty || _secondaryKey.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自动策略需要同时填写 PaddleOCR 与 MinerU Token')));
      return;
    }
    setState(() => _saving = true);
    await persistLayoutProviderConfig(ref, LayoutProviderConfig(type: _type, baseUrl: _url.text.trim(), apiKey: _key.text.trim(), secondaryApiKey: _secondaryKey.text.trim()));
    if (!mounted) return;
    setState(() => _saving = false);
    AppHaptics.success();
    AppToast.success(context, '版面识别设置已保存');
  }
}

class _MineruCloudCard extends StatelessWidget {
  const _MineruCloudCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '服务：MinerU 精准解析 API（VLM）\n应用会申请临时上传地址、上传当前整页图片并轮询解析任务，然后从结果 ZIP 的版面块按题号聚合候选题框。Token 仅使用系统安全存储；整页会上传至 MinerU。候选框必须由你确认后才会裁切入库。',
  );
}

class _PaddleCloudCard extends StatelessWidget {
  const _PaddleCloudCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '服务：PaddleOCR AI Studio · PP-StructureV3\n应用会上传当前整页图片并轮询异步任务；仅将候选框保留在本地。Token 使用系统安全存储，不会写入导出文件、备份或诊断日志。识别结果仍须人工确认后才能裁切入库。',
  );
}

class _AutoCloudCard extends StatelessWidget {
  const _AutoCloudCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '自动策略：先调用 PaddleOCR；仅当候选框少于 2 个、覆盖率异常或候选框严重重叠时，才自动升级 MinerU VLM。两个服务的 Token 分别安全存储；任一候选结果都必须人工确认。',
  );
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard();
  @override
  Widget build(BuildContext context) => _InfoCard(
    '接口协议\nPOST /v1/layout/question-regions\nContent-Type: multipart/form-data，字段 file\n返回：{"provider":"paddle-pp-structure","regions":[{"number":"1","x":0.05,"y":0.08,"width":0.9,"height":0.18,"confidence":0.92}]}\n坐标必须为 0~1 归一化值；结果仅作为可编辑候选框。',
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: isDark ? AppColors.accentTealContainerLight.withValues(alpha: 0.12) : AppColors.accentTealContainerLight, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 12, color: isDark ? AppColors.accentTealLight : AppColors.accentTeal)),
    );
  }
}


class _ConfigurationStatusCard extends StatelessWidget {
  const _ConfigurationStatusCard({
    required this.type,
    required this.apiKey,
    required this.secondaryApiKey,
    required this.loaded,
    this.hasStoredToken = false,
    this.hasStoredSecondaryToken = false,
  });
  final LayoutProviderType type;
  final String apiKey;
  final String secondaryApiKey;
  final bool loaded;
  final bool hasStoredToken;
  final bool hasStoredSecondaryToken;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 文本框有字 或 安全存储里确有对应 Token，均视为“已具备凭据”。
    final paddleReady = type == LayoutProviderType.paddleCloud &&
        (apiKey.trim().isNotEmpty || hasStoredToken);
    final mineruReady = type == LayoutProviderType.mineruCloud &&
        (apiKey.trim().isNotEmpty || hasStoredToken);
    final autoReady = type == LayoutProviderType.autoCloud &&
        (apiKey.trim().isNotEmpty || hasStoredToken) &&
        (secondaryApiKey.trim().isNotEmpty || hasStoredSecondaryToken);
    final ready = type == LayoutProviderType.currentVision ||
        type == LayoutProviderType.manualOnly ||
        type == LayoutProviderType.customHttp ||
        paddleReady ||
        mineruReady ||
        autoReady;
    final text = !loaded
        ? '正在读取已保存的配置…'
        : ready
            ? '配置可用：导入整页试卷后，在“整页框选切题”页面点击识别即可看到实际服务名称和耗时。'
            : '配置不完整：已选择服务，但安全存储中未读到所需 Token。请重新填写并保存。';
    final color = ready
        ? (isDark ? AppColors.successLight : AppColors.successDark)
        : (isDark ? AppColors.warningLight : AppColors.warningDark);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: .3))),
      child: Row(children: <Widget>[
        Icon(ready ? CupertinoIcons.checkmark_shield : CupertinoIcons.exclamationmark_triangle, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
      ]),
    );
  }
}


enum _ConnectionTarget { paddle, mineru, ai }

class _ConnectionTestPanel extends StatelessWidget {
  const _ConnectionTestPanel({
    required this.testing,
    required this.result,
    required this.onPaddle,
    required this.onMineru,
    required this.onAi,
  });
  final bool testing;
  final ConnectionTestResult? result;
  final VoidCallback onPaddle;
  final VoidCallback onMineru;
  final VoidCallback onAi;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = result == null
        ? AppColors.slateDark
        : result!.ok
            ? (isDark ? AppColors.successLight : AppColors.successDark)
            : (isDark ? AppColors.dangerLight : AppColors.dangerDark);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slateContainerDark : AppColors.slateContainerLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppColors.slateContainerLight : AppColors.slateLight.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Text('测试连接', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('测试会验证实际接口：PaddleOCR 提交最小任务、MinerU 创建上传任务、普通 AI 发起最小文本请求；不会上传你的试卷。', style: TextStyle(fontSize: 12, color: isDark ? AppColors.slateLight : AppColors.slate)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          OutlinedButton.icon(onPressed: testing ? null : onPaddle, icon: const Icon(CupertinoIcons.checkmark_shield, size: 16), label: const Text('测试 PaddleOCR')),
          OutlinedButton.icon(onPressed: testing ? null : onMineru, icon: const Icon(CupertinoIcons.doc_text_search, size: 16), label: const Text('测试 MinerU')),
          OutlinedButton.icon(onPressed: testing ? null : onAi, icon: const Icon(CupertinoIcons.sparkles, size: 16), label: const Text('测试普通 AI')),
        ]),
        if (testing) const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Row(children: <Widget>[SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('正在发起真实服务测试…', style: TextStyle(fontSize: 12))]),
        ),
        if (result != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: .28))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[Icon(result!.ok ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: color), const SizedBox(width: 6), Expanded(child: Text(result!.title, style: TextStyle(fontWeight: FontWeight.w700, color: color))), Text('${result!.elapsed.inMilliseconds}ms', style: TextStyle(fontSize: 12, color: color))]),
              const SizedBox(height: 4),
              Text(result!.detail, style: const TextStyle(fontSize: 12, height: 1.35)),
            ]),
          ),
        ),
      ]),
    );
  }
}
