import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用版本号（与 pubspec.yaml 同步维护）。
const String kAppVersion = '1.0.4';
const String kAppBuildNumber = '5';

/// 关于页面（Phase 9-4）。
///
/// 显示版本号、检查更新、使用帮助、反馈与建议。
/// 检查更新预留入口（Phase 11 接线），反馈跳 GitHub Issues。
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsAbout)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 顶部 App 信息卡
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainerLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        CupertinoIcons.book,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    const Text(
                      'AI 错题本',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      '版本 $kAppVersion（build $kAppBuildNumber）',
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xl),

            AppSectionTitle(AppStrings.settingsAboutVersion),
            const SizedBox(height: AppSpace.md),
            AppCard(
              child: Column(
                children: <Widget>[
                  AppListTile(
                    icon: CupertinoIcons.info_circle,
                    iconColor: AppColors.info,
                    iconBackgroundColor: AppColors.infoContainerLight,
                    title: '当前版本',
                    subtitle: '$kAppVersion+$kAppBuildNumber',
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.arrow_down_circle,
                    iconColor: AppColors.primary,
                    iconBackgroundColor: AppColors.primaryContainerLight,
                    title: AppStrings.settingsAboutCheckUpdate,
                    subtitle: AppStrings.settingsAboutCheckUpdateSubtitle,
                    onTap: _checkUpdate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),

            AppSectionTitle('帮助与反馈'),
            const SizedBox(height: AppSpace.md),
            AppCard(
              child: Column(
                children: <Widget>[
                  AppListTile(
                    icon: CupertinoIcons.question_circle,
                    iconColor: AppColors.accentTeal,
                    iconBackgroundColor: AppColors.accentTealContainerLight,
                    title: AppStrings.settingsAboutHelp,
                    subtitle: AppStrings.settingsAboutHelpSubtitle,
                    onTap: _showHelp,
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.envelope,
                    iconColor: AppColors.accentAmber,
                    iconBackgroundColor: AppColors.accentAmberContainerLight,
                    title: AppStrings.settingsAboutFeedback,
                    subtitle: AppStrings.settingsAboutFeedbackSubtitle,
                    onTap: _openFeedback,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Center(
              child: Text(
                'Made with Flutter',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdate() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('检查更新'),
        content: const Text('检查更新功能将在后续版本上线，敬请期待。'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHelp() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用帮助'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('· 首页：查看今日行动、科目掌握度、学习趋势'),
              SizedBox(height: 8),
              Text('· 添加：拍照或选图录入错题'),
              SizedBox(height: 8),
              Text('· 错题本：浏览、筛选、查看错题详情'),
              SizedBox(height: 8),
              Text('· 复习：按计划复习，评分后自动更新掌握度'),
              SizedBox(height: 8),
              Text('· 知识树：按学科查看知识点结构与薄弱点'),
              SizedBox(height: 8),
              Text('· 设置：调整 AI 服务、外观、学习偏好等'),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _openFeedback() async {
    const url = 'https://github.com/joeshu/smart-wrong-notebook/issues';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器，请手动访问 GitHub Issues')),
      );
    }
  }
}
