/// Correspondance explicite entre les identifiants historiques V6 et les
/// colonnes de groupe Excel. Aucun rapprochement par sous-chaîne : un groupe
/// "Adultes débutants" ne doit pas être confondu avec "Adultes".
class GroupEligibility {
  static String canonical(String input) {
    final value = input.trim().toLowerCase()
        .replaceAll(RegExp(r'[àáâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    const aliases = <String, String>{
      'benjamin': 'benjamins', 'benjamins': 'benjamins',
      'competitionbenjamin': 'benjamins', 'competitionbenjamins': 'benjamins',
      'junior': 'juniors', 'juniors': 'juniors',
      'competitionjunior': 'juniors', 'competitionjuniors': 'juniors',
      'avenir': 'avenirs', 'avenirs': 'avenirs',
      'competitionavenir': 'avenirs', 'competitionavenirs': 'avenirs',
      'aquaforme': 'aqua', 'aquafitness': 'aqua',
    };
    return aliases[value] ?? value;
  }

  static bool anyMatch(Iterable<String> memberGroups, Iterable<String> eligibleGroups) {
    final allowed = eligibleGroups.map(canonical).toSet();
    return memberGroups.any((g) => allowed.contains(canonical(g)));
  }
}
