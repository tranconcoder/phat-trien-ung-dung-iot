class Maintenance {
  final String id;
  final String carId;
  final String title;
  final String description;
  final DateTime date;
  final double cost;
  final String serviceCenter;
  final bool isCompleted;

  Maintenance({
    required this.id,
    required this.carId,
    required this.title,
    required this.description,
    required this.date,
    required this.cost,
    required this.serviceCenter,
    required this.isCompleted,
  });

  // Create a Maintenance from JSON data
  factory Maintenance.fromJson(Map<String, dynamic> json) {
    return Maintenance(
      id: json['id'] as String,
      carId: json['carId'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      date: DateTime.parse(json['date'] as String),
      cost: json['cost'].toDouble(),
      serviceCenter: json['serviceCenter'] as String,
      isCompleted: json['isCompleted'] as bool,
    );
  }

  // Convert Maintenance to JSON data
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'carId': carId,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'cost': cost,
      'serviceCenter': serviceCenter,
      'isCompleted': isCompleted,
    };
  }

  // Create a copy of Maintenance with some properties changed
  Maintenance copyWith({
    String? id,
    String? carId,
    String? title,
    String? description,
    DateTime? date,
    double? cost,
    String? serviceCenter,
    bool? isCompleted,
  }) {
    return Maintenance(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      cost: cost ?? this.cost,
      serviceCenter: serviceCenter ?? this.serviceCenter,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
