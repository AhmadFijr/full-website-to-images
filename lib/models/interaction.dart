import 'interaction_type.dart';

class Interaction {
  final InteractionType type; // Type of interaction
  final String? selector; // CSS selector
  final String? value; // For input value
  final String? script; // For direct JS code
  final int? delayMs; // Wait time in milliseconds

  Interaction({
    // Constructor for the Interaction class
    required this.type,
    this.selector,
    this.value,
    this.script,
    this.delayMs,
  });
}