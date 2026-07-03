# Mobile Order Picking

Separate Flutter mobile app for store order preparation. It does not modify the existing web app code.

## What it does

- Login with Supabase auth.
- Select today's branch from `product_movement_history`.
- Write the employee name who prepares the order.
- Choose `Medicine` or `General`.
- Shows items in the same sorting logic used by `PrintService`.
- Tap an item, scan barcode, enter the exact quantity, and the row turns green.
- Final submit writes one session and item-level scan rows to Supabase.

## First setup

Run this SQL once:

`mobile_order_picking/supabase/mobile_order_picking_results.sql`

## Run

```powershell
cd C:\Users\abdulrahim\StudioProjects\inventory_system\mobile_order_picking
flutter pub get
flutter run
```

You can override Supabase settings without editing files:

```powershell
flutter run --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_ANON_KEY=your_anon_key
```

## Data source

The branch order is read from:

- `product_movement_history`
- `movement_type = daily_order`
- `movement_date = today`

Extra display and scan details are completed from `daily_order` using `branch`, `run_date`, and `item_code`.
