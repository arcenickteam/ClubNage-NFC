import '../models.dart';
import 'group_eligibility.dart';

enum SlotPermission {
  authorized,
  sameFamilyException,
  denied,
}

class SlotAuthorization {
  // Plusieurs créneaux peuvent être indiqués dans une même cellule.
  static List<String> parse(String value) => value
      .split(RegExp(r'[,;\n]+'))
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  static String canonical(String input) {
    final value = GroupEligibility.canonical(input);
    const aliases = {'junior': 'juniors', 'benjamin': 'benjamins',
      'avenir': 'avenirs'};
    return aliases[value] ?? value;
  }

  // La colonne Créneau est prioritaire sur la catégorie.
  static bool explicitlyAllowed(Member member, String slot) =>
      parse(member.authorizedSlots).any(
        (value) => canonical(value) == canonical(slot),
      );

  static String family(String slot) {
    final key = canonical(slot);

    if (key.startsWith('aqua') && key != 'aquaphobie') {
      return 'aqua';
    }

    if (key.startsWith('jaune')) {
      return 'jaune';
    }

    if (key == 'junior' || key == 'juniors' ||
        key == 'benjamin' || key == 'benjamins' ||
        key == 'avenir' || key == 'avenirs') {
      return 'competition';
    }

    return key;
  }

  static SlotPermission permission(Member member, String slot) {
    if (explicitlyAllowed(member, slot)) {
      return SlotPermission.authorized;
    }

    final assigned = parse(member.authorizedSlots);

    if (assigned.any((value) => family(value) == family(slot))) {
      return SlotPermission.sameFamilyException;
    }

    return SlotPermission.denied;
  }
}
