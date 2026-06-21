import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

abstract class ProductMovementEvent extends Equatable {
  const ProductMovementEvent();

  @override
  List<Object?> get props => [];
}

class LoadProductMovementBranches extends ProductMovementEvent {}

class ProductMovementQueryChanged extends ProductMovementEvent {
  final String query;

  const ProductMovementQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class ProductMovementSuggestionSelected extends ProductMovementEvent {
  final String itemCode;
  final String itemName;

  const ProductMovementSuggestionSelected({
    required this.itemCode,
    required this.itemName,
  });

  @override
  List<Object?> get props => [itemCode, itemName];
}

class ProductMovementBranchChanged extends ProductMovementEvent {
  final String? branch;

  const ProductMovementBranchChanged(this.branch);

  @override
  List<Object?> get props => [branch];
}

class ProductMovementDateRangeChanged extends ProductMovementEvent {
  final DateTimeRange range;

  const ProductMovementDateRangeChanged(this.range);

  @override
  List<Object?> get props => [range];
}

class ProductMovementTypeChanged extends ProductMovementEvent {
  final String movementType;

  const ProductMovementTypeChanged(this.movementType);

  @override
  List<Object?> get props => [movementType];
}

class LoadProductMovementRows extends ProductMovementEvent {}
