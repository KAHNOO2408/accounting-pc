import 'package:flutter/material.dart';

import '../../core/jalali.dart';
import '../../data/store.dart';
import '../auth/auth_screens.dart';

/// Quiet start screen shown behind the ribbon.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final th = Theme.of(context);
    final s = store.settings;
    final title = s.businessName.isNotEmpty ? s.businessName : 'تراز';
    return Center(
      child: Opacity(
        opacity: 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TarazLogo(size: 84),
            const SizedBox(height: 18),
            Text(title, style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(Jalali.now().formatWithWeekday(), style: th.textTheme.titleMedium?.copyWith(color: th.hintColor)),
            const SizedBox(height: 4),
            Text('دفتر مالی ${Jalali.now().year}', style: th.textTheme.bodyMedium?.copyWith(color: th.hintColor)),
          ],
        ),
      ),
    );
  }
}
