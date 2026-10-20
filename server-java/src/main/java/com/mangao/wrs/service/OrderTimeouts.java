package com.mangao.wrs.service;

import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.Env;
import com.mangao.wrs.core.V;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * App orders that the owner has not accepted or declined:
 *  - after 15 minutes the owner gets a reminder ("You have not accepted ... yet");
 *  - after 30 minutes the order is cancelled, the customer gets a polite message and the owner is told.
 * Checked every minute. In test mode it runs only when a test asks (POST /__test/sweep).
 */
@Component
public class OrderTimeouts {
  public static final int REMIND_MINUTES = 15;
  public static final int CANCEL_MINUTES = 30;
  public static final String REMINDER = "Order Reminder";

  private final Db db;
  private final Orders orders;

  public OrderTimeouts(Db db, Orders orders) {
    this.db = db;
    this.orders = orders;
  }

  @EventListener(ApplicationReadyEvent.class)
  public void start() {
    if (Env.testMode()) return;
    ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor(r -> {
      Thread t = new Thread(r, "order-timeouts");
      t.setDaemon(true);
      return t;
    });
    timer.scheduleAtFixedRate(() -> {
      try {
        sweep(Clock.now());
      } catch (Exception e) {
        System.err.println("[order timeouts] " + e.getMessage());
      }
    }, 1, 1, TimeUnit.MINUTES);
  }

  private static String what(Map<String, Object> o) {
    long q = V.lng(o.get("quantity"));
    return q + " " + (q == 1 ? "gallon" : "gallons") + " · " + o.get("order_type");
  }

  private static String name(Map<String, Object> o) {
    return V.truthy(o.get("customer_name")) ? V.str(o.get("customer_name")) : "Guest";
  }

  /** Sends due reminders and cancels orders waiting 30 minutes. Returns { reminded, cancelled }. */
  public synchronized Map<String, Object> sweep(Instant now) {
    int reminded = 0, cancelled = 0;
    Instant cancelBefore = now.minusSeconds(CANCEL_MINUTES * 60L);
    Instant remindBefore = now.minusSeconds(REMIND_MINUTES * 60L);

    List<Map<String, Object>> late = db.query(
        "SELECT * FROM orders WHERE status = 'New' AND order_source = 'App' AND created_at <= ? ORDER BY created_at", cancelBefore);
    for (Map<String, Object> o : late) {
      long oid = V.lng(o.get("order_id"));
      boolean done = db.tx(() -> {
        int n = db.update("UPDATE orders SET status = 'Cancelled' WHERE order_id = ? AND status = 'New'", oid);
        if (n != 1) return false;
        orders.addHistory(oid, "Cancelled", null, "Not accepted within " + CANCEL_MINUTES + " minutes", now);
        orders.notifyCustomer(o, "Cancelled", "Order cancelled",
            "We're sorry, the station is very busy right now and could not accept your order in time, so it was cancelled. "
                + "You were not charged. Please try ordering again in a little while. Thank you for your patience!");
        orders.notifyOwner("Cancelled", "Order cancelled automatically",
            name(o) + "'s order (" + what(o) + ", ordered " + Clock.dateClock(V.instant(o.get("created_at")))
                + ") was not accepted within " + CANCEL_MINUTES + " minutes, so it was cancelled. The customer was told.",
            oid);
        return true;
      });
      if (done) cancelled++;
    }

    List<Map<String, Object>> waiting = db.query(
        "SELECT o.* FROM orders o WHERE o.status = 'New' AND o.order_source = 'App' AND o.created_at <= ? AND o.created_at > ?"
            + " AND NOT EXISTS (SELECT 1 FROM notifications n WHERE n.order_id = o.order_id AND n.notification_type = ?)",
        remindBefore, cancelBefore, REMINDER);
    for (Map<String, Object> o : waiting) {
      Instant created = V.instant(o.get("created_at"));
      Instant cancelAt = created.plusSeconds(CANCEL_MINUTES * 60L);
      orders.notifyOwner(REMINDER, "Order still waiting",
          "Owner, you have not accepted " + name(o) + "'s order yet (" + what(o) + ", ordered " + Clock.dateClock(created)
              + "). Accept or decline it by " + Clock.clock(cancelAt) + ", or it will be cancelled.",
          V.lng(o.get("order_id")));
      reminded++;
    }
    return Map.of("reminded", reminded, "cancelled", cancelled);
  }
}
