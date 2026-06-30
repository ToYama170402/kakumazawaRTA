class RouteBounds {
  const RouteBounds({
    required this.minLatitude,
    required this.minLongitude,
    required this.maxLatitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double minLongitude;
  final double maxLatitude;
  final double maxLongitude;

  factory RouteBounds.fromJson(Map<String, dynamic> json) {
    return RouteBounds(
      minLatitude: (json['min_latitude'] as num).toDouble(),
      minLongitude: (json['min_longitude'] as num).toDouble(),
      maxLatitude: (json['max_latitude'] as num).toDouble(),
      maxLongitude: (json['max_longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'min_latitude': minLatitude,
      'min_longitude': minLongitude,
      'max_latitude': maxLatitude,
      'max_longitude': maxLongitude,
    };
  }
}

class RouteDefinition {
  const RouteDefinition({
    required this.id,
    required this.category,
    required this.routeName,
    required this.goalBounds,
    required this.startBounds,
    required this.maxVelocityThreshold,
    required this.avgVelocityThreshold,
  });

  final String id;
  final String category;
  final String routeName;
  final RouteBounds goalBounds;
  final RouteBounds startBounds;
  final double maxVelocityThreshold;
  final double avgVelocityThreshold;

  factory RouteDefinition.fromJson(Map<String, dynamic> json) {
    return RouteDefinition(
      id: json['id'] as String,
      category: json['category'] as String,
      routeName: json['route_name'] as String,
      goalBounds: RouteBounds.fromJson(
        json['goal_bounds'] as Map<String, dynamic>,
      ),
      startBounds: RouteBounds.fromJson(
        json['start_bounds'] as Map<String, dynamic>,
      ),
      maxVelocityThreshold: (json['max_velocity_threshold'] as num).toDouble(),
      avgVelocityThreshold: (json['avg_velocity_threshold'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'category': category,
      'route_name': routeName,
      'goal_bounds': goalBounds.toJson(),
      'start_bounds': startBounds.toJson(),
      'max_velocity_threshold': maxVelocityThreshold,
      'avg_velocity_threshold': avgVelocityThreshold,
    };
  }
}
