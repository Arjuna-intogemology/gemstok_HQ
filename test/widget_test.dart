import 'package:flutter_test/flutter_test.dart';
import 'package:gemstok_hq/db/projects.dart';
import 'package:gemstok_hq/settings/key_store.dart';

void main() {
  test('only Supabase pooler hosts are accepted', () {
    expect(KeyStore.poolerHost.hasMatch('aws-0-ap-south-1.pooler.supabase.com'), isTrue);
    expect(KeyStore.poolerHost.hasMatch('db.odcwzqiwfngozjztnfzm.supabase.co'), isFalse);
    expect(KeyStore.poolerHost.hasMatch('evil.com/pooler.supabase.com'), isFalse);
    expect(KeyStore.poolerHost.hasMatch('pooler.supabase.com.evil.com'), isFalse);
  });

  test('HQ always connects as hq_reader.<ref>', () {
    for (final p in hqProjects) {
      expect(p.readerUser, 'hq_reader.${p.ref}');
    }
  });
}
