import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/db/app_database.dart';

/// Плитка актива в списке инвентаризации.
/// Высококонтрастная кодировка: зелёный — проверено,
/// серый — осталось найти, оранжевый — чужая техника (перемещение).
class AssetTile extends StatelessWidget {
  final Asset asset;
  final bool selectedForPrint;
  final ValueChanged<bool?>? onPrintSelected;
  final VoidCallback? onTap;

  const AssetTile({
    super.key,
    required this.asset,
    this.selectedForPrint = false,
    this.onPrintSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = InventoryColors.forAsset(
      isVerified: asset.isVerified,
      isForeign: asset.isForeign,
    );
    final subtitle = [
      asset.objectKey,
      if (asset.serialNumber.isNotEmpty) 'СН: ${asset.serialNumber}',
      if (asset.code1c.isNotEmpty) '1С: ${asset.code1c}',
      if (asset.molName.isNotEmpty) 'МОЛ: ${asset.molName}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        title: Text(
          asset.name,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (asset.isForeign)
              const Chip(
                label: Text('Перемещение'),
                backgroundColor: Color(0xFFFFE0B2),
                visualDensity: VisualDensity.compact,
              ),
            if (asset.isVerified && !asset.isForeign)
              const Icon(Icons.check_circle, color: AppTheme.verified),
            Checkbox(
              value: selectedForPrint,
              onChanged: onPrintSelected,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
