import 'package:flutter/material.dart';

/// Mapeo de claves de íconos a `IconData`
const Map<String, IconData> categoryIconsMap = {
  'restaurant': Icons.restaurant,
  'directions_bus': Icons.directions_bus,
  'movie': Icons.movie,
  'health_and_safety': Icons.health_and_safety,
  'school': Icons.school,
  'home': Icons.home,
  'checkroom': Icons.checkroom,
  'sports_esports': Icons.sports_esports,
  'flight_takeoff': Icons.flight_takeoff,
  'receipt_long': Icons.receipt_long,
  'pets': Icons.pets,
  'payments': Icons.payments,
  'trending_up': Icons.trending_up,
};

/// Retorna un ícono desde una clave string. Si no existe, usa uno genérico.
IconData iconFromString(String? iconKey) {
  if (iconKey == null) return Icons.payments;
  return categoryIconsMap[iconKey] ?? Icons.payments;
}

/// Heurístico de ícono según nombre + tipo (solo si `icon` no está definido)
IconData categoryIcon(String name, String type, {String? icon}) {
  if (icon != null) return iconFromString(icon);

  final n = name.toLowerCase();
  if (type == 'income') return Icons.trending_up;

  if (n.contains('aliment') || n.contains('comida')) return Icons.restaurant;
  if (n.contains('transp') || n.contains('taxi') || n.contains('bus')) return Icons.directions_bus;
  if (n.contains('multimedia') || n.contains('stream')) return Icons.movie;
  if (n.contains('salud') || n.contains('medic')) return Icons.health_and_safety;
  if (n.contains('educa') || n.contains('curso')) return Icons.school;
  if (n.contains('renta') || n.contains('alquiler') || n.contains('hogar')) return Icons.home;
  if (n.contains('ropa') || n.contains('vest')) return Icons.checkroom;
  if (n.contains('entreten') || n.contains('ocio')) return Icons.sports_esports;
  if (n.contains('viaje') || n.contains('hotel')) return Icons.flight_takeoff;
  if (n.contains('servicio') || n.contains('luz') || n.contains('agua') || n.contains('internet')) return Icons.receipt_long;
  if (n.contains('mascota')) return Icons.pets;

  return Icons.payments;
}
