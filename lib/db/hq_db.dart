import 'dart:io';

import 'package:flutter/services.dart';
import 'package:postgres/postgres.dart';

import '../settings/key_store.dart';
import 'projects.dart';

/// Opens read-only connections. Every screen that needs data goes through [HqDb.open],
/// so these rules hold everywhere:
///   · user is always hq_reader.<ref> — HQ can't even try another role
///   · after connecting, the database must say current_user = hq_reader and
///     read-only = on, otherwise HQ disconnects and refuses
///   · SSL always on; verified against the Supabase CA if assets/certs/supabase-ca.crt exists
///   · 10 s to connect, 15 s per query
class HqDb {
  static const _caAsset = 'assets/certs/supabase-ca.crt';

  /// Connection for [project], already checked. Caller must close() it.
  static Future<Connection> open(HqProject project) async {
    final host = await KeyStore.host(project.id);
    final password = await KeyStore.passwordForConnection(project.id);
    if (host == null || password == null) {
      throw const HqDbError('Not set — add it in Settings.');
    }
    if (!KeyStore.poolerHost.hasMatch(host)) {
      throw const HqDbError('Host must be a Supabase pooler address (…pooler.supabase.com).');
    }

    final ssl = await sslSetup();
    final conn = await Connection.open(
      Endpoint(
        host: host,
        port: 5432, // session pooler
        database: 'postgres',
        username: project.readerUser,
        password: password,
      ),
      settings: ConnectionSettings(
        sslMode: ssl.mode,
        securityContext: ssl.context,
        applicationName: 'gemstok_hq',
        connectTimeout: const Duration(seconds: 10),
        queryTimeout: const Duration(seconds: 15),
      ),
    );

    try {
      final r = await conn.execute(
          "select current_user::text, current_setting('transaction_read_only')::text");
      final user = r.first[0] as String;
      final readOnly = r.first[1] as String;
      if (user != project.role) {
        throw HqDbError('Connected as "$user", not ${project.role} — refused.');
      }
      if (project.role == 'hq_reader' && readOnly != 'on') {
        throw const HqDbError('hq_reader is not read-only — fix its SQL before using HQ.');
      }
      return conn;
    } catch (_) {
      await conn.close();
      rethrow;
    }
  }

  /// Green/red check for the Settings screen.
  static Future<CheckResult> check(HqProject project) async {
    if (!await KeyStore.isSet(project.id)) return const CheckResult.notSet();
    final ssl = await sslSetup();
    final watch = Stopwatch()..start();
    Connection? conn;
    try {
      conn = await open(project);
      return CheckResult(ok: true, text: '${project.role} · ${watch.elapsedMilliseconds} ms', verified: ssl.verified);
    } on HqDbError catch (e) {
      return CheckResult(ok: false, text: e.message, verified: ssl.verified);
    } on BadCertificateException catch (e) {
      final c = e.certificate;
      return CheckResult(
          ok: false,
          text: 'SSL certificate not trusted — server sent: ${c.subject} · issued by: ${c.issuer}',
          verified: ssl.verified);
    } on ServerException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('not found') || m.contains('does not exist')) {
        return CheckResult(ok: false, text: '${project.role} doesn\'t exist in this project yet — run its SQL first.', verified: ssl.verified);
      }
      if (m.contains('password')) {
        return CheckResult(ok: false, text: 'Wrong password for hq_reader (use the one from its SQL, not postgres).', verified: ssl.verified);
      }
      return CheckResult(ok: false, text: _short(e.message), verified: ssl.verified);
    } on SocketException catch (e) {
      return CheckResult(ok: false, text: 'Can\'t reach the server: ${_short(e.message)}', verified: ssl.verified);
    } catch (e) {
      return CheckResult(ok: false, text: _short(e.toString()), verified: ssl.verified);
    } finally {
      await conn?.close();
    }
  }

  static Future<SslSetup> sslSetup() async {
    try {
      final ca = await rootBundle.load(_caAsset);
      final context = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificatesBytes(ca.buffer.asUint8List());
      return SslSetup(SslMode.verifyFull, context, verified: true);
    } catch (_) {
      // No CA file yet: still encrypted, but the server's certificate isn't checked.
      return const SslSetup(SslMode.require, null, verified: false);
    }
  }

  static String _short(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

class SslSetup {
  const SslSetup(this.mode, this.context, {required this.verified});
  final SslMode mode;
  final SecurityContext? context;
  final bool verified;
}

class CheckResult {
  const CheckResult({required this.ok, required this.text, required this.verified}) : notSet = false;
  const CheckResult.notSet()
      : ok = false,
        text = 'Not set',
        verified = false,
        notSet = true;

  final bool ok;
  final bool notSet;
  final String text;
  final bool verified; // SSL certificate checked against the Supabase CA
}

class HqDbError implements Exception {
  const HqDbError(this.message);
  final String message;
  @override
  String toString() => message;
}
