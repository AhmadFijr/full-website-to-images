enum InteractionType {
  click,
  input,
  scroll,
  // Add other types as needed
}

class Interaction {
  final InteractionType type;
  final String? selector;
  final String? value;

  Interaction({
    required this.type,
    this.selector,
    this.value
  });
}