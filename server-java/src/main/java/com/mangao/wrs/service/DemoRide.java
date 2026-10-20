package com.mangao.wrs.service;

import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.Env;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.stereotype.Component;

/**
 * Where the rider starts, and the demo ride.
 *
 * Start: when orders go Out for Delivery, the rider's map position is set to the station, so the
 * sidecar always starts there; the rider's phone GPS then moves it.
 *
 * Demo ride (owner: More > Prices & Settings, for testing and presentations when the rider's phone
 * is not really moving): the server drives the sidecar from the station along the streets to each
 * stop, waits at a stop until the rider marks it Delivered or Not delivered, then goes on. The trip
 * to a stop takes at most about 2 minutes (shorter trips go at 25 km/h). The rider's phone GPS is
 * not used while a demo ride runs. It is off when the server starts (DEMO_RIDE=true turns it on).
 */
@Component
public class DemoRide {
  private static final double MIN_SPEED = 25000 / 3600.0; // meters per second
  private static final double MAX_LEG_SECONDS = 120;
  private static final long TICK_MS = 2000;

  private final Db db;
  private final Realtime realtime;
  private final Routes routes;
  private final Orders orders;
  private final AtomicBoolean on = new AtomicBoolean("true".equalsIgnoreCase(Env.get("DEMO_RIDE", "false").trim()));
  private final Map<Long, Ride> rides = new ConcurrentHashMap<>();
  private ScheduledExecutorService timer;

  public DemoRide(Db db, Realtime realtime, Routes routes, Orders orders) {
    this.db = db;
    this.realtime = realtime;
    this.routes = routes;
    this.orders = orders;
  }

  public boolean isOn() {
    return on.get();
  }

  /** A demo ride is moving this rider (the phone's GPS is then not used). */
  public boolean riding(long riderId) {
    return on.get() && rides.containsKey(riderId);
  }

  /** Owner switches the demo ride on or off. On: riders already out start from the station. */
  public synchronized void set(boolean value) {
    on.set(value);
    if (!value) {
      rides.clear();
      return;
    }
    for (Map<String, Object> r : db.query("SELECT DISTINCT rider_id FROM orders WHERE status = 'Out for Delivery' AND rider_id IS NOT NULL")) {
      start(V.lng(r.get("rider_id")));
    }
  }

  /** Orders went Out for Delivery: the rider starts at the station (and the demo ride starts if on). */
  public void startAtStation(long riderId) {
    Orders.Station st = orders.stationPoint();
    if (st.lat() == null || st.lng() == null) return;
    move(riderId, st.lat(), st.lng());
    if (on.get()) start(riderId);
  }

  private synchronized void start(long riderId) {
    Orders.Station st = orders.stationPoint();
    if (st.lat() == null || st.lng() == null) return;
    List<Map<String, Object>> out = db.query(
        "SELECT order_id, delivery_latitude AS latitude, delivery_longitude AS longitude FROM orders WHERE rider_id = ? AND status = 'Out for Delivery' AND delivery_latitude IS NOT NULL", riderId);
    if (out.isEmpty()) return;
    // Visit the stops nearest-first, starting at the station.
    List<double[]> path = new ArrayList<>();
    List<Long> stopIds = new ArrayList<>();
    path.add(new double[] {st.lat(), st.lng()});
    List<Map<String, Object>> left = new ArrayList<>(out);
    double[] at = path.get(0);
    while (!left.isEmpty()) {
      Map<String, Object> best = null;
      double bestM = Double.MAX_VALUE;
      for (Map<String, Object> o : left) {
        double m = Routes.meters(at[0], at[1], V.num(o.get("latitude")), V.num(o.get("longitude")));
        if (m < bestM) {
          bestM = m;
          best = o;
        }
      }
      left.remove(best);
      at = new double[] {V.num(best.get("latitude")), V.num(best.get("longitude"))};
      path.add(at);
      stopIds.add(V.lng(best.get("order_id")));
    }
    Routes.Route route = routes.route(path);
    rides.put(riderId, new Ride(route.points(), path.subList(1, path.size()), stopIds));
    move(riderId, st.lat(), st.lng());
    ensureTimer();
  }

  private synchronized void ensureTimer() {
    if (timer != null) return;
    timer = Executors.newSingleThreadScheduledExecutor(r -> {
      Thread t = new Thread(r, "demo-ride");
      t.setDaemon(true);
      return t;
    });
    timer.scheduleAtFixedRate(this::tick, TICK_MS, TICK_MS, TimeUnit.MILLISECONDS);
  }

  private void tick() {
    for (Map.Entry<Long, Ride> e : rides.entrySet()) {
      try {
        if (!on.get() || !e.getValue().step(e.getKey())) rides.remove(e.getKey());
      } catch (Exception ex) {
        System.err.println("[demo ride] " + ex.getMessage());
        rides.remove(e.getKey());
      }
    }
  }

  /** Saves the rider's place and tells the phones (live map, customer tracking). */
  private void move(long riderId, double lat, double lng) {
    Map<String, Object> out = db.one("SELECT batch_id FROM orders WHERE rider_id = ? AND status = 'Out for Delivery' ORDER BY out_at DESC LIMIT 1", riderId);
    if (out == null) return;
    Instant t = Clock.now();
    db.update("INSERT INTO rider_locations (rider_id, batch_id, latitude, longitude, is_sharing, updated_at) VALUES (?, ?, ?, ?, 1, ?)"
            + " ON DUPLICATE KEY UPDATE batch_id = VALUES(batch_id), latitude = VALUES(latitude), longitude = VALUES(longitude), is_sharing = 1, updated_at = VALUES(updated_at)",
        riderId, out.get("batch_id"), String.format(Locale.ROOT, "%.7f", lat), String.format(Locale.ROOT, "%.7f", lng), t);
    realtime.location(riderId, M.of("lat", lat, "lng", lng, "at", t, "sharing", true));
  }

  /** One rider's demo trip: the street line, the stops on it, and how far along it the sidecar is. */
  private final class Ride {
    final List<double[]> line;
    final double[] along; // meters from the start to each point of the line
    final double[] stopAt; // meters from the start to each stop
    final List<Long> stopIds;
    final double speed;
    double done = 0;

    Ride(List<double[]> line, List<double[]> stops, List<Long> stopIds) {
      this.line = line;
      this.stopIds = stopIds;
      along = new double[line.size()];
      for (int i = 1; i < line.size(); i++) {
        along[i] = along[i - 1] + Routes.meters(line.get(i - 1)[0], line.get(i - 1)[1], line.get(i)[0], line.get(i)[1]);
      }
      stopAt = new double[stops.size()];
      int from = 0;
      for (int s = 0; s < stops.size(); s++) {
        int best = from;
        double bestM = Double.MAX_VALUE;
        for (int i = from; i < line.size(); i++) {
          double m = Routes.meters(line.get(i)[0], line.get(i)[1], stops.get(s)[0], stops.get(s)[1]);
          if (m < bestM) {
            bestM = m;
            best = i;
          }
        }
        stopAt[s] = along[best];
        from = best;
      }
      double firstLeg = stopAt.length > 0 ? stopAt[0] : along[along.length - 1];
      speed = Math.max(MIN_SPEED, firstLeg / MAX_LEG_SECONDS);
    }

    /** One move (every 2 seconds). False when the trip is over. */
    boolean step(long riderId) {
      List<Long> open = new ArrayList<>();
      for (Map<String, Object> r : db.query("SELECT order_id FROM orders WHERE rider_id = ? AND status = 'Out for Delivery'", riderId)) {
        open.add(V.lng(r.get("order_id")));
      }
      if (open.isEmpty()) return false;
      // Stop at the first stop that is still out.
      double limit = along[along.length - 1];
      for (int s = 0; s < stopIds.size(); s++) {
        if (open.contains(stopIds.get(s))) {
          limit = stopAt[s];
          break;
        }
      }
      if (done >= limit) return true; // waiting at the customer
      done = Math.min(limit, done + speed * TICK_MS / 1000.0);
      double[] p = pointAt(done);
      move(riderId, p[0], p[1]);
      return true;
    }

    double[] pointAt(double m) {
      for (int i = 1; i < line.size(); i++) {
        if (along[i] >= m) {
          double seg = along[i] - along[i - 1];
          double f = seg <= 0 ? 0 : (m - along[i - 1]) / seg;
          double[] a = line.get(i - 1), b = line.get(i);
          return new double[] {a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f};
        }
      }
      return line.get(line.size() - 1);
    }
  }
}
