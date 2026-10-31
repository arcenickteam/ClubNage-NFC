import '../models.dart';
import 'group_eligibility.dart';

enum SlotPermission { authorized, sameFamilyException, denied }

/// Les droits explicites du fichier V8 sont prioritaires sur les catégories.
/// Les anciens référentiels (sans colonne Créneau) conservent le comportement V7.16.
class SlotAuthorization {
  static List<String> parse(String input) => input
      .split(RegExp(r'[,;\n]+'))
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  static String canonical(String value) {
    final key = GroupEligibility.canonical(value);
    const aliases = {
      'rouge': 'rvbv', 'violet': 'rvbv', 'bleu': 'rvbv', 'vert': 'rvbv',
      'rougevioletbleuvert': 'rvbv',
    };
    return aliases[key] ?? key;
  }

  static String family(String value) {
    final key = canonical(value);
    if (key.startsWith('aqua') && key != 'aquaphobie') return 'aqua';
    if (key.startsWith('jaune')) return 'jaune';
    if (key == 'juniors' || key == 'benjamins' || key == 'avenirs') {
      return 'competition';
    }
    return key;
  }

  static SlotPermission permission(Member member, String slot) {
    final assigned = parse(member.authorizedSlots);
    if (assigned.isEmpty) {
      // Compatibilité avec les installations qui n'ont pas encore réimporté V8.
      return member.groups.any((g) => canonical(g) == canonical(slot))
          ? SlotPermission.authorized : SlotPermission.denied;
    }
    if (assigned.any((g) => canonical(g) == canonical(slot))) {
      return SlotPermission.authorized;
    }
    if (assigned.any((g) => family(g) == family(slot))) {
      return SlotPermission.sameFamilyException;
    }
    return SlotPermission.denied;
  }
}
