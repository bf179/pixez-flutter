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
final String tableFollowedArtist = 'followedartist';

class FollowedArtistPersist {
  String userId;
  String name;
  int? id;

  FollowedArtistPersist({required this.userId, required this.name, this.id});

  factory FollowedArtistPersist.fromJson(Map<String, dynamic> json) {
    return FollowedArtistPersist(
      id: json[followedColumnId],
      userId: json[followedColumnUserId],
      name: json[followedColumnName] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      followedColumnId: id,
      followedColumnUserId: userId,
      followedColumnName: name,
    };
  }
}

class FollowedArtistProvider {
  late Database db;

  Future open() async {
    String databasesPath = (await getDatabasesPath());
    String path = join(databasesPath, 'followedartist.db');
    db = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      await db.execute('''
create table $tableFollowedArtist ( 
  $followedColumnId integer primary key autoincrement, 
  $followedColumnUserId text not null unique,
  $followedColumnName text not null
  )
''');
    });
  }

  Future<FollowedArtistPersist> insert(FollowedArtistPersist todo) async {
    todo.id = await db.insert(tableFollowedArtist, todo.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return todo;
  }

  Future<FollowedArtistPersist?> getByUserId(String userId) async {
    List<Map<String, dynamic>> maps = await db.query(tableFollowedArtist,
        columns: [followedColumnId, followedColumnUserId, followedColumnName],
        where: '$followedColumnUserId = ?',
        whereArgs: [userId]);
    if (maps.isNotEmpty) return FollowedArtistPersist.fromJson(maps.first);
    return null;
  }

  Future<List<FollowedArtistPersist>> getAll() async {
    List<Map<String, dynamic>> maps = await db.query(tableFollowedArtist,
        columns: [followedColumnId, followedColumnUserId, followedColumnName]);
    return maps.map((f) => FollowedArtistPersist.fromJson(f)).toList();
  }

  Future<int> delete(int id) async {
    return await db.delete(tableFollowedArtist,
        where: '$followedColumnId = ?', whereArgs: [id]);
  }

  Future<int> deleteAll() async {
    return await db.delete(tableFollowedArtist);
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
