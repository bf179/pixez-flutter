/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/hello/setting/hidden_artist_page.dart';

/// 发现过滤独立设置页（仅安卓）
/// 集中管理：隐藏已关注 / 隐藏已收藏 / 隐藏公共关注库 / 关注同步 / 数据导出
class DiscoverySettingPage extends StatefulWidget {
  const DiscoverySettingPage();

  @override
  _DiscoverySettingPageState createState() => _DiscoverySettingPageState();
}

class _DiscoverySettingPageState extends State<DiscoverySettingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('发现过滤'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSectionTitle('隐藏规则'),
          Observer(builder: (_) {
            return SwitchListTile(
              secondary: const Icon(Icons.person_off_outlined),
              title: const Text('隐藏已关注画师的作品'),
              subtitle: const Text('在推荐、搜索等界面隐藏已关注画师及隐藏列表内画师的作品（插画与小说均生效）'),
              value: discoveryStore.hideFollowedArtists,
              onChanged: (v) => discoveryStore.setHideFollowedArtists(v),
            );
          }),
          Observer(builder: (_) {
            return SwitchListTile(
              secondary: const Icon(Icons.favorite_border),
              title: const Text('隐藏已收藏的作品'),
              subtitle: const Text('在推荐、搜索等界面隐藏已经收藏过的作品'),
              value: discoveryStore.hideFavoritedWorks,
              onChanged: (v) => discoveryStore.setHideFavoritedWorks(v),
            );
          }),
          Observer(builder: (_) {
            return SwitchListTile(
              secondary: const Icon(Icons.people_outline),
              title: const Text('隐藏公共关注库'),
              subtitle: const Text(
                  '关闭：只隐藏当前账号的关注；打开：所有账号的关注一并隐藏（多账号场景）'),
              value: discoveryStore.hidePublicFollowed,
              onChanged: (v) => discoveryStore.setHidePublicFollowed(v),
            );
          }),
          const Divider(),
          _buildSectionTitle('关注列表'),
          // 同步关注列表：点击后后台执行，不占用操作焦点，状态实时刷新
          Observer(builder: (_) {
            final syncing = discoveryStore.syncing;
            final status = discoveryStore.syncStatus;
            return ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('同步关注列表'),
              subtitle: Text(
                syncing
                    ? status
                    : '当前缓存 ${discoveryStore.followedUids.length} 位关注画师\n'
                        '${status.isEmpty ? '' : '$status\n'}'
                        '后台每 6 小时自动同步一次',
                maxLines: 5,
              ),
              trailing: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: () => discoveryStore.syncFollowed(),
            );
          }),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清除关注缓存'),
            subtitle: const Text('删除本账号缓存的关注画师记录（旧版本数据不兼容时使用，不影响其他账号）'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('清除关注缓存'),
                  content: const Text(
                      '将删除当前账号缓存的全部关注画师记录（不影响其他账号），确定清除？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('清除'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await discoveryStore.clearFollowedCache();
                BotToast.showText(text: '已清除关注缓存');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('导出关注列表（sqlite）'),
            subtitle: const Text('当前账号的关注列表数据库文件'),
            onTap: () async {
              BotToast.showLoading();
              final ok = await discoveryStore.exportFollowedToSqlite();
              BotToast.closeAllLoading();
              BotToast.showText(text: ok ? '已导出 sqlite 数据库' : '导出失败');
            },
          ),
          const Divider(),
          _buildSectionTitle('隐藏画师列表'),
          ListTile(
            leading: const Icon(Icons.format_list_numbered),
            title: const Text('隐藏画师列表管理'),
            subtitle: const Text('导入（txt/sqlite）/ 导出 / 搜索 / 编辑 / 清空'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const HiddenArtistPage())),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('导出隐藏画师列表（sqlite）'),
            subtitle: const Text('自配置隐藏画师列表数据库文件（对所有账号生效）'),
            onTap: () async {
              BotToast.showLoading();
              final ok = await discoveryStore.exportHiddenToSqlite();
              BotToast.closeAllLoading();
              BotToast.showText(text: ok ? '已导出 sqlite 数据库' : '导出失败');
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              '说明：隐藏画师列表对所有登录账号生效；关注列表按账号分别缓存。'
              '在作品详情页内关注/收藏不会立即隐藏当前作品，退出或切换后生效。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
