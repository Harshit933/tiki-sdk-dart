/*
 * Copyright (c) TIKI Inc.
 * MIT license. See LICENSE file in root directory.
 */

import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import '../shared_storage/shared_storage.dart';
import 'node_service.dart';
import 'xchain/xchain_service.dart';

import 'l0_storage.dart';

export './backup/backup_service.dart';
export './block/block_service.dart';
export './key/key_service.dart';
export './transaction/transaction_service.dart';
export '../shared_storage/wasabi/wasabi_service.dart';

class NodeServiceBuilder {
  KeyModel? _primaryKey;
  L0Storage? _l0Storage;
  Database? database;
  KeyStorage? _keyStorage;
  String? _apiKey;
  List<String> _readOnly = [];
  Duration _blockInterval = const Duration(minutes: 1);
  int _maxTransactions = 200;
  String _databaseDir = '';
  String? _address;

  set l0Storage(L0Storage? val) => _l0Storage = val;
  set apiKey(String? apiKey) => _apiKey = apiKey;
  set readOnly(List<String> val) => _readOnly = val;
  set keyStorage(KeyStorage val) => _keyStorage = val;
  set blockInterval(Duration val) => _blockInterval = val;
  set maxTransactions(int val) => _maxTransactions = val;
  set databaseDir(String val) => _databaseDir = val;
  set address(String? val) => _address = val;

  Future<NodeService> build() async {
    _loadStorage();
    await _loadPrimaryKey();
    sqlite3.open("$_databaseDir/${base64Url.encode(_primaryKey!.address)}.db");
    NodeService nodeService = NodeService();
    nodeService.blockInterval = _blockInterval;
    nodeService.maxTransactions = _maxTransactions;
    nodeService.transactionService = TransactionService(database!);
    nodeService.blockService = BlockService(database!);
    nodeService.xchainService = XchainService(_l0Storage!, database!);
    nodeService.backupService = BackupService(
        _l0Storage!, database!, _primaryKey!, nodeService.getBlock);
    nodeService.readOnly = _readOnly;
    nodeService.primaryKey = _primaryKey!;
    await nodeService.init();
    return nodeService;
  }

  Future<void> _loadPrimaryKey() async {
    if (_keyStorage == null) {
      throw Exception('Keystore must be set to build NodeService');
    }
    KeyService keyService = KeyService(_keyStorage!);
    if (_address != null) {
      KeyModel? key = await keyService.get(_address!);
      if (key != null) {
        _primaryKey = key;
        return;
      }
    }
    _primaryKey = await keyService.create();
    return;
  }

  void _loadStorage() {
    if (_l0Storage == null && _apiKey == null) {
      throw Exception(
          'Please provide an apiKey or a L0Storage implementation for chain backup.');
    } else if (_apiKey != null) {
      _l0Storage = SharedStorage(_apiKey!, _primaryKey!.privateKey);
    }
  }
}
