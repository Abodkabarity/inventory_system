import 'package:flutter/material.dart';

const _bg = Color(0xFFF5F7FB);
const _ink = Color(0xFF13233A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFDCE5F0);

class _Part {
  final String title, body, image, caption;
  final List<String> steps;
  final double ratio;
  const _Part(
    this.title,
    this.body,
    this.steps,
    this.image,
    this.ratio,
    this.caption,
  );
}

class _Topic {
  final String number, title, subtitle;
  final IconData icon;
  final Color color;
  final List<_Part> parts;
  const _Topic(
    this.number,
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.parts,
  );
}

const _topics = <_Topic>[
  _Topic(
    '01',
    'Branch workspace navigation',
    'Orders, Allocation, Stock Check, Insurance AI and Guide',
    Icons.dashboard_customize_rounded,
    Color(0xFF0EA5E9),
    [
      _Part(
        'Move between branch tools',
        'The floating drawer is the single navigation point for branch operations and keeps the order table at full width.',
        [
          'Orders opens the daily order workspace.',
          'Allocation shows items waiting to be sent or received.',
          'Stock Check opens assigned physical counts.',
          'Insurance AI opens coverage and clinical knowledge.',
          'Order Guide returns to this help centre.',
        ],
        'assets/images/order_guide/branch_drawer.png',
        1.76,
        'Branch identity is hidden in this guide image.',
      ),
    ],
  ),
  _Topic(
    '02',
    'Daily order workspace',
    'Search, filters, summary cards and table columns',
    Icons.shopping_cart_checkout_rounded,
    Color(0xFF2563EB),
    [
      _Part(
        'Start with the workspace summary',
        'Use the three summary cards, search and quick filters to isolate the items that need attention without changing the saved order.',
        [
          'Visible Products is the count after filters.',
          'Items in Order counts lines with a final quantity.',
          'Additional Orders Today shows usage against the daily limit.',
          'Search by item code, name or barcode.',
          'Use Clear Filters to return to the full table.',
        ],
        'assets/images/order_guide/daily_order_overview.png',
        2.14,
        'Actual order workspace with sensitive data blurred.',
      ),
      _Part(
        'Read every ordering column',
        'Review the recommendation together with stock, demand and formulary status. Add Columns reveals extra operational fields.',
        [
          'Branch Stock is the current branch quantity.',
          'Store Stock is available central stock.',
          'Demand for 30 Days is the ordering baseline.',
          'Final Reorder Qty is the quantity that will be submitted.',
          'The formulary badge identifies the active ordering rule.',
        ],
        'assets/images/order_guide/daily_order_overview.png',
        2.14,
        'Sort and filter controls remain available in the main table.',
      ),
    ],
  ),
  _Topic(
    '03',
    'Order calculation',
    'Demand, reorder thresholds and pack rounding',
    Icons.calculate_rounded,
    Color(0xFF16A34A),
    [
      _Part(
        'How the recommendation is calculated',
        'The system establishes 30-day demand, calculates minimum and maximum stock, then proposes enough stock to reach the maximum when the branch is at or below its minimum.',
        [
          'Demand uses the applicable maximum from sales, assortment, Max Adjustment and TMA, subject to formulary rules.',
          'Demand ≤25: minimum = demand ×21/30; maximum = demand.',
          'Demand 26–150: minimum = demand ×15/30; maximum = demand ×21/30.',
          'Demand >150: minimum = demand ×10/30; maximum = demand ×14/30.',
          'Suggestion = maximum − branch stock, rounded up to the minimum order-unit multiple.',
          'NON formulary items are not proposed through the normal rule unless an allowed exception applies.',
        ],
        'assets/images/order_guide/daily_order_overview.png',
        2.14,
        'Demand and Final Reorder Qty are displayed together.',
      ),
    ],
  ),
  _Topic(
    '04',
    'Final reorder, review and submit',
    'Normal editing, limited stock, disabled editing and submission',
    Icons.fact_check_rounded,
    Color(0xFF7C3AED),
    [
      _Part(
        'Edit an available Final Reorder quantity',
        'Click the pencil beside Final Reorder Qty to open the editor. This is the normal state when the item is eligible and central store stock is available.',
        [
          'Old QTY is the current saved final reorder; Your Edit shows the new value.',
          'Use minus and plus, or enter the quantity directly, without exceeding Max allowed.',
          'A reason is required before Save becomes available.',
          'Apply to Max Adjustment is available only when decreasing the final reorder quantity.',
          'Review Store Stock, Min Reorder, Max Reorder, Reorder QTY, Mismatch, Formulary and Purchase Type.',
          'Press Save to keep the change, or Close to leave without saving.',
        ],
        'assets/images/order_guide/final_reorder_edit.png',
        1.00,
        'Normal Final Reorder editor with quantity controls and quick information.',
      ),
      _Part(
        'Final Reorder when stock is limited',
        'The Limited Stock warning appears when central stock restricts the quantity that can be ordered. The editor remains available, but the maximum is capped.',
        [
          'Read the Limited Stock warning before changing the quantity.',
          'The Max allowed value is the highest quantity accepted for this item.',
          'The plus control becomes unavailable when Your Edit reaches the maximum.',
          'You may reduce the quantity, but a reason is still required to save.',
          'Use Quick info to compare Store Stock with Min Reorder, Max Reorder and Reorder QTY.',
        ],
        'assets/images/order_guide/final_reorder_limited_stock.png',
        0.67,
        'Limited Stock state: Final Reorder cannot be increased above Max allowed.',
      ),
      _Part(
        'When Final Reorder editing is disabled',
        'Editing is disabled when Store Stock is zero or the item is NON-Formulary. The warning explains the active restriction and quantity controls cannot be used.',
        [
          'Read the Editing Disabled message to understand the restriction.',
          'Old QTY and Your Edit remain visible for reference.',
          'Minus, plus and quantity input are disabled.',
          'Save remains unavailable because no valid edit can be made.',
          'Check Store Stock and Formulary in Quick info, then close the panel.',
          'Use an approved alternative workflow only if the operational policy allows it.',
        ],
        'assets/images/order_guide/final_reorder_disabled.png',
        0.83,
        'Editing Disabled state for zero store stock or a NON-Formulary item.',
      ),
      _Part(
        'Submit stage 1: Review Pending Items To Order',
        'When pending suggestions exist, Submit first opens Pending Items To Order. Every card must be reviewed before the process can continue.',
        [
          'Check the item code, name, requester, quantity, reason and request time.',
          'Choose Add To Order when the suggestion should be included in Final Reorder.',
          'Choose Ignore when the item must not be included in this submission.',
          'The Reviewed counter shows completed decisions against total pending suggestions.',
          'Next remains disabled until all pending suggestions are reviewed.',
          'Cancel closes the stage and stops submission without changing the submitted status.',
        ],
        'assets/images/order_guide/submit_pending_items.png',
        1.11,
        'Pending Items To Order must be added or ignored before continuing.',
      ),
      _Part(
        'Submit stage 2: Review low-demand stock gaps',
        'The next stage lists eligible items where Branch Stock is lower than 30-day demand. This is a final optional check for small quantities that may be operationally useful.',
        [
          'Compare Demand 30D with Branch stock for each suggested item.',
          'Leave an item untouched when no extra quantity is required.',
          'Use minus and plus to select the quantity, without exceeding Maximum.',
          'Press Add to order only for items that should be included.',
          'The footer counts how many eligible items have been added.',
          'Press Next: Review Changes after completing the review.',
        ],
        'assets/images/order_guide/submit_low_demand_review.png',
        1.32,
        'Optional Branch Stock Less Than Demand review before the final confirmation.',
      ),
      _Part(
        'Submit stage 3: Review Changes and confirm',
        'Review Changes is the final confirmation stage. It summarizes saved edits before the order is submitted and locked.',
        [
          'Review every changed item, old quantity, new quantity and reason when edits exist.',
          'No changes means no Final Reorder edits were made; the order can still be submitted.',
          'Cancel returns to the order without submitting.',
          'Confirm Submit sends the final daily order.',
          'Use Confirm Submit only after quantities, pending requests and suggestions are correct.',
          'After confirmation, the order becomes read-only and the header shows Submitted.',
        ],
        'assets/images/order_guide/submit_review_changes.png',
        1.64,
        'Final Review Changes stage; an order with no edits may still be submitted.',
      ),
      _Part(
        'After submission',
        'A successfully submitted order is locked. Use the status tools for follow-up instead of attempting to change the completed order.',
        [
          'Submitted confirms that the daily order is complete and locked.',
          'Order History opens earlier submitted orders.',
          'Non Received records quantities that were not delivered.',
          'The schedule banner shows the next preparation and submission time.',
        ],
        'assets/images/order_guide/daily_order_overview.png',
        2.14,
        'Submitted status and the next order schedule appear in the workspace header.',
      ),
    ],
  ),
  _Topic(
    '05',
    'Additional orders',
    'Create, send and track urgent requests',
    Icons.add_box_outlined,
    Color(0xFF0E9F9A),
    [
      _Part(
        'Add an extra quantity from an item row',
        'Open Additional Request from the item action, enter only the extra requirement, choose a reason and save the draft.',
        [
          'Enter the additional quantity required beyond the daily order.',
          'Select the reason that best explains the request.',
          'Confirm urgent only after logistics has been contacted.',
          'Save Draft to keep it, or Remove Draft to discard it.',
          'Send Additional activates when valid drafts exist.',
        ],
        'assets/images/order_guide/additional_request.png',
        1.17,
        'Additional Request side panel.',
      ),
      _Part(
        'Use Items To Order for a new request',
        'This is the structured route for a needed item that starts outside the calculated daily-order lines.',
        [
          'Search by item code or name.',
          'Enter quantity, reason and Requested By.',
          'Press Add Request to register it.',
          'Pending requests must be processed or ignored before submission.',
          'The system warns before combining it with an existing daily-order quantity.',
        ],
        'assets/images/order_guide/items_to_order.png',
        1.73,
        'Items To Order dialog.',
      ),
      _Part(
        'Track every request',
        'Additional Order Track shows requested and fulfilled quantity, reason, status and timestamps.',
        [
          'Pending is awaiting action; Sent has reached fulfilment.',
          'Done displays the fulfilled quantity and completion time.',
          'Rejected was not approved; Qty changed was fulfilled differently.',
          'Use search, date and status filters to locate a request.',
        ],
        'assets/images/order_guide/additional_tracking.png',
        1.69,
        'Additional Requests Tracking timeline.',
      ),
    ],
  ),
  _Topic(
    '06',
    'Stock mismatch',
    'Record system-versus-actual stock differences',
    Icons.rule_rounded,
    Color(0xFFEF5B3D),
    [
      _Part(
        'Document a physical stock difference',
        'Mismatch records explain why the physical count does not match the system quantity and preserve a review trail.',
        [
          'Open Add Mismatch from the toolbar.',
          'Select the item by code or name.',
          'Enter System Qty and counted Actual Qty.',
          'Press Add Mismatch and verify the difference.',
          'Edit a wrong record or delete only an invalid one.',
        ],
        'assets/images/order_guide/mismatch.png',
        1.30,
        'Mismatch panel showing system, actual and difference.',
      ),
    ],
  ),
  _Topic(
    '07',
    'Max adjustment',
    'Apply a justified demand override',
    Icons.tune_rounded,
    Color(0xFFF59E0B),
    [
      _Part(
        'Adjust the demand ceiling',
        'Use Max Adjustment only when a documented local condition makes the normal demand baseline unsuitable.',
        [
          'Open Add Max from the toolbar.',
          'Select the item and review Current Demand.',
          'Enter Max Adjustment and a specific reason.',
          'Keep Added By Branch enabled for branch-originated changes.',
          'Save, then recheck Demand for 30 Days and Final Reorder Qty.',
        ],
        'assets/images/order_guide/max_adjustment.png',
        1.74,
        'Max Adjustment panel with demand, value and reason.',
      ),
    ],
  ),
  _Topic(
    '08',
    'Stock check',
    'Complete assigned physical counts correctly',
    Icons.inventory_2_rounded,
    Color(0xFF10A65A),
    [
      _Part(
        'Complete the task before its deadline',
        'Stock Check compares ledger quantity with a physical count. Submitted lines lock and record who completed them.',
        [
          'Open a pending task from the branch drawer.',
          'Import STK Ledger to fill System Qty.',
          'Count stock and enter Actual Qty for every item.',
          'Use search and category filters for large tasks.',
          'Confirm Pending reaches zero, then Submit Stock Check before the deadline.',
        ],
        'assets/images/order_guide/stock_check.png',
        2.16,
        'Actual Stock Check screen with identities hidden.',
      ),
    ],
  ),
];

class BranchOrderGuidePage extends StatelessWidget {
  final VoidCallback onBack;
  const BranchOrderGuidePage({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) => _fixedScale(
    context,
    Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: onBack),
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) {
                  final columns = size.maxWidth >= 1180
                      ? 4
                      : size.maxWidth >= 720
                      ? 2
                      : 1;
                  return CustomScrollView(
                    slivers: [
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 18),
                        sliver: SliverToBoxAdapter(child: _Hero()),
                      ),
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Choose a guide',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Focused walkthroughs using real application screens.',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _TopicCard(topic: _topics[i]),
                            childCount: _topics.length,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                mainAxisExtent: 192,
                              ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});
  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(
      children: [
        IconButton.filledTonal(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFEDE9FE),
            foregroundColor: const Color(0xFF5B21B6),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.menu_book_rounded, color: Color(0xFF2563EB)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Branch Order Guide',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Complete operating guide for the branch workspace',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 15,
                color: Color(0xFF15803D),
              ),
              SizedBox(width: 5),
              Text(
                'Sensitive data hidden',
                style: TextStyle(
                  color: Color(0xFF15803D),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero();
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 178),
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF102E5C), Color(0xFF1768D5), Color(0xFF0EA5E9)],
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x242563EB),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, size) => Row(
        children: [
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BRANCH OPERATIONS · 2026',
                  style: TextStyle(
                    color: Color(0xFFD8EDFF),
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 13),
                Text(
                  'Everything your branch needs\nto operate daily orders',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '8 complete topics · Real application screens · Step-by-step instructions',
                  style: TextStyle(
                    color: Color(0xFFD8EDFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (size.maxWidth > 650) ...[
            const SizedBox(width: 20),
            const _Metric('08', 'Topics'),
            const SizedBox(width: 10),
            const _Metric('08', 'Screens'),
          ],
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  final String value, label;
  const _Metric(this.value, this.label);
  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 78,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: Colors.white.withValues(alpha: .18)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFD8EDFF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _TopicCard extends StatelessWidget {
  final _Topic topic;
  const _TopicCard({required this.topic});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => _TopicPage(topic: topic))),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: topic.color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(topic.icon, color: topic.color, size: 22),
                ),
                const Spacer(),
                Text(
                  topic.number,
                  style: TextStyle(
                    color: topic.color.withValues(alpha: .55),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                topic.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  '${topic.parts.length} ${topic.parts.length == 1 ? 'chapter' : 'chapters'}',
                  style: TextStyle(
                    color: topic.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_rounded, color: topic.color, size: 19),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _TopicPage extends StatelessWidget {
  final _Topic topic;
  const _TopicPage({required this.topic});
  @override
  Widget build(BuildContext context) => _fixedScale(
    context,
    Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 74,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: topic.color.withValues(alpha: .1),
                      foregroundColor: topic.color,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: topic.color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(topic.icon, color: topic.color, size: 21),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.title,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Branch Order Guide  /  Topic ${topic.number}',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${topic.parts.length} ${topic.parts.length == 1 ? 'chapter' : 'chapters'}',
                    style: TextStyle(
                      color: topic.color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 42),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1320),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: topic.color.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  child: Icon(
                                    topic.icon,
                                    color: topic.color,
                                    size: 29,
                                  ),
                                ),
                                const SizedBox(width: 17),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        topic.title,
                                        style: const TextStyle(
                                          color: _ink,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        topic.subtitle,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          for (var i = 0; i < topic.parts.length; i++) ...[
                            _Chapter(
                              part: topic.parts[i],
                              index: i + 1,
                              color: topic.color,
                            ),
                            if (i < topic.parts.length - 1)
                              const SizedBox(height: 18),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Chapter extends StatelessWidget {
  final _Part part;
  final int index;
  final Color color;
  const _Chapter({
    required this.part,
    required this.index,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D0F172A),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(22),
          child: LayoutBuilder(
            builder: (context, size) {
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CHAPTER ${index.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    part.title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 20,
                      height: 1.18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    part.body,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.55,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
              final steps = _Steps(steps: part.steps, color: color);
              return size.maxWidth < 760
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [details, const SizedBox(height: 18), steps],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: details),
                        const SizedBox(width: 26),
                        Expanded(flex: 4, child: steps),
                      ],
                    );
            },
          ),
        ),
        const Divider(height: 1, color: _border),
        _GuideImage(part: part, color: color),
      ],
    ),
  );
}

class _Steps extends StatelessWidget {
  final List<String> steps;
  final Color color;
  const _Steps({required this.steps, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'STEP BY STEP',
          style: TextStyle(
            color: _ink,
            fontSize: 10,
            letterSpacing: .8,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 11),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 21,
                  height: 21,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 10,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _GuideImage extends StatelessWidget {
  final _Part part;
  final Color color;
  const _GuideImage({required this.part, required this.color});
  void _open(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .9),
    builder: (dialog) => Dialog.fullscreen(
      backgroundColor: const Color(0xFF08111F),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: .7,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(80),
                child: Center(
                  child: Image.asset(part.image, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(dialog),
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: const Color(0xFFF1F5F9),
        child: InkWell(
          onTap: () => _open(context),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: part.ratio,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Image.asset(part.image, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.zoom_in_rounded, size: 17, color: color),
                      const SizedBox(width: 5),
                      Text(
                        'Open full screen',
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFF8FAFC),
        child: Text(
          part.caption,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

Widget _fixedScale(BuildContext context, Widget child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
  child: child,
);
