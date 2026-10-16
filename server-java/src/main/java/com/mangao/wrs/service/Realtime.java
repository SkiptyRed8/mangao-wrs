package com.mangao.wrs.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.Jwt;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.io.IOException;
import java.net.URI;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import org.springframework.web.util.UriComponentsBuilder;

/**
 * Real-time updates (Spring WebSocket, step 35) and the live rider location (step 34).
 * The app connects to ws://server:3100/ws?token=... (or ?guest=<guest phone code>) and joins rooms:
 *   user:<id>, role:<Owner|Staff|Rider|Customer>, guest:<code>.
 * Each message is JSON { "event": name, "data": {...} }. Events:
 *   order         { id, status }                     an order changed: lists and details reload
 *   notification  { title, message, type, orderId }  shown as a banner
 *   location      { riderId, lat, lng, at, sharing } rider moved (live map)
 *   refresh       { what }                           stock, tank or loans changed
 */
@Component
public class Realtime extends TextWebSocketHandler {
  private final Db db;
  private final ObjectMapper json;
  private final Map<String, Set<WebSocketSession>> rooms = new ConcurrentHashMap<>();
  private final Map<String, List<String>> sessionRooms = new ConcurrentHashMap<>();
  private final Map<Long, ScheduledFuture<?>> pending = new ConcurrentHashMap<>();
  private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor(r -> {
    Thread t = new Thread(r, "realtime");
    t.setDaemon(true);
    return t;
  });

  public Realtime(Db db, ObjectMapper json) {
    this.db = db;
    this.json = json;
  }

  // ---------------------------------------------------------------- connections
  @Override
  public void afterConnectionEstablished(WebSocketSession raw) throws IOException {
    WebSocketSession s = new ConcurrentWebSocketSessionDecorator(raw, 5000, 512 * 1024);
    URI uri = raw.getUri();
    Map<String, List<String>> q = uri == null ? Map.of() : UriComponentsBuilder.fromUri(uri).build().getQueryParams();
    String token = first(q, "token");
    String guest = first(q, "guest");
    List<String> mine = new ArrayList<>();
    if (token != null && !token.isEmpty()) {
      Map<String, Object> p = Jwt.verify(java.net.URLDecoder.decode(token, java.nio.charset.StandardCharsets.UTF_8));
      Map<String, Object> u = p == null ? null : db.one("SELECT user_id, role, is_active FROM users WHERE user_id = ?", V.lng(p.get("sub")));
      if (u == null || !V.truthy(u.get("is_active"))) {
        raw.close(new CloseStatus(4001, "Session ended"));
        return;
      }
      mine.add("user:" + V.lng(u.get("user_id")));
      mine.add("role:" + u.get("role"));
    } else if (guest != null && guest.matches("^[A-Za-z0-9_-]{16,64}$")) {
      mine.add("guest:" + guest);
    } else {
      raw.close(new CloseStatus(4001, "Please log in"));
      return;
    }
    for (String r : mine) rooms.computeIfAbsent(r, k -> ConcurrentHashMap.newKeySet()).add(s);
    sessionRooms.put(raw.getId(), mine);
    raw.getAttributes().put("wrs.session", s);
  }

  @Override
  public void afterConnectionClosed(WebSocketSession raw, CloseStatus status) {
    List<String> mine = sessionRooms.remove(raw.getId());
    if (mine == null) return;
    for (String r : mine) {
      Set<WebSocketSession> set = rooms.get(r);
      if (set != null) set.removeIf(x -> x.getId().equals(raw.getId()));
    }
  }

  @Override
  protected void handleTextMessage(WebSocketSession session, TextMessage message) {
    // The app only listens; "ping" keeps the connection open.
  }

  private static String first(Map<String, List<String>> q, String k) {
    List<String> l = q.get(k);
    return l == null || l.isEmpty() ? null : l.get(0);
  }

  // ---------------------------------------------------------------- sending
  private void emit(Set<String> to, String event, Map<String, Object> data) {
    String text;
    try {
      text = json.writeValueAsString(M.of("event", event, "data", data));
    } catch (IOException e) {
      return;
    }
    Set<String> sent = new java.util.HashSet<>();
    for (String r : to) {
      Set<WebSocketSession> set = rooms.get(r);
      if (set == null) continue;
      for (WebSocketSession s : set) {
        if (!sent.add(s.getId())) continue;
        try {
          if (s.isOpen()) s.sendMessage(new TextMessage(text));
        } catch (Exception e) {
          // a closed tab; it is removed when the close arrives
        }
      }
    }
  }

  private void later(Runnable r) {
    timer.schedule(() -> {
      try {
        r.run();
      } catch (Exception e) {
        System.err.println("[realtime] " + e.getMessage());
      }
    }, 300, TimeUnit.MILLISECONDS);
  }

  /** Tells everyone who can see this order that it changed (owner, staff, its rider and its customer). */
  public void orderChanged(long orderId) {
    if (orderId <= 0) return;
    ScheduledFuture<?> old = pending.remove(orderId);
    if (old != null) old.cancel(false);
    // Wait for the database transaction to finish before the apps reload.
    pending.put(orderId, timer.schedule(() -> {
      pending.remove(orderId);
      try {
        Map<String, Object> o = db.one("SELECT order_id, status, customer_id, guest_token, rider_id FROM orders WHERE order_id = ?", orderId);
        if (o == null) return;
        Set<String> to = new LinkedHashSet<>(List.of("role:Owner", "role:Staff"));
        if (o.get("customer_id") != null) to.add("user:" + V.lng(o.get("customer_id")));
        else if (o.get("guest_token") != null) to.add("guest:" + o.get("guest_token"));
        if (o.get("rider_id") != null) to.add("user:" + V.lng(o.get("rider_id")));
        emit(to, "order", M.of("id", V.lng(o.get("order_id")), "status", o.get("status")));
      } catch (Exception e) {
        System.err.println("[realtime] " + e.getMessage());
      }
    }, 300, TimeUnit.MILLISECONDS));
  }

  /** A new in-app notification for one account or guest phone. */
  public void notification(Long userId, String guestToken, String title, String message, String type, Long orderId) {
    String room = userId != null ? "user:" + userId : guestToken != null ? "guest:" + guestToken : null;
    if (room == null) return;
    later(() -> emit(Set.of(room), "notification", M.of("title", title, "message", message, "type", type, "orderId", orderId)));
  }

  /** Rider location: owner and staff, the rider, and the customers of the rider's orders on the road. */
  public void location(long riderId, Map<String, Object> payload) {
    List<Map<String, Object>> rows = db.query(
        "SELECT customer_id, guest_token FROM orders WHERE rider_id = ? AND status = 'Out for Delivery'", riderId);
    Set<String> to = new LinkedHashSet<>(List.of("role:Owner", "role:Staff", "user:" + riderId));
    for (Map<String, Object> r : rows) to.add(r.get("customer_id") != null ? "user:" + V.lng(r.get("customer_id")) : "guest:" + r.get("guest_token"));
    Map<String, Object> data = M.of("riderId", riderId);
    data.putAll(payload);
    emit(to, "location", data);
  }

  public void locationLater(long riderId, Map<String, Object> payload) {
    later(() -> location(riderId, payload));
  }

  /** Something else the owner's screens show changed (stock, tank). */
  public void ownerRefresh(String what) {
    emit(Set.of("role:Owner", "role:Staff"), "refresh", M.of("what", what));
  }
}
