import 'package:flutter/widgets.dart';

enum LayoutBreakpoint { compact, medium, expanded }

const double _compactMax = 599;
const double _mediumMax = 1199;

extension LayoutBreakpointX on LayoutBreakpoint {
  bool get isCompact => this == LayoutBreakpoint.compact;
  bool get isMedium => this == LayoutBreakpoint.medium;
  bool get isExpanded => this == LayoutBreakpoint.expanded;

  T when<T>({
    required T Function() compact,
    required T Function() medium,
    required T Function() expanded,
  }) {
    return switch (this) {
      LayoutBreakpoint.compact => compact(),
      LayoutBreakpoint.medium => medium(),
      LayoutBreakpoint.expanded => expanded(),
    };
  }
}

LayoutBreakpoint breakpointOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width <= _compactMax) return LayoutBreakpoint.compact;
  if (width <= _mediumMax) return LayoutBreakpoint.medium;
  return LayoutBreakpoint.expanded;
}

int gridCrossAxisCount(BuildContext context) {
  return breakpointOf(context).when(
    compact: () => 2,
    medium: () => 4,
    expanded: () => 6,
  );
}

double gridMaxExtent(BuildContext context) {
  return breakpointOf(context).when(
    compact: () => 200,
    medium: () => 220,
    expanded: () => 240,
  );
}
