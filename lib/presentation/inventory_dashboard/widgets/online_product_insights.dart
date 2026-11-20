import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/online_overview.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';
import 'online_overview_grid.dart';
import 'online_rank_guide_design.dart';
import 'stock_catalog_visuals.dart';

const _body = TextStyle(color: catalogInk, fontSize: 15, height: 1.4);

class OnlineRankGuide extends StatelessWidget {
  final Object? premiumRetail;
  final Map<String, dynamic> forecastMeta;
  final Map<OnlineRank, OnlineOverviewRow> examples;
  const OnlineRankGuide({
    super.key,
    required this.premiumRetail,
    required this.forecastMeta,
    required this.examples,
  });

  bool get actualSales => forecastMeta['basis'] == 'actual_sales';
  bool get forecast => !actualSales && forecastMeta['status'] == 'ready';

  int? _topPercent(int index) {
    final policy = forecastMeta['policy'];
    if (policy is List && index < policy.length && policy[index] is num) {
      return ((1 - (policy[index] as num)) * 100).round();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
    child: Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: SizedBox(
        width: 1120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 18 : 30,
                24,
                18,
                22,
              ),
              decoration: const BoxDecoration(color: Colors.white),
              child: Row(
                children: [
                  Container(
                    width: MediaQuery.sizeOf(context).width < 600 ? 48 : 64,
                    height: MediaQuery.sizeOf(context).width < 600 ? 48 : 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF0FAF9), Color(0xFFD9F0ED)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      color: Color(0xFF087D76),
                      size: MediaQuery.sizeOf(context).width < 600 ? 27 : 32,
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width >= 600) ...[
                    const SizedBox(width: 24),
                    Container(
                      width: 1,
                      height: 54,
                      color: const Color(0xFFC9D3E0),
                    ),
                    const SizedBox(width: 24),
                  ] else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What the letters mean',
                          style: TextStyle(
                            color: catalogInk,
                            fontSize: MediaQuery.sizeOf(context).width < 600
                                ? 24
                                : 31,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          actualSales
                              ? 'Last 6 full months · Online branches only'
                              : forecast
                              ? '6-month sales trial · Online branches only'
                              : 'Normal purchase products · Online branches only',
                          style: const TextStyle(
                            color: Color(0xFF65758C),
                            fontSize: 18,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    color: catalogInk,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF3F6FA),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Scrollbar(
                child: SingleChildScrollView(
                  primary: true,
                  padding: EdgeInsets.fromLTRB(
                    MediaQuery.sizeOf(context).width < 600 ? 18 : 30,
                    4,
                    MediaQuery.sizeOf(context).width < 600 ? 18 : 30,
                    30,
                  ),
                  child: LayoutBuilder(
                    builder: (context, size) => _cards(size.maxWidth),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _cards(double width) {
    if (actualSales) return _actualCards(width);
    const gap = 16.0;
    final compact = width < 600;
    final cardWidth = compact ? width : (width - gap) / 2;
    final aQtyPercent = _topPercent(0);
    final aValuePercent = _topPercent(1);
    final bQtyPercent = _topPercent(2);
    final bValuePercent = _topPercent(3);
    final newProductNote = forecastMeta['mrn_age_rule'] == null
        ? ''
        : ' For new products with only 2 available months, sales in both months can qualify.';
    final routes = [
      (
        forecast
            ? aQtyPercent == null
                  ? 'High Qty'
                  : 'Top $aQtyPercent% by expected Qty'
            : 'Top 25% by Qty',
        forecast
            ? 'We sort products with expected sales from highest to lowest Qty for the next 6 months. The product needs at least 3 expected Qty and must have sold in at least 3 different months in the last 12 months.$newProductNote'
            : 'At least 3 Qty this year. The product sold in 3 different months, or in 2 months this year with sales last year. Strong sales in a few branches count, too.',
      ),
      (
        forecast
            ? aValuePercent == null
                  ? 'High sales value'
                  : 'Top $aValuePercent% by expected value'
            : 'Top 10% by sales value',
        forecast
            ? 'We multiply expected Qty by today’s Retail price, then rank products with a price by that value. This gives higher-priced products a way to get A with fewer sales. They must have sold in at least 3 different months in the last 12 months.$newProductNote'
            : 'At least 3 Qty this year, with sales in 3 different months. We multiply Qty sold after returns by today’s Retail price.',
      ),
      if (premiumRetail != null)
        (
          'Retail AED ${catalogQty(premiumRetail)} or more',
          'We check the last 12 months in 4 groups of 3 months. It must sell in 3 or 4 groups, including the latest. For example, 1 Qty every 3 months can get A.',
        ),
    ];
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        if (forecastMeta['mrn_age_rule'] != null)
          Container(
            width: width,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6EBF2)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New products',
                  style: TextStyle(
                    color: catalogInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'A product is new for 6 months from its first approved MRN receipt. After 6 months, or with no MRN record, it is an existing product. Current age is checked on the page’s last update date.',
                  style: _body,
                ),
                SizedBox(height: 8),
                Text(
                  'Sales estimates use completed months. For a new product, we use sales since receipt, including months with no sales. We divide net Qty by available days, using at least 30 days, to estimate the next 6 months. A still needs sales in at least 2 months. B can use 1 month when only 1 month is available. Earlier online sales are always kept in the calculation.',
                  style: _body,
                ),
              ],
            ),
          ),
        _RankGuideCard(
          rank: OnlineRank.a,
          title: 'High priority',
          body: forecast
              ? 'We use past online sales to estimate how much each product may sell in the next 6 months. A product can get A in any of the ways below. Keep A products available in all open online branches.'
              : 'A product can qualify in any of these ways. It needs sales in the last 3 full months, after returns.',
          example: examples[OnlineRank.a],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (forecast && aQtyPercent != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F6FC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDDE8F5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why $aQtyPercent%?',
                        style: _body.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'For every 100 products in the Qty ranking, about $aQtyPercent are in the top group. We tried different cutoffs on past sales. This cutoff helped the branch plan cover more sales by Qty and by value within the trial stock limit.',
                        style: _body,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              LayoutBuilder(
                builder: (context, size) {
                  final routeCards = [
                    for (final (title, body) in routes)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDCE7E6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFF087D76),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              body,
                              style: _body.copyWith(fontSize: 16, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                  ];
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < routeCards.length; i++) ...[
                          if (i > 0) const SizedBox(height: gap),
                          routeCards[i],
                        ],
                      ],
                    );
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < routeCards.length; i++) ...[
                          if (i > 0) const SizedBox(width: gap),
                          Expanded(child: routeCards[i]),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        for (final (rank, title, body) in [
          (
            OnlineRank.b,
            'Medium sales',
            forecast
                ? 'We check A first. B needs sales in at least 2 different months in the last 12 months. '
                      '${forecastMeta['mrn_age_rule'] == null ? '' : 'A new product with only 1 available month needs sales in that month. '}'
                      '${bQtyPercent != null && bValuePercent != null ? 'It must rank in the top $bQtyPercent% by expected Qty or the top $bValuePercent% by expected sales value. ' : 'It also needs a mid-level sales forecast. '}'
                      'Keep stock in the main online branches and the product’s 2 best branches.'
                : 'The product sold more than 2 Qty this year and ranked above the bottom 25% by Qty. It sold in 5 or more branches or sold more Qty than half the products with online sales.',
          ),
          (
            OnlineRank.c,
            'Low sales',
            forecast
                ? 'We check A and B first. C covers the remaining products with a sales history. They may have a low forecast or sales in only a few months, even with a high Retail price. Keep stock in the 2 branches with the highest expected sales.'
                : 'There were few online sales. A product that sold 1 Qty last year and 1 Qty this year is a common example. A product that sold well last year can also be C if it barely sold this year.',
          ),
          (
            OnlineRank.n,
            'New, no online stock',
            'The first approved MRN receipt was less than 6 months ago. Stock is 0 Qty in every online branch, and stock is available in STORE. It gets N even if it sold before. Zero or missing STORE stock does not get N. INHOUSE products get S first. After 6 months, the normal stock and sales rules apply.',
          ),
          (
            OnlineRank.m,
            'No stock or sales',
            'Stock is 0 Qty in all online branches. No online sales in 2025 or 2026. New products that meet N are checked first.',
          ),
          (
            OnlineRank.t,
            'Stock with no recent sales',
            'Has stock in an online branch. No online sales in the last 6 full months, and no sales in the current month.',
          ),
          (
            OnlineRank.s,
            'In-house',
            'Sales Orientation is INHOUSE. These products always get S.',
          ),
          (
            OnlineRank.review,
            'Needs review',
            'No online sales. Stock reports are missing or show a negative Qty. Check the stock figures.',
          ),
        ])
          SizedBox(
            width: rank == OnlineRank.review ? width : cardWidth,
            child: _RankGuideCard(
              rank: rank,
              title: title,
              body: body,
              example: examples[rank],
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'Tap a product to see why it got its rank.',
            style: _body,
          ),
        ),
      ],
    );
  }

  Widget _actualCards(double width) {
    final half = width < 840 ? width : (width - 20) / 2;
    final qtyA = forecastMeta['A_qty_top_pct'];
    final valueA = forecastMeta['A_value_top_pct'];
    final qtyB = forecastMeta['B_qty_top_pct'];
    final valueB = forecastMeta['B_value_top_pct'];
    final branches = forecastMeta['minimum_A_branches'];
    return Wrap(
      spacing: 20,
      runSpacing: 26,
      children: [
        SizedBox(
          width: width,
          child: OnlineGuideFrame(
            rank: OnlineRank.a,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OnlineGuideSummary(
                  embedded: true,
                  rank: OnlineRank.a,
                  title: 'High priority',
                  body:
                      'A sells well in many branches, sells a high Qty, or has a high sales value. We use the last 6 full months of online sales, after returns. A product needs only one of the rules below. Keep stock in all open online branches.',
                ),
                Padding(
                  padding: EdgeInsets.all(width < 560 ? 18 : 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final heading = Text(
                            'Priority rules for A',
                            style: onlineGuideText.copyWith(
                              fontSize: box.maxWidth < 560 ? 24 : 26,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          );
                          return box.maxWidth < 560
                              ? heading
                              : Row(
                                  children: [
                                    heading,
                                    const SizedBox(width: 20),
                                    const Expanded(
                                      child: Divider(color: Color(0xFFC6D2E2)),
                                    ),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 6),
                      OnlineGuideRule(
                        icon: Icons.storefront_outlined,
                        title: 'Sales in many branches',
                        body:
                            'Sold in at least 70% of online branches. With the current branch list, this means $branches branches.',
                      ),
                      OnlineGuideRule(
                        icon: Icons.widgets_outlined,
                        title: 'High Qty sold',
                        body:
                            'It sells more Qty than most products. We use the first $qtyA out of 100 products when sorted from highest to lowest Qty, with at least 3 Qty. It can get A even if only a few branches sell it.',
                      ),
                      OnlineGuideRule(
                        icon: Icons.bar_chart_rounded,
                        title: 'High sales value',
                        body:
                            'Its sales have a high value. We multiply Qty sold by the current Retail price, then use the first $valueA out of 100 products by that value. A product can get A with fewer sales if its price is higher.',
                      ),
                      const OnlineGuideRule(
                        icon: Icons.sell_outlined,
                        title: 'Retail AED 1,000 or more',
                        body:
                            'A product at this price can get A even when it sells a small Qty. We split the last year into 4 groups of 3 months. It must sell in at least 3 groups, including the latest. For example, 1 Qty every 3 months can be enough. Price alone does not give A.',
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.event_repeat_rounded,
                            color: Color(0xFF087D7C),
                            size: 25,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'The first 3 rules also need sales in at least 3 different months within the last 6 full months. A new product with only 2 available months needs sales in both months.',
                              style: onlineGuideText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      OnlineGuideNote(
                        title: 'How do we compare products?',
                        body:
                            'We sort products with sales from highest to lowest. For A, we use about $qtyA out of 100 by Qty, or $valueA out of 100 by sales value. For B, we use about $qtyB out of 100 by Qty, or $valueB out of 100 by value, after checking A. These percentages compare products; they are not the share of branches or total sales. They are starting limits for this trial. A has other ways to get in, so more than $qtyA% of products can get A. Products with equal results stay together.',
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFDCE8EA),
                ),
                OnlineGuideExample(
                  product: examples[OnlineRank.a],
                  embedded: true,
                ),
              ],
            ),
          ),
        ),
        for (final (rank, title, body) in [
          (
            OnlineRank.b,
            'Medium sales',
            'B has enough sales for the middle group, but does not meet A. It usually sells regularly in a smaller Qty or at a lower sales value than A. It needs sales in at least 2 of the last 6 full months. A new product with only 1 available month can use that month. Keep stock in the main online branches and the product’s 2 best branches.',
          ),
          (
            OnlineRank.c,
            'Low sales',
            'C sells a small Qty, has a low sales value, or sells in too few months to get B. Each product shows its own reason. Keep stock in its 2 best online branches.',
          ),
          (
            OnlineRank.n,
            'New, no online stock',
            'N is a new product with no current stock in online branches. Its first approved MRN was less than 6 months ago. Every online branch has 0 Qty, and STORE has stock to send. It can get N even if it sold before. INHOUSE gets S first.',
          ),
          (
            OnlineRank.m,
            'No stock or sales',
            'M has no current online stock and no recorded online sales in 2025 or 2026. We check S and N first.',
          ),
          (
            OnlineRank.t,
            'Stock with no recent sales',
            'T has stock in an online branch, but it has not sold online in the last 6 full months or the current month. Check why the stock is not selling.',
          ),
          (
            OnlineRank.s,
            'In-house',
            'S is for products marked INHOUSE in Sales Orientation. They have their own group and get S before any other rank.',
          ),
          (
            OnlineRank.review,
            'Needs review',
            'No online sales were found. Stock reports are missing or show stock below 0 Qty. Check these figures before choosing a sales rank.',
          ),
        ])
          SizedBox(
            width: rank == OnlineRank.review ? width : half,
            child: OnlineGuideRankCard(
              rank: rank,
              title: title,
              body: body,
              product: examples[rank],
            ),
          ),
        SizedBox(
          width: width,
          child: const OnlineGuideNote(
            title: 'How we check new products',
            icon: Icons.local_shipping_outlined,
            body:
                'New products: the first approved MRN tells us when the product first arrived. It is new for 6 months. With no MRN record, it counts as existing. For a newer product, we compare its average Qty sold per day since receipt, using at least 30 days. Months before it arrived do not count against it. We keep any earlier recorded sales. Sales value uses the current Retail price.',
          ),
        ),
      ],
    );
  }
}

class _RankGuideCard extends StatelessWidget {
  final OnlineRank rank;
  final String title, body;
  final OnlineOverviewRow? example;
  final Widget? child;
  const _RankGuideCard({
    required this.rank,
    required this.title,
    required this.body,
    this.example,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = onlineRankColor(rank);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: rank == OnlineRank.review
                    ? Icon(Icons.manage_search_rounded, color: color, size: 20)
                    : Text(
                        rank.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: catalogInk,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(body, style: _body.copyWith(fontSize: 16, height: 1.5)),
          if (child != null) ...[const SizedBox(height: 16), child!],
          if (example case final product?) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE6EBF2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Current example · ${product.item.code}'
                    '${product.hasSalesForecast && product.priceKnown ? ' · Retail AED ${catalogQty(product.retail)}' : ''}',
                    style: _body.copyWith(
                      color: const Color(0xFF65758C),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.item.name,
                    style: _body.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(onlinePlainReason(product), style: _body),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text('No current example for this rank.', style: _body),
          ],
        ],
      ),
    );
  }
}

class OnlineProductInsights extends StatelessWidget {
  final OnlineOverviewRow row;
  const OnlineProductInsights({super.key, required this.row});

  @override
  Widget build(BuildContext context) => CatalogPanel(
    key: const ValueKey('online-rank-reason'),
    title: row.rank == OnlineRank.review
        ? 'Why check this product?'
        : 'Why is this ${row.rank.label}?',
    subtitle: 'Across all online branches',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          onlinePriorityLabel(row),
          style: TextStyle(
            color: onlineRankColor(row.rank),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(onlinePlainReason(row), style: _body),
        if (row.productAge.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CatalogPill(
                row.productAge['status'] == 'new'
                    ? 'New product'
                    : 'Existing product',
                color: row.productAge['status'] == 'new'
                    ? catalogTeal
                    : catalogMuted,
              ),
              if (row.productAge['first_mrn'] != null)
                CatalogPill(
                  'First MRN ${catalogDate(row.productAge['first_mrn'])}',
                  color: catalogBlue,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row.productAge['first_mrn'] == null
                ? 'No MRN receipt was found by ${catalogDate(row.productAge['as_of'])}, so we treat it as an existing product.'
                : row.productAge['status'] == 'new'
                ? 'First received less than 6 months ago. It stays new until ${catalogDate(row.productAge['new_until'])}.'
                : 'First received at least 6 months ago, so it is an existing product.',
            style: _body,
          ),
          if (row.productAge['first_online_sale_month'] != null)
            Text(
              'First online sales: ${DateFormat('MMM yyyy').format(DateTime.parse('${row.productAge['first_online_sale_month']}'))}.',
              style: _body,
            ),
        ],
        const SizedBox(height: 6),
        Text(
          'Item status: ${onlineItemLabel(row.item.itemStatus)}',
          style: _body,
        ),
        if (row.item.text('sales_orientation').isNotEmpty)
          Text(
            'Sales Orientation: ${row.item.text('sales_orientation')}',
            style: _body,
          ),
        if (row.usesActualSales && row.priorityBranches.isNotEmpty)
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Where to keep stock · ${row.priorityBranches.length} branches',
                style: _body.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(row.action, style: _body),
              children: [
                for (final branch in row.priorityBranches)
                  ListTile(
                    dense: true,
                    title: Text(
                      StoreBranchIdentityRegistry.displayName(branch),
                      style: _body,
                    ),
                  ),
              ],
            ),
          )
        else if (row.priorityBranches.isNotEmpty)
          Text(
            'Top branches: ${row.priorityBranches.map(StoreBranchIdentityRegistry.displayName).join(', ')}',
            style: _body,
          ),
      ],
    ),
  );
}

class OnlineProductForecast extends StatelessWidget {
  final OnlineOverviewRow row;
  final Map<String, dynamic> details;
  final List<Map<String, dynamic>> branchStock;
  const OnlineProductForecast({
    super.key,
    required this.row,
    required this.details,
    required this.branchStock,
  });

  @override
  Widget build(BuildContext context) {
    final forecast = row.salesForecast;
    final planned = row.forecastBranches
        .where(row.branchNames.contains)
        .toSet();
    final stockByBranch = {
      for (final entry in branchStock)
        if (planned.contains(entry['branch'])) entry['branch']: entry['stock'],
    };
    final plannedWithStock = planned
        .where((name) => stockNumber(stockByBranch[name]) > 0)
        .length;
    final missingReports = planned
        .where((name) => stockByBranch[name] == null)
        .length;
    final branches =
        (details['branches'] as List? ?? const [])
            .map(stockMap)
            .where((branch) => row.branchNames.contains(branch['branch']))
            .toList()
          ..sort(
            (a, b) => stockNumber(b['qty']).compareTo(stockNumber(a['qty'])),
          );
    return CatalogPanel(
      key: const ValueKey('online-six-month-forecast'),
      title: 'Next 6 months',
      subtitle:
          '${catalogDate(forecast['forecast_from'])} – ${catalogDate(forecast['forecast_to'])} · Online sales trial',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              CatalogPill('Expected sales ${catalogQty(forecast['qty'])} Qty'),
              if (forecast['estimated_value'] != null)
                CatalogPill(
                  'Estimated value AED ${catalogQty(forecast['estimated_value'])}',
                  color: catalogBlue,
                ),
              CatalogPill(
                'Keep available in ${row.forecastBranches.length} branches',
                color: catalogPurple,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Availability plan: ${row.forecastBranches.map(StoreBranchIdentityRegistry.displayName).join(', ')}.',
            style: _body,
          ),
          if (planned.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Current stock in $plannedWithStock of ${planned.length} planned '
              '${planned.length == 1 ? 'branch' : 'branches'}.'
              '${missingReports == 0 ? '' : ' Missing stock reports: $missingReports.'}',
              style: _body,
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Value uses today’s Retail price. Forecast Qty covers 6 months of sales.',
            style: _body,
          ),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Expected sales by online branch',
                style: _body,
              ),
              children: [
                for (final branch in branches)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      StoreBranchIdentityRegistry.displayName(
                        '${branch['branch']}',
                      ),
                      style: _body,
                    ),
                    subtitle: Text(
                      'Chance of sales ${(stockNumber(branch['sale_chance']) * 100).round()}%'
                      '${branch['required'] == true ? ' · Keep available' : ''}',
                      style: const TextStyle(color: catalogMuted, fontSize: 13),
                    ),
                    trailing: Text(
                      '${catalogQty(branch['qty'])} Qty',
                      style: _body,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnlineProductSales extends StatelessWidget {
  final List<Map<String, dynamic>> months;
  final String branch;
  final bool annual;
  const OnlineProductSales({
    super.key,
    required this.months,
    required this.branch,
    this.annual = false,
  });

  @override
  Widget build(BuildContext context) {
    final scope = branch.isEmpty
        ? 'All online branches'
        : StoreBranchIdentityRegistry.displayName(branch);
    final current = months
        .where((month) => month['source'] == 'sales_last_45_days')
        .lastOrNull;
    final period = current == null
        ? 'Full months'
        : current['through'] == null
        ? 'Current month · No data uploaded'
        : 'Current month through ${catalogDate(current['through'])} · Not complete';
    return CatalogPanel(
      key: ValueKey(
        annual ? 'annual-sales-panel' : 'online-monthly-sales-panel',
      ),
      title: annual ? 'Online sales by year' : 'Monthly online sales',
      subtitle: '$scope · $period',
      child: annual
          ? _OnlineYearSalesChart(months: months)
          : CatalogMonthlyChart(
              item: StockCatalogItem({'monthly_sales': months}),
              showStockDetails: false,
            ),
    );
  }
}

class _OnlineYearSalesChart extends StatelessWidget {
  final List<Map<String, dynamic>> months;
  const _OnlineYearSalesChart({required this.months});

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) {
      return const Text('No online sales data.', style: _body);
    }

    final totals = <String, ({double qty, int months})>{};
    for (final month in months) {
      final year = '${month['month']}'.split('/').last;
      final previous = totals[year] ?? (qty: 0.0, months: 0);
      totals[year] = (
        qty: previous.qty + stockNumber(month['total']),
        months: previous.months + 1,
      );
    }
    final highest = totals.values.map((total) => total.qty).fold(0.0, math.max);
    final lowest = totals.values.map((total) => total.qty).fold(0.0, math.min);
    final scale = 190 / math.max(1.0, highest - lowest);
    final years = totals.keys.toList()..sort();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: years.map((year) {
        final total = totals[year]!;
        final bar = Container(
          width: 84,
          height: total.qty.abs() * scale,
          decoration: BoxDecoration(
            color: year == years.last ? catalogTeal : catalogBlue,
            borderRadius: BorderRadius.circular(6),
          ),
        );
        return Expanded(
          child: Column(
            children: [
              Text(
                '${catalogQty(total.qty)} Qty',
                textAlign: TextAlign.center,
                style: _body.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: highest > 0 ? highest * scale : 16,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: total.qty > 0 ? bar : null,
                ),
              ),
              const Divider(height: 1, color: Color(0xFFDCE5F0)),
              SizedBox(
                height: -lowest * scale,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: total.qty < 0 ? bar : null,
                ),
              ),
              const SizedBox(height: 10),
              Text(year, style: _body),
              Text(
                '${total.months} ${total.months == 1 ? 'month' : 'months'}',
                style: const TextStyle(color: catalogMuted, fontSize: 13),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class OnlineProductSummary extends StatelessWidget {
  final OnlineOverviewRow row;
  final Object? sales45;
  const OnlineProductSummary({
    super.key,
    required this.row,
    required this.sales45,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final columns = size.maxWidth < 630
          ? 2
          : size.maxWidth < 950
          ? 3
          : 5;
      final width = (size.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (index, (label, qty, color, icon)) in [
            (
              'Online stock',
              row.displayedStock,
              catalogTeal,
              Icons.storefront_outlined,
            ),
            (
              'Store stock',
              row.storeStock,
              catalogBlue,
              Icons.warehouse_outlined,
            ),
            (
              'Other branch stock',
              row.otherBranchStock,
              catalogOrange,
              Icons.store_outlined,
            ),
            (
              'Online + Store',
              row.combinedStock,
              catalogPurple,
              Icons.inventory_2_outlined,
            ),
            (
              'Online sales (45D)',
              sales45 ?? 0,
              catalogOrange,
              Icons.shopping_bag_outlined,
            ),
          ].indexed)
            SizedBox(
              width: columns == 2 && index == 4 ? size.maxWidth : width,
              child: _OnlineStockMetric(
                title: label,
                value: qty == null ? '—' : catalogQty(qty),
                color: color,
                icon: icon,
              ),
            ),
        ],
      );
    },
  );
}

class _OnlineStockMetric extends StatelessWidget {
  final String title, value;
  final Color color;
  final IconData icon;
  const _OnlineStockMetric({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color.alphaBlend(color.withValues(alpha: .055), Colors.white),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: catalogInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class OnlineProductStock extends StatelessWidget {
  final OnlineOverviewRow row;
  final OnlineProductAudit? audit;
  final bool checking;
  final String? error;
  final VoidCallback onCheck;
  final Map<String, dynamic> recent;
  final List<Map<String, dynamic>> branches;
  const OnlineProductStock({
    super.key,
    required this.row,
    required this.recent,
    required this.branches,
    required this.onCheck,
    this.audit,
    this.checking = false,
    this.error,
  });

  Widget _branchStockTile(Map<String, dynamic> branch) {
    final name = '${branch['branch']}';
    final stock = branch['stock'];
    final sales = branch['recent_sales'];
    final cover = row.stockCoverFor(
      stock: stock == null ? null : stockNumber(stock),
      sales: sales == null ? null : stockNumber(sales),
    );
    final history = audit?.branches[onlineKey(name)];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(StoreBranchIdentityRegistry.displayName(name), style: _body),
      trailing: Text(
        stock == null ? 'Unknown' : catalogQty(stock),
        style: _body,
      ),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnlineStockCoverBar(days: cover, title: 'Stock cover'),
          if (history != null)
            Text(
              history.verified
                  ? '${history.stockedDays} days with stock'
                  : 'Stock history is incomplete',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stock = row.combinedStock;
    final sales = recent['qty'] ?? 0;
    String qty(double? value) => value == null ? 'Unknown' : catalogQty(value);
    return CatalogPanel(
      key: const ValueKey('stock-sales-panel'),
      title: 'Stock / Sales',
      subtitle: recent['from'] != null && recent['through'] != null
          ? 'Online sales · ${catalogDate(recent['from'])} – ${catalogDate(recent['through'])}'
          : 'Online stock + Store stock',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CatalogStockChart(
            item: StockManagementItem({
              'total_stock': stock,
              'stock_unavailable': stock == null,
              'recent_sales': sales,
            }),
            onlineSales: true,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CatalogPill(
                'Online stock: ${qty(row.displayedStock)}',
                color: catalogTeal,
              ),
              CatalogPill(
                'Store stock: ${qty(row.storeStock)}',
                color: catalogBlue,
              ),
              CatalogPill(
                'Online + Store: ${qty(stock)}',
                color: catalogPurple,
              ),
              CatalogPill(
                'Other branch stock: ${catalogQty(row.otherBranchStock)} Qty',
                color: catalogOrange,
              ),
            ],
          ),
          const SizedBox(height: 8),
          OnlineStockCoverBar(
            days: row.stockCoverDays,
            title: 'Online stock cover',
            note: onlineStockCoverNote(row),
          ),
          const SizedBox(height: 6),
          Text(onlineStockCoverNote(row), style: _body),
          const SizedBox(height: 8),
          Text(
            'Stock as of ${catalogDate(recent['stock_day'] ?? row.classification['stock_day'])}. ${onlineStockNote(row)}.',
            style: _body,
          ),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Stock by branch', style: _body),
              children: [
                for (final branch in branches) _branchStockTile(branch),
                if (error != null)
                  const Text(
                    'Could not check stock history. Try again.',
                    style: _body,
                  ),
                TextButton.icon(
                  onPressed: checking ? null : onCheck,
                  icon: const Icon(Icons.history),
                  label: Text(checking ? 'Checking…' : 'Check stock history'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
