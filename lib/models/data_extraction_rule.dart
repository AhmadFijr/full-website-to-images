
class DataExtractionRule {
  final String name;
  final String selector;
  final String? attributeName; // Can be null if extracting text
  final String dataType; // e.g., "string", "int", "double"

  DataExtractionRule({
    required this.name,
    required this.selector,
    this.attributeName,
    required this.dataType,
  });
}
