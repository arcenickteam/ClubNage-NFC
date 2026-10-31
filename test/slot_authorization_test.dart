import 'package:flutter_test/flutter_test.dart';
import '../lib/models.dart';
import '../lib/services/slot_authorization.dart';

Member person(String slots, {List<String> groups = const []}) => Member(
  id: '1', firstName: 'Test', lastName: 'Nageur', groups: groups,
  nfcUid: '', qrToken: '', authorizedSlots: slots,
);

void main() {
  test('Plusieurs créneaux explicites', () {
    expect(SlotAuthorization.permission(person('Adultes, Junior'), 'Junior'), SlotPermission.authorized);
    expect(SlotAuthorization.permission(person('Adultes; Junior'), 'Adultes'), SlotPermission.authorized);
  });
  test('Exception même famille Aqua', () {
    expect(SlotAuthorization.permission(person('Aqua M1'), 'Aqua M2'), SlotPermission.sameFamilyException);
  });
  test('Refus entre familles', () {
    expect(SlotAuthorization.permission(person('Adultes'), 'Junior'), SlotPermission.denied);
  });
  test('RVBV et anciens groupes couleurs', () {
    expect(SlotAuthorization.permission(person('RVBV'), 'RVBV'), SlotPermission.authorized);
    expect(SlotAuthorization.permission(person('', groups: ['Rouge']), 'RVBV'), SlotPermission.authorized);
  });
  test('Ancien référentiel sans créneau', () {
    expect(SlotAuthorization.permission(person('', groups: ['Junior']), 'Junior'), SlotPermission.authorized);
    expect(SlotAuthorization.permission(person('', groups: ['Adultes']), 'Junior'), SlotPermission.denied);
  });
}
