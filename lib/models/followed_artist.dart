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
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final String followedColumnId = 'id';
final String followedColumnUserId = 'user_id';
final String followedColumnName = 'name';
final String followedColumnAccountId = 'account_id';
final String tableFollowedArtist = 'followedartist';

class FollowedArtistPersist {
  String userId;
  String name;

  /// 所属登录账号（该账号的 userId）；null 表示旧数据/公共记录
  String? accountId;
  int? id;

  FollowedArtistPersist(
      {required this.userId, required this.name, this.accountId, this.id});

  factory FollowedArtistPersist.fromJson(Map<String, dynamic> json) {
    return FollowedArtistPersist(
      id: json[followedColumnId],
      userId: json[followedColumnUserId],
      name: json[followedColumnName] ?? '',
      accountId: json[followedColumnAccountId]?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      followedColumnId: id,
      followedColumnUserId: userId,
      followedColumnName: name,
      followedColumnAccountId: accountId,
    };
  }
}

class FollowedArtistProvider {
  late Database db;

  Future open() async {
    String databasesPath = (await getDatabasesPath());
    String path = join(databasesPath, 'followedartist.db');
    db = await openDatabase(path, version: 2,
        onCreate: (Database db, int version) async {
      await db.execute('''
create table $tableFollowedArtist ( 
  $followedColumnId integer primary key autoincrement, 
  $followedColumnUserId text not null,
  $followedColumnName text not null,
  $followedColumnAccountId text
  )
''');
      await db.execute(
          'create unique index idx_followed_account_uid on $tableFollowedArtist ($followedColumnAccountId, $followedColumnUserId)');
    }, onUpgrade: (Database db, int oldVersion, int newVersion) async {
      if (oldVersion < 2) {
        // 老版本只有 user_id 唯一约束，先去掉再补 account 维度唯一索引
        try {
          await db.execute('drop index if exists idx_followed_uid');
        } catch (e) {}
        try {
          await db.execute(
              'alter table $tableFollowedArtist add column $followedColumnAccountId text');
        } catch (e) {}
        try {
          await db.execute(
              'create unique index if not exists idx_followed_account_uid on $tableFollowedArtist ($followedColumnAccountId, $followedColumnUserId)');
        } catch (e) {}
      }
    });
  }

  Future<FollowedArtistPersist> insert(FollowedArtistPersist todo) async {
    todo.id = await db.insert(tableFollowedArtist, todo.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return todo;
  }

  Future<FollowedArtistPersist?> getByUserId(
      String userId, String? accountId) async {
    // accountId 为 null 时匹配旧数据（account_id IS NULL）的公共记录
    final where = accountId == null
        ? '$followedColumnUserId = ? AND $followedColumnAccountId IS NULL'
        : '$followedColumnUserId = ? AND $followedColumnAccountId = ?';
    final args = accountId == null ? [userId] : [userId, accountId];
    List<Map<String, dynamic>> maps = await db.query(tableFollowedArtist,
        columns: [
          followedColumnId,
          followedColumnUserId,
          followedColumnName,
          followedColumnAccountId
        ],
        where: where,
        whereArgs: args);
    if (maps.isNotEmpty) return FollowedArtistPersist.fromJson(maps.first);
    return null;
  }

  Future<List<FollowedArtistPersist>> getAll() async {
    List<Map<String, dynamic>> maps = await db.query(tableFollowedArtist,
        columns: [
          followedColumnId,
          followedColumnUserId,
          followedColumnName,
          followedColumnAccountId
        ]);
    return maps.map((f) => FollowedArtistPersist.fromJson(f)).toList();
  }

  Future<List<FollowedArtistPersist>> getByAccount(String? accountId) async {
    // accountId 为 null 时匹配旧数据（account_id IS NULL）的公共记录
    final where = accountId == null
        ? '$followedColumnAccountId IS NULL'
        : '$followedColumnAccountId = ?';
    final args = accountId == null ? [] : [accountId];
    List<Map<String, dynamic>> maps = await db.query(tableFollowedArtist,
        columns: [
          followedColumnId,
          followedColumnUserId,
          followedColumnName,
          followedColumnAccountId
        ],
        where: where,
        whereArgs: args);
    return maps.map((f) => FollowedArtistPersist.fromJson(f)).toList();
  }

  Future<int> delete(int id) async {
    return await db.delete(tableFollowedArtist,
        where: '$followedColumnId = ?', whereArgs: [id]);
  }

  Future<int> deleteAll() async {
    return await db.delete(tableFollowedArtist);
  }

  Future<int> deleteByAccount(String? accountId) async {
    // accountId 为 null 时必须用 IS NULL 才能匹配旧数据的公共记录
    final where = accountId == null
        ? '$followedColumnAccountId IS NULL'
        : '$followedColumnAccountId = ?';
    final args = accountId == null ? [] : [accountId];
    return await db.delete(tableFollowedArtist,
        where: where, whereArgs: args);
  }

  Future<int> update(FollowedArtistPersist todo) async {
    return await db.update(tableFollowedArtist, todo.toJson(),
        where: '$followedColumnId = ?', whereArgs: [todo.id]);
  }

  Future<List<FollowedArtistPersist>> insertAll(
      List<FollowedArtistPersist> list) async {
    await db.transaction((txn) async {
      for (var todo in list) {
        todo.id = await txn.insert(tableFollowedArtist, todo.toJson(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    return list;
  }

  Future close() async => db.close();
}
