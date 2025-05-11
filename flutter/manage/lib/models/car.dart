class Car {
  final String id;
  final String make;
  final String model;
  final String licensePlate;
  final int year;
  final String color;
  final double mileage;
  final DateTime purchaseDate;
  final double fuelLevel;
  final DateTime lastMaintenanceDate;
  final DateTime nextMaintenanceDate;

  Car({
    required this.id,
    required this.make,
    required this.model,
    required this.licensePlate,
    required this.year,
    required this.color,
    required this.mileage,
    required this.purchaseDate,
    required this.fuelLevel,
    required this.lastMaintenanceDate,
    required this.nextMaintenanceDate,
  });

  // Create a Car from JSON data
  factory Car.fromJson(Map<String, dynamic> json) {
    return Car(
      id: json['id'] as String,
      make: json['make'] as String,
      model: json['model'] as String,
      licensePlate: json['licensePlate'] as String,
      year: json['year'] as int,
      color: json['color'] as String,
      mileage: json['mileage'].toDouble(),
      purchaseDate: DateTime.parse(json['purchaseDate'] as String),
      fuelLevel: json['fuelLevel'].toDouble(),
      lastMaintenanceDate: DateTime.parse(
        json['lastMaintenanceDate'] as String,
      ),
      nextMaintenanceDate: DateTime.parse(
        json['nextMaintenanceDate'] as String,
      ),
    );
  }

  // Convert Car to JSON data
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'make': make,
      'model': model,
      'licensePlate': licensePlate,
      'year': year,
      'color': color,
      'mileage': mileage,
      'purchaseDate': purchaseDate.toIso8601String(),
      'fuelLevel': fuelLevel,
      'lastMaintenanceDate': lastMaintenanceDate.toIso8601String(),
      'nextMaintenanceDate': nextMaintenanceDate.toIso8601String(),
    };
  }

  // Create a copy of Car with some properties changed
  Car copyWith({
    String? id,
    String? make,
    String? model,
    String? licensePlate,
    int? year,
    String? color,
    double? mileage,
    DateTime? purchaseDate,
    double? fuelLevel,
    DateTime? lastMaintenanceDate,
    DateTime? nextMaintenanceDate,
  }) {
    return Car(
      id: id ?? this.id,
      make: make ?? this.make,
      model: model ?? this.model,
      licensePlate: licensePlate ?? this.licensePlate,
      year: year ?? this.year,
      color: color ?? this.color,
      mileage: mileage ?? this.mileage,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      fuelLevel: fuelLevel ?? this.fuelLevel,
      lastMaintenanceDate: lastMaintenanceDate ?? this.lastMaintenanceDate,
      nextMaintenanceDate: nextMaintenanceDate ?? this.nextMaintenanceDate,
    );
  }
}
