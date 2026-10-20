-- Mangao WRS - Order, Inventory, Sales & Delivery Management System
-- Database schema (MySQL 8 / MariaDB 10.4+), new ordering process of Oct 13, 2026.
--
-- Order sources:
--   App      - customer orders in the app (delivery price, cash on delivery)
--   Logged   - delivery order logged by the owner or staff (call, text, Messenger, walk-in for delivery)
--   Walk-in  - walk-in pick-up, saved as a record with its payment (no status steps)
-- Delivery order statuses:
--   New -> Processing -> Out for Delivery -> Delivered
--   side results: Not Delivered (owner re-delivers or cancels), Declined, Cancelled
-- Walk-in pick-up records have the status Recorded.
--
-- The setup script replaces the database name `mangao_wrs` with DB_NAME from server/.env.

CREATE DATABASE IF NOT EXISTS mangao_wrs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mangao_wrs;

-- ------------------------------------------------------------------ people
CREATE TABLE users (
  user_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone_number VARCHAR(15) NOT NULL,
  email VARCHAR(100) NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('Owner','Staff','Rider','Customer') NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  privacy_consent_at DATETIME NULL COMMENT 'When the customer agreed to the Terms and Data Privacy Notice',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_users_phone (phone_number),
  UNIQUE KEY uq_users_email (email),
  KEY idx_users_role (role)
) ENGINE=InnoDB COMMENT='Owner (one), staff, riders and customers';

CREATE TABLE password_resets (
  reset_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT UNSIGNED NOT NULL,
  code_hash VARCHAR(255) NOT NULL COMMENT '6-digit code, hashed',
  attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
  expires_at DATETIME NOT NULL COMMENT '10 minutes after sending',
  used_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_resets_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='Forgot password codes sent by email';

CREATE TABLE customer_addresses (
  address_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id INT UNSIGNED NOT NULL,
  address_name VARCHAR(50) NOT NULL COMMENT 'e.g. Home, Work',
  house_unit_no VARCHAR(20) NULL,
  block_lot VARCHAR(30) NULL,
  street VARCHAR(100) NULL,
  barangay VARCHAR(60) NULL,
  city VARCHAR(40) NOT NULL DEFAULT 'Quezon City',
  landmark VARCHAR(150) NULL,
  latitude DECIMAL(10,7) NULL COMMENT 'Pin on the map (empty when only typed)',
  longitude DECIMAL(10,7) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_addresses_customer FOREIGN KEY (customer_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='Saved delivery addresses (pinned or typed)';

-- ------------------------------------------------------------------ prices and settings
CREATE TABLE prices (
  price_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  item_type ENUM('Refill Walk-in','Refill Delivery','Package') NOT NULL,
  amount DECIMAL(8,2) NOT NULL,
  effective_from DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  set_by INT UNSIGNED NULL,
  CONSTRAINT fk_prices_user FOREIGN KEY (set_by) REFERENCES users (user_id) ON DELETE SET NULL,
  KEY idx_prices_item (item_type, effective_from)
) ENGINE=InnoDB COMMENT='Price history; the newest row of each item is the current price (new orders only)';

CREATE TABLE station_settings (
  setting_id TINYINT UNSIGNED PRIMARY KEY DEFAULT 1,
  tank_limit SMALLINT UNSIGNED NOT NULL DEFAULT 60 COMMENT 'Gallons before the raw water tank alert',
  seals_per_gallon TINYINT UNSIGNED NOT NULL DEFAULT 3,
  station_latitude DECIMAL(10,7) NULL,
  station_longitude DECIMAL(10,7) NULL,
  station_phone VARCHAR(15) NULL,
  station_address VARCHAR(255) NULL COMMENT 'Shown on reports and the live map',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB COMMENT='One row of station settings';

-- ------------------------------------------------------------------ inventory and tank
CREATE TABLE inventory_items (
  item_id TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  item_name ENUM('New Gallon','Seal') NOT NULL,
  quantity_on_hand INT NOT NULL DEFAULT 0,
  low_stock_level INT UNSIGNED NOT NULL DEFAULT 0,
  UNIQUE KEY uq_item_name (item_name)
) ENGINE=InnoDB COMMENT='New gallons and seals in stock';

CREATE TABLE tank_cycles (
  cycle_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  gallons_count INT UNSIGNED NOT NULL DEFAULT 0,
  tank_limit SMALLINT UNSIGNED NOT NULL,
  started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  alerted_at DATETIME NULL COMMENT 'When the count reached the limit',
  ended_at DATETIME NULL COMMENT 'When the owner refilled the tank and reset the counter',
  reset_by INT UNSIGNED NULL,
  CONSTRAINT fk_tank_user FOREIGN KEY (reset_by) REFERENCES users (user_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='Raw water tank counter; the open cycle has ended_at empty';

-- ------------------------------------------------------------------ orders
CREATE TABLE delivery_batches (
  batch_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  rider_id INT UNSIGNED NOT NULL COMMENT 'One rider per batch (one sidecar)',
  sent_by INT UNSIGNED NULL COMMENT 'Owner or staff who marked Out for Delivery',
  sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at DATETIME NULL COMMENT 'Last order of the batch recorded; location sharing stops',
  CONSTRAINT fk_batches_rider FOREIGN KEY (rider_id) REFERENCES users (user_id),
  CONSTRAINT fk_batches_sender FOREIGN KEY (sent_by) REFERENCES users (user_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='Orders sent out together with one rider';

CREATE TABLE orders (
  order_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_source ENUM('App','Logged','Walk-in') NOT NULL,
  logged_channel ENUM('Call','Text','Messenger','Walk-in for delivery') NULL COMMENT 'Logged delivery orders only',
  order_type ENUM('Refill','Package') NOT NULL,
  customer_id INT UNSIGNED NULL COMMENT 'Customer account (app orders)',
  guest_token VARCHAR(64) NULL COMMENT 'Guest phone code (guest app orders)',
  created_by INT UNSIGNED NULL COMMENT 'Owner or staff who logged the order',
  customer_name VARCHAR(100) NULL,
  contact_phone VARCHAR(15) NULL,
  address_id INT UNSIGNED NULL,
  delivery_address_text VARCHAR(255) NULL COMMENT 'Copy of the address at the time of the order',
  delivery_landmark VARCHAR(150) NULL,
  delivery_latitude DECIMAL(10,7) NULL,
  delivery_longitude DECIMAL(10,7) NULL,
  quantity SMALLINT UNSIGNED NOT NULL,
  unit_price DECIMAL(8,2) NOT NULL COMMENT 'Copied from the price list when ordered',
  total_amount DECIMAL(10,2) NOT NULL,
  notes VARCHAR(255) NULL,
  delivery_date DATE NULL COMMENT 'Day the customer chose for the delivery; NULL = as soon as possible',
  status ENUM('New','Processing','Out for Delivery','Delivered','Not Delivered','Declined','Cancelled','Recorded') NOT NULL,
  payment_method ENUM('COD','Pay on delivery','Paid at station','Walk-in') NOT NULL,
  payment_status ENUM('Pending','Paid','Unpaid') NOT NULL DEFAULT 'Pending',
  paid_at DATETIME NULL,
  rider_id INT UNSIGNED NULL,
  batch_id INT UNSIGNED NULL,
  accepted_by INT UNSIGNED NULL,
  accepted_at DATETIME NULL COMMENT 'Accepted (app) or logged (logged orders)',
  est_delivery_from DATETIME NULL,
  est_delivery_to DATETIME NULL,
  out_at DATETIME NULL,
  delivered_at DATETIME NULL,
  tank_counted_at DATETIME NULL COMMENT 'Gallons added to the tank counter (first time only)',
  tank_cycle_id INT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES users (user_id) ON DELETE SET NULL,
  CONSTRAINT fk_orders_creator FOREIGN KEY (created_by) REFERENCES users (user_id) ON DELETE SET NULL,
  CONSTRAINT fk_orders_address FOREIGN KEY (address_id) REFERENCES customer_addresses (address_id) ON DELETE SET NULL,
  CONSTRAINT fk_orders_rider FOREIGN KEY (rider_id) REFERENCES users (user_id) ON DELETE SET NULL,
  CONSTRAINT fk_orders_batch FOREIGN KEY (batch_id) REFERENCES delivery_batches (batch_id) ON DELETE SET NULL,
  CONSTRAINT fk_orders_acceptor FOREIGN KEY (accepted_by) REFERENCES users (user_id) ON DELETE SET NULL,
  CONSTRAINT fk_orders_cycle FOREIGN KEY (tank_cycle_id) REFERENCES tank_cycles (cycle_id) ON DELETE SET NULL,
  KEY idx_orders_status (status),
  KEY idx_orders_created (created_at),
  KEY idx_orders_guest (guest_token),
  CONSTRAINT chk_orders_qty CHECK (quantity > 0)
) ENGINE=InnoDB COMMENT='App orders, logged delivery orders and walk-in records; every order is a sale';

CREATE TABLE order_status_history (
  history_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id INT UNSIGNED NOT NULL,
  status VARCHAR(40) NOT NULL COMMENT 'Status or event, e.g. Processing, Rider changed, Marked paid',
  changed_by INT UNSIGNED NULL COMMENT 'Empty for a guest',
  note VARCHAR(255) NULL COMMENT 'Reason, rider name, payment ...',
  changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_history_order FOREIGN KEY (order_id) REFERENCES orders (order_id) ON DELETE CASCADE,
  CONSTRAINT fk_history_user FOREIGN KEY (changed_by) REFERENCES users (user_id) ON DELETE SET NULL,
  KEY idx_history_order (order_id, changed_at)
) ENGINE=InnoDB COMMENT='Order timeline: every step with date, time and who did it';

CREATE TABLE stock_movements (
  movement_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  item_id TINYINT UNSIGNED NOT NULL,
  order_id INT UNSIGNED NULL,
  recorded_by INT UNSIGNED NULL,
  movement_type ENUM('Added','Used','Damaged','Lost','Lent','Returned','Adjusted') NOT NULL,
  quantity_change INT NOT NULL COMMENT 'Positive adds, negative removes',
  note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_moves_item FOREIGN KEY (item_id) REFERENCES inventory_items (item_id),
  CONSTRAINT fk_moves_order FOREIGN KEY (order_id) REFERENCES orders (order_id) ON DELETE SET NULL,
  CONSTRAINT fk_moves_user FOREIGN KEY (recorded_by) REFERENCES users (user_id) ON DELETE SET NULL,
  KEY idx_moves_time (created_at)
) ENGINE=InnoDB COMMENT='Movement history of every stock change';

CREATE TABLE gallon_loans (
  loan_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_id INT UNSIGNED NULL,
  customer_name VARCHAR(100) NOT NULL,
  contact_phone VARCHAR(15) NULL,
  order_id INT UNSIGNED NULL,
  quantity SMALLINT UNSIGNED NOT NULL,
  lent_by INT UNSIGNED NULL,
  lent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  returned_at DATETIME NULL,
  returned_by INT UNSIGNED NULL,
  note VARCHAR(255) NULL,
  CONSTRAINT fk_loans_customer FOREIGN KEY (customer_id) REFERENCES users (user_id) ON DELETE SET NULL,
  CONSTRAINT fk_loans_order FOREIGN KEY (order_id) REFERENCES orders (order_id) ON DELETE SET NULL,
  CONSTRAINT fk_loans_lent_by FOREIGN KEY (lent_by) REFERENCES users (user_id) ON DELETE SET NULL,
  CONSTRAINT fk_loans_returned_by FOREIGN KEY (returned_by) REFERENCES users (user_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='Gallons lent to customers and returned';

CREATE TABLE damage_reports (
  report_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id INT UNSIGNED NULL,
  customer_name VARCHAR(100) NULL,
  reported_by INT UNSIGNED NULL,
  photo_path VARCHAR(255) NULL,
  note VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_damage_order FOREIGN KEY (order_id) REFERENCES orders (order_id) ON DELETE SET NULL,
  CONSTRAINT fk_damage_user FOREIGN KEY (reported_by) REFERENCES users (user_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='Damaged customer gallons (photo and note); a new gallon is taken from stock';

CREATE TABLE stored_files (
  file_path VARCHAR(120) NOT NULL PRIMARY KEY COMMENT 'e.g. damage/3f9a....jpg (same as damage_reports.photo_path)',
  content_type VARCHAR(40) NOT NULL,
  data MEDIUMBLOB NOT NULL,
  created_at DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Uploaded photos stored in the database (online server)';

-- ------------------------------------------------------------------ delivery tracking and notifications
CREATE TABLE rider_locations (
  rider_id INT UNSIGNED PRIMARY KEY,
  batch_id INT UNSIGNED NULL,
  latitude DECIMAL(10,7) NOT NULL,
  longitude DECIMAL(10,7) NOT NULL,
  is_sharing TINYINT(1) NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_location_rider FOREIGN KEY (rider_id) REFERENCES users (user_id) ON DELETE CASCADE,
  CONSTRAINT fk_location_batch FOREIGN KEY (batch_id) REFERENCES delivery_batches (batch_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='Last known location of each rider while orders are out';

CREATE TABLE notifications (
  notification_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT UNSIGNED NULL COMMENT 'Owner, staff or customer account',
  guest_token VARCHAR(64) NULL COMMENT 'Guest phone',
  order_id INT UNSIGNED NULL,
  notification_type VARCHAR(40) NOT NULL COMMENT 'New Order, Logged Order, Cancelled, Not Delivered, Damaged Gallon, Tank, Low Stock, Order Accepted ...',
  title VARCHAR(100) NOT NULL,
  message VARCHAR(255) NOT NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE,
  CONSTRAINT fk_notif_order FOREIGN KEY (order_id) REFERENCES orders (order_id) ON DELETE CASCADE,
  KEY idx_notif_user (user_id, is_read, created_at),
  KEY idx_notif_guest (guest_token)
) ENGINE=InnoDB COMMENT='In-app alerts and customer status notifications';

CREATE TABLE notification_preferences (
  user_id INT UNSIGNED NOT NULL,
  notification_type VARCHAR(40) NOT NULL,
  is_enabled TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, notification_type),
  CONSTRAINT fk_prefs_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='Which alerts the owner wants to receive';

CREATE TABLE device_tokens (
  token_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id INT UNSIGNED NULL,
  guest_token VARCHAR(64) NULL,
  push_token VARCHAR(255) NOT NULL,
  platform VARCHAR(20) NOT NULL DEFAULT 'android',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_push_token (push_token),
  CONSTRAINT fk_tokens_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='Firebase Cloud Messaging tokens for push notifications';

-- ------------------------------------------------------------------ starting data
-- Owner placeholder (name, phone, email and password are set from server/.env by the setup script)
INSERT INTO users (user_id, full_name, phone_number, email, password_hash, role)
VALUES (1, 'Owner', '09170000001', 'owner@example.com', '-', 'Owner');

INSERT INTO prices (item_type, amount) VALUES ('Refill Walk-in', 30.00), ('Refill Delivery', 35.00), ('Package', 150.00);
-- Station: 98 Riverside Street, Barangay Commonwealth, Quezon City (the owner moves the pin to the exact spot in Prices & Settings > Station location).
INSERT INTO station_settings (setting_id, tank_limit, seals_per_gallon, station_latitude, station_longitude, station_address)
VALUES (1, 60, 3, 14.6928230, 121.0871699, '98 Riverside Street, Barangay Commonwealth, Quezon City');
INSERT INTO inventory_items (item_name, quantity_on_hand, low_stock_level) VALUES ('New Gallon', 0, 30), ('Seal', 0, 60);
INSERT INTO tank_cycles (gallons_count, tank_limit) VALUES (0, 60);
