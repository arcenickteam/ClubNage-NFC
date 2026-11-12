import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clubnage_nfc/services/local_roster_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sexe et naissance conservés après import et redémarrage', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalRosterStore();
    await store.save([{
      'id': 'MN26-0001', 'nom': 'Test', 'prenom': 'Camille',
      'sexe': 'F', 'dateNaissance': '14/03/2010', 'groupes': 'Junior',
    }]);
    final people = await store.load();
    expect(people, isNotNull);
    expect(people!.single.sex, 'F');
    expect(people.single.dateOfBirth, '14/03/2010');
  });

  test('ancienne base sans sexe reste compatible', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalRosterStore();
    await store.save([{
      'id': 'MN26-0002', 'nom': 'Test', 'prenom': 'Alex',
      'dateNaissance': '2009-05-12', 'groupes': 'Junior',
    }]);
    final people = await store.load();
    expect(people!.single.sex, '');
  });
}
