/*
 * Copyright (c) TIKI Inc.
 * MIT license. See LICENSE file in root directory.
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:tiki_trail/key.dart';
import 'package:tiki_trail/node/block/block_model.dart';
import 'package:tiki_trail/node/block/block_service.dart';
import 'package:tiki_trail/node/transaction/transaction_model.dart';
import 'package:tiki_trail/node/transaction/transaction_service.dart';
import 'package:tiki_trail/utils/merkel_tree.dart';
import 'package:uuid/uuid.dart';

import '../../fixtures/idp.dart' as idp_fixture;

void main() {
  group('Transaction Service tests', () {
    test('Create/Commit/GetPending - Success', () async {
      Database database = sqlite3.openInMemory();
      TransactionService service =
          TransactionService(database, idp_fixture.idp);
      BlockService blockService = BlockService(database);

      Key key = await idp_fixture.key;
      Uint8List contents = Uint8List.fromList(utf8.encode(const Uuid().v4()));
      Uint8List merkelProof =
          Uint8List.fromList(utf8.encode(const Uuid().v4()));

      TransactionModel transaction = await service.create(contents, key);
      List<TransactionModel> pending = service.getPending();

      expect(pending.length, 1);
      expect(pending.elementAt(0).id, transaction.id);
      expect(
          pending.elementAt(0).timestamp,
          transaction.timestamp.subtract(
              Duration(microseconds: transaction.timestamp.microsecond)));
      expect(pending.elementAt(0).version, transaction.version);
      expect(pending.elementAt(0).assetRef, transaction.assetRef);
      expect(pending.elementAt(0).userSignature, transaction.userSignature);
      expect(pending.elementAt(0).address, transaction.address);
      expect(pending.elementAt(0).contents, contents);

      BlockModel block = blockService
          .create(Uint8List.fromList(utf8.encode(const Uuid().v4())));

      service.commit(transaction.id!, block, merkelProof);
      pending = service.getPending();

      expect(pending.length, 0);
    });

    test('Create/Commit/GetByBlock - Success', () async {
      Database database = sqlite3.openInMemory();
      TransactionService service =
          TransactionService(database, idp_fixture.idp);
      BlockService blockService = BlockService(database);

      Key key = await idp_fixture.key;
      Uint8List contents = Uint8List.fromList(utf8.encode(const Uuid().v4()));
      Uint8List merkelProof =
          Uint8List.fromList(utf8.encode(const Uuid().v4()));

      TransactionModel transaction = await service.create(contents, key);
      BlockModel block = blockService
          .create(Uint8List.fromList(utf8.encode(const Uuid().v4())));

      transaction.merkelProof = merkelProof;
      transaction.block = block;
      service.commit(transaction.id!, block, merkelProof);
      blockService.commit(block);

      List<TransactionModel> transactions = service.getByBlock(block.id!);

      expect(transactions.length, 1);
      expect(transactions.elementAt(0).id, transaction.id);
      expect(
          transactions.elementAt(0).timestamp,
          transaction.timestamp.subtract(
              Duration(microseconds: transaction.timestamp.microsecond)));
      expect(transactions.elementAt(0).version, transaction.version);
      expect(transactions.elementAt(0).assetRef, transaction.assetRef);
      expect(
          transactions.elementAt(0).userSignature, transaction.userSignature);
      expect(transactions.elementAt(0).address, transaction.address);
      expect(transactions.elementAt(0).contents, contents);
      expect(transactions.elementAt(0).block?.id, block.id);
      expect(transactions.elementAt(0).merkelProof, merkelProof);
    });

    test('ValidateInclusion - Success', () async {
      Database database = sqlite3.openInMemory();
      TransactionService service =
          TransactionService(database, idp_fixture.idp);

      Key key = await idp_fixture.key;

      List<TransactionModel> transactions = [];
      List<Uint8List> hashes = [];
      for (int i = 0; i < 5; i++) {
        TransactionModel transaction = await service.create(
            Uint8List.fromList(utf8.encode(const Uuid().v4())), key);
        hashes.add(transaction.id!);
        transactions.add(transaction);
      }

      MerkelTree tree = MerkelTree.build(hashes);

      for (int i = 0; i < 5; i++) {
        transactions.elementAt(i).merkelProof =
            tree.proofs[transactions.elementAt(i).id];
        expect(
            TransactionService.validateInclusion(
                transactions.elementAt(i), tree.root!),
            true);
      }
    });

    test('ValidateAuthor - Success', () async {
      Database database = sqlite3.openInMemory();
      TransactionService service =
          TransactionService(database, idp_fixture.idp);

      Key key = await idp_fixture.key;
      TransactionModel transaction = await service.create(
          Uint8List.fromList(utf8.encode(const Uuid().v4())), key);

      expect(
          await TransactionService.validateAuthor(
              transaction, key.id, idp_fixture.idp),
          true);
    });

    test('ValidateIntegrity - Success', () async {
      Database database = sqlite3.openInMemory();
      TransactionService service =
          TransactionService(database, idp_fixture.idp);

      Key key = await idp_fixture.key;
      TransactionModel transaction = await service.create(
          Uint8List.fromList(utf8.encode(const Uuid().v4())), key);

      expect(TransactionService.validateIntegrity(transaction), true);
    });
  });
}
