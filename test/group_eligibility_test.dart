import 'package:flutter_test/flutter_test.dart';
import 'package:clubnage_nfc/services/group_eligibility.dart';

void main() {
  test('Benjamin Excel accepté dans compétition Benjamins V6', () {
    expect(GroupEligibility.anyMatch(['Benjamin'], ['benjamins']), isTrue);
    expect(GroupEligibility.anyMatch(['Compétition Benjamin'], ['benjamins']), isTrue);
  });
  test('Les groupes distincts ne sont pas confondus', () {
    expect(GroupEligibility.anyMatch(['Junior'], ['benjamins']), isFalse);
    expect(GroupEligibility.anyMatch(['Adultes débutants'], ['adultes']), isFalse);
  });
  test('Accents et casse', () {
    expect(GroupEligibility.anyMatch(['Compétition Avenirs'], ['avenirs']), isTrue);
  });
}
