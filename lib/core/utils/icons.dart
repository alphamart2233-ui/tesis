import 'package:flutter/material.dart';

IconData categoryIcon(String name, String type) {
  final n = name.toLowerCase();
  if (type == 'income') return Icons.trending_up;

  // Gastos (heurístico por nombre)
  if (n.contains('aliment') || n.contains('comida')) return Icons.restaurant;
  if (n.contains('transp') || n.contains('taxi') || n.contains('bus'))
    return Icons.directions_bus;
  if (n.contains('multimedia') || n.contains('stream')) return Icons.movie;
  if (n.contains('salud') || n.contains('medic'))
    return Icons.health_and_safety;
  if (n.contains('educa') || n.contains('curso')) return Icons.school;
  if (n.contains('renta') || n.contains('alquiler') || n.contains('hogar'))
    return Icons.home;
  if (n.contains('ropa') || n.contains('vest')) return Icons.checkroom;
  if (n.contains('entreten') || n.contains('ocio')) return Icons.sports_esports;
  if (n.contains('viaje') || n.contains('hotel')) return Icons.flight_takeoff;
  if (n.contains('servicio') ||
      n.contains('luz') ||
      n.contains('agua') ||
      n.contains('internet'))
    return Icons.receipt_long;
  if (n.contains('mascota')) return Icons.pets;
  return Icons.payments; // genérico
}
